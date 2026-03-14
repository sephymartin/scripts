#!/bin/sh
set -eu

PROGRAM_NAME=${0##*/}

DOMAIN=""
FALLBACK_DOMAIN=""
CF_API_TOKEN=""
REALITY_DEST="itunes.apple.com"
XRAY_UUID=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
CRON_SCHEDULE="0 3 * * *"
DRY_RUN=0
SKIP_DOCKER="${XRAY_SKIP_DOCKER:-0}"

INSTALL_DIR="${HOME}/docker-compose"
DATA_DIR="${HOME}/data"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
CLIENT_CONFIG_FILE="${INSTALL_DIR}/client-config.txt"
CRON_TARGET="${INSTALL_DIR}/scripts/renew-certs.sh"
MOCK_CRONTAB_FILE="${INSTALL_DIR}/.mock_crontab"

info() {
  printf '%s\n' "[INFO] $*"
}

warn() {
  printf '%s\n' "[WARN] $*" >&2
}

die() {
  printf '%s\n' "[ERROR] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  sh start_xray.sh --domain DOMAIN --fallback-domain DOMAIN --cf-api-token TOKEN [options]

Required:
  --domain DOMAIN                 Public domain used for Reality SNI routing
  --fallback-domain DOMAIN        HTTPS fallback site used by Nginx and Xray fallback
  --cf-api-token TOKEN            Cloudflare API token for Certbot DNS validation

Optional:
  --reality-dest DOMAIN           Reality destination domain (default: itunes.apple.com)
  --xray-uuid UUID                Existing Xray UUID; auto-generated when omitted
  --reality-private-key KEY       Existing Reality private key
  --reality-public-key KEY        Existing Reality public key
  --reality-short-id HEX          Existing Reality short ID; auto-generated when omitted
  --cron-schedule "M H * * *"     Cron schedule for renew-certs.sh (default: 0 3 * * *)
  --dry-run                       Render files and cron state without running Docker or Certbot
  -h, --help                      Show this help
EOF
}

require_value() {
  [ $# -ge 2 ] || die "missing value for $1"
  [ -n "$2" ] || die "missing value for $1"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --domain)
      require_value "$1" "${2-}"
      DOMAIN=$2
      shift 2
      ;;
    --fallback-domain)
      require_value "$1" "${2-}"
      FALLBACK_DOMAIN=$2
      shift 2
      ;;
    --cf-api-token)
      require_value "$1" "${2-}"
      CF_API_TOKEN=$2
      shift 2
      ;;
    --reality-dest)
      require_value "$1" "${2-}"
      REALITY_DEST=$2
      shift 2
      ;;
    --xray-uuid)
      require_value "$1" "${2-}"
      XRAY_UUID=$2
      shift 2
      ;;
    --reality-private-key)
      require_value "$1" "${2-}"
      REALITY_PRIVATE_KEY=$2
      shift 2
      ;;
    --reality-public-key)
      require_value "$1" "${2-}"
      REALITY_PUBLIC_KEY=$2
      shift 2
      ;;
    --reality-short-id)
      require_value "$1" "${2-}"
      REALITY_SHORT_ID=$2
      shift 2
      ;;
    --cron-schedule)
      require_value "$1" "${2-}"
      CRON_SCHEDULE=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[ -n "$DOMAIN" ] || die "--domain is required"
[ -n "$FALLBACK_DOMAIN" ] || die "--fallback-domain is required"
[ -n "$CF_API_TOKEN" ] || die "--cf-api-token is required"

command -v sed >/dev/null 2>&1 || die "sed is required"

if [ "$DRY_RUN" -ne 1 ]; then
  command -v docker >/dev/null 2>&1 || die "docker is required"
  command -v crontab >/dev/null 2>&1 || die "crontab is required"
fi

generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return
  fi

  if [ -r /proc/sys/kernel/random/uuid ]; then
    cat /proc/sys/kernel/random/uuid
    return
  fi

  if command -v openssl >/dev/null 2>&1; then
    uuid_raw=$(openssl rand -hex 16)
    printf '%s-%s-%s-%s-%s\n' \
      "$(printf '%s' "$uuid_raw" | cut -c1-8)" \
      "$(printf '%s' "$uuid_raw" | cut -c9-12)" \
      "$(printf '%s' "$uuid_raw" | cut -c13-16)" \
      "$(printf '%s' "$uuid_raw" | cut -c17-20)" \
      "$(printf '%s' "$uuid_raw" | cut -c21-32)"
    return
  fi

  die "unable to generate UUID"
}

generate_short_id() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 8
    return
  fi

  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
    return
  fi

  printf '%s\n' "0123456789abcdef"
}

generate_reality_keys() {
  if [ "$SKIP_DOCKER" = "1" ] || [ "$DRY_RUN" -eq 1 ]; then
    REALITY_PRIVATE_KEY="dryrun-private-key"
    REALITY_PUBLIC_KEY="dryrun-public-key"
    return
  fi

  info "Generating Reality x25519 keypair via Docker"
  set +e
  key_output=$(docker run --rm teddysun/xray xray x25519 2>&1)
  key_status=$?
  set -e

  if [ "$key_status" -ne 0 ]; then
    warn "xray x25519 exited with status $key_status"
    if [ -n "$key_output" ]; then
      warn "xray x25519 output:"
      printf '%s\n' "$key_output" >&2
    fi
  fi

  REALITY_PRIVATE_KEY=$(printf '%s\n' "$key_output" | awk -F': ' '
    $1 == "Private key" || $1 == "PrivateKey" { print $2; exit }
  ')
  REALITY_PUBLIC_KEY=$(printf '%s\n' "$key_output" | awk -F': ' '
    $1 == "Public key" || $1 == "PublicKey" || $1 == "Password" { print $2; exit }
  ')

  if [ -z "$REALITY_PRIVATE_KEY" ]; then
    warn "unable to parse Reality private key from xray x25519 output"
    if [ -n "$key_output" ]; then
      warn "xray x25519 raw output for debugging:"
      printf '%s\n' "$key_output" >&2
    fi
    die "failed to generate Reality private key"
  fi

  if [ -z "$REALITY_PUBLIC_KEY" ]; then
    warn "unable to parse Reality public key from xray x25519 output"
    if [ -n "$key_output" ]; then
      warn "xray x25519 raw output for debugging:"
      printf '%s\n' "$key_output" >&2
    fi
    die "failed to generate Reality public key"
  fi
}

escape_replacement() {
  printf '%s' "$1" | sed 's/[&|]/\\&/g'
}

render_template() {
  template_file=$1
  output_file=$2

  domain_escaped=$(escape_replacement "$DOMAIN")
  fallback_domain_escaped=$(escape_replacement "$FALLBACK_DOMAIN")
  cf_api_token_escaped=$(escape_replacement "$CF_API_TOKEN")
  reality_dest_escaped=$(escape_replacement "$REALITY_DEST")
  xray_uuid_escaped=$(escape_replacement "$XRAY_UUID")
  reality_private_key_escaped=$(escape_replacement "$REALITY_PRIVATE_KEY")
  reality_public_key_escaped=$(escape_replacement "$REALITY_PUBLIC_KEY")
  reality_short_id_escaped=$(escape_replacement "$REALITY_SHORT_ID")
  install_dir_escaped=$(escape_replacement "$INSTALL_DIR")
  data_dir_escaped=$(escape_replacement "$DATA_DIR")

  sed \
    -e "s|__DOMAIN__|$domain_escaped|g" \
    -e "s|__FALLBACK_DOMAIN__|$fallback_domain_escaped|g" \
    -e "s|__CF_API_TOKEN__|$cf_api_token_escaped|g" \
    -e "s|__REALITY_DEST__|$reality_dest_escaped|g" \
    -e "s|__REALITY_SERVER_NAME__|$reality_dest_escaped|g" \
    -e "s|__XRAY_UUID__|$xray_uuid_escaped|g" \
    -e "s|__REALITY_PRIVATE_KEY__|$reality_private_key_escaped|g" \
    -e "s|__REALITY_PUBLIC_KEY__|$reality_public_key_escaped|g" \
    -e "s|__REALITY_SHORT_ID__|$reality_short_id_escaped|g" \
    -e "s|__INSTALL_DIR__|$install_dir_escaped|g" \
    -e "s|__DATA_DIR__|$data_dir_escaped|g" \
    "$template_file" >"$output_file"
}

write_template_file() {
  target=$1
  shift

  mkdir -p "$(dirname "$target")"
  cat >"$target"
}

write_compose_file() {
  tmp_file=$(mktemp)
  cat >"$tmp_file" <<'EOF'
services:

  nginx:
    image: nginx:alpine
    container_name: nginx
    ports:
      - 80:8080
      - 443:8443
    volumes:
      - __INSTALL_DIR__/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - __INSTALL_DIR__/nginx/conf.d/:/etc/nginx/conf.d/:ro
      - __INSTALL_DIR__/nginx/stream.d/:/etc/nginx/stream.d/:ro
      - __INSTALL_DIR__/nginx/snippets/:/etc/nginx/snippets/:ro
      - __INSTALL_DIR__/nginx/cert/:/etc/cert/:ro
      - __INSTALL_DIR__/nginx/auth/:/etc/nginx/auth/:ro
      - __INSTALL_DIR__/certbot/etc/letsencrypt/:/etc/letsencrypt/:ro
      - __DATA_DIR__/nginx/logs/:/var/log/nginx/
    extra_hosts:
      - "host.docker.internal:host-gateway"
    depends_on:
      - xray
    deploy:
      resources:
        limits:
          memory: 64M
    restart: unless-stopped

  xray:
    image: teddysun/xray
    container_name: xray
    volumes:
      - __INSTALL_DIR__/xray/:/etc/xray:ro
    restart: unless-stopped

  certbot:
    image: certbot/dns-cloudflare
    container_name: certbot
    environment:
      - TZ=Asia/Shanghai
    volumes:
      - __INSTALL_DIR__/certbot/etc/letsencrypt:/etc/letsencrypt
      - __DATA_DIR__/certbot/var/lib/letsencrypt:/var/lib/letsencrypt
      - __DATA_DIR__/certbot/var/log/letsencrypt:/var/log/letsencrypt
      - __INSTALL_DIR__/certbot/cloudflare.ini:/etc/cloudflare.ini:ro
    profiles:
      - manual
EOF
  render_template "$tmp_file" "$COMPOSE_FILE"
  rm -f "$tmp_file"
}

write_xray_config() {
  tmp_file=$(mktemp)
  cat >"$tmp_file" <<'EOF'
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "servers": [
            "https://1.1.1.1/dns-query",
            "https://8.8.8.8/dns-query"
        ],
        "queryStrategy": "UseIPv4"
    },
    "api": {
        "services": [
            "HandlerService",
            "LoggerService",
            "StatsService"
        ],
        "tag": "api"
    },
    "stats": {},
    "policy": {
        "levels": {
            "0": {
                "handshake": 4,
                "connIdle": 300,
                "uplinkOnly": 2,
                "downlinkOnly": 5,
                "bufferSize": 32,
                "statsUserUplink": true,
                "statsUserDownlink": true
            }
        },
        "system": {
            "statsInboundUplink": true,
            "statsInboundDownlink": true,
            "statsOutboundUplink": true,
            "statsOutboundDownlink": true
        }
    },
    "inbounds": [
        {
            "listen": "0.0.0.0",
            "port": 6443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "__XRAY_UUID__",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "__FALLBACK_DOMAIN__:443",
                        "xver": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "__REALITY_DEST__:443",
                    "xver": 0,
                    "serverNames": [
                        "__REALITY_SERVER_NAME__"
                    ],
                    "privateKey": "__REALITY_PRIVATE_KEY__",
                    "shortIds": [
                        "",
                        "__REALITY_SHORT_ID__"
                    ]
                },
                "tcpSettings": {
                    "acceptProxyProtocol": true
                }
            },
            "tag": "vless-reality-in",
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic", "fakedns"]
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct-out"
        },
        {
            "protocol": "blackhole",
            "tag": "block",
            "settings": {
                "response": {
                    "type": "none"
                }
            }
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "protocol": ["bittorrent"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "domain": ["geosite:category-ads-all"],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": [
                    "geoip:cn",
                    "geoip:private"
                ],
                "outboundTag": "block"
            }
        ]
    }
}
EOF
  render_template "$tmp_file" "${INSTALL_DIR}/xray/config.json"
  rm -f "$tmp_file"
}

write_nginx_files() {
  write_template_file "${INSTALL_DIR}/nginx/nginx.conf" <<'EOF'
worker_processes auto;

error_log /var/log/nginx/error.log notice;
pid /tmp/nginx.pid;

worker_rlimit_nofile 65535;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

stream {
    include /etc/nginx/stream.d/*.conf;
}

http {
    proxy_temp_path /tmp/proxy_temp;
    client_body_temp_path /tmp/client_temp;
    fastcgi_temp_path /tmp/fastcgi_temp;
    uwsgi_temp_path /tmp/uwsgi_temp;
    scgi_temp_path /tmp/scgi_temp;

    include /etc/nginx/snippets/performance.conf;
    include /etc/nginx/snippets/logging.conf;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    map $upstream_response_time $upstream_response_timer {
        default $upstream_response_time;
        "" 0;
    }

    map $http_x_forwarded_proto $x_forwarded_proto {
        default $http_x_forwarded_proto;
        ""      $scheme;
    }

    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
    '$status $body_bytes_sent "$http_referer" '
    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log json_combined;

    sendfile on;
    keepalive_timeout 65;
    keepalive_requests 1000;

    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_comp_level 5;
    gzip_types
    text/css
    text/javascript
    text/xml
    text/plain
    text/x-component
    application/javascript
    application/json
    application/xml
    application/x-javascript
    application/rss+xml
    application/xml+rss
    font/truetype
    font/opentype
    application/vnd.ms-fontobject
    image/svg+xml;

    gzip_static on;
    gzip_proxied expired no-cache no-store private auth;
    gzip_vary on;

    include /etc/nginx/conf.d/*.conf;
}
EOF

  write_template_file "${INSTALL_DIR}/nginx/snippets/proxy-common.conf" <<'EOF'
proxy_http_version 1.1;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $x_forwarded_proto;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;

proxy_connect_timeout 60s;
proxy_send_timeout 60s;
proxy_read_timeout 60s;

proxy_buffering on;
proxy_buffer_size 4k;
proxy_buffers 8 16k;
proxy_busy_buffers_size 24k;
EOF

  write_template_file "${INSTALL_DIR}/nginx/snippets/logging.conf" <<'EOF'
log_format json_combined escape=json
    '{'
    '"time_local":"$time_local",'
    '"remote_addr":"$remote_addr",'
    '"remote_user":"$remote_user",'
    '"request":"$request",'
    '"status": "$status",'
    '"body_bytes_sent":"$body_bytes_sent",'
    '"request_time":"$request_time",'
    '"http_referrer":"$http_referer",'
    '"http_user_agent":"$http_user_agent",'
    '"http_x_forwarded_for":"$http_x_forwarded_for",'
    '"upstream_response_time":"$upstream_response_time",'
    '"upstream_addr":"$upstream_addr"'
    '}';
EOF

  write_template_file "${INSTALL_DIR}/nginx/snippets/performance.conf" <<'EOF'
tcp_nopush on;
tcp_nodelay on;

client_body_buffer_size 16k;
client_header_buffer_size 1k;
client_max_body_size 64m;
large_client_header_buffers 4 8k;

client_body_timeout 60s;
client_header_timeout 60s;
send_timeout 60s;

open_file_cache max=10000 inactive=30s;
open_file_cache_valid 60s;
open_file_cache_min_uses 2;
open_file_cache_errors on;
EOF

  tmp_site=$(mktemp)
  cat >"$tmp_site" <<'EOF'
server {
    resolver 127.0.0.11 valid=30s ipv6=off;
    listen [::]:80;
    listen 80;
    server_name __DOMAIN__;
    return 301 https://$host$request_uri;
}

server {
    resolver 127.0.0.11 valid=30s ipv6=off;
    listen 9443 ssl;
    server_name __DOMAIN__ proxy_protocol ssl http2;

    ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/__DOMAIN__/chain.pem;

    proxy_set_header Host $http_host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $x_forwarded_proto;
    proxy_set_header REMOTE-HOST $remote_addr;

    proxy_buffering off;
    proxy_request_buffering off;

    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    access_log /var/log/nginx/__DOMAIN__.log json_combined;

    location / {
        proxy_ssl_server_name on;
        proxy_ssl_session_reuse off;
        proxy_ssl_name __FALLBACK_DOMAIN__;
        proxy_pass https://__FALLBACK_DOMAIN__:443/;
        proxy_set_header Host __FALLBACK_DOMAIN__;
        include /etc/nginx/snippets/proxy-common.conf;
    }
}
EOF
  render_template "$tmp_site" "${INSTALL_DIR}/nginx/conf.d/${DOMAIN}.conf"
  rm -f "$tmp_site"

  tmp_default=$(mktemp)
  cat >"$tmp_default" <<'EOF'
server {
    listen 8080 default_server;
    listen [::]:8080 default_server;
    server_name _;

    location /health {
        return 200 'OK\n';
        add_header Content-Type text/plain;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 9443 ssl proxy_protocol default_server;
    listen [::]:9443 ssl proxy_protocol default_server;
    http2 on;
    server_name _;

    set_real_ip_from 127.0.0.0/8;
    set_real_ip_from 10.0.0.0/8;
    set_real_ip_from 172.16.0.0/12;
    set_real_ip_from 192.168.0.0/16;
    real_ip_header proxy_protocol;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;

    server_tokens off;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    access_log /var/log/nginx/default_https.log json_combined;

    location / {
        proxy_ssl_server_name on;
        proxy_ssl_name __FALLBACK_DOMAIN__;
        proxy_pass https://__FALLBACK_DOMAIN__:443/;
        proxy_set_header Host __FALLBACK_DOMAIN__;
        include /etc/nginx/snippets/proxy-common.conf;
    }
}
EOF
  render_template "$tmp_default" "${INSTALL_DIR}/nginx/conf.d/default.conf"
  rm -f "$tmp_default"

  tmp_sni=$(mktemp)
  cat >"$tmp_sni" <<'EOF'
upstream xray_backend {
    server xray:6443;
}

upstream nginx_https {
    server 127.0.0.1:9443;
}

map $ssl_preread_server_name $backend_name {
    __DOMAIN__      xray_backend;
    default         nginx_https;
}

server {
    listen 8443;
    listen [::]:8443;

    proxy_pass $backend_name;
    proxy_protocol on;
    ssl_preread on;
}
EOF
  render_template "$tmp_sni" "${INSTALL_DIR}/nginx/stream.d/sni.conf"
  rm -f "$tmp_sni"
}

write_certbot_files() {
  write_template_file "${INSTALL_DIR}/certbot/cloudflare.ini" <<'EOF'
# Cloudflare API token used by Certbot
dns_cloudflare_api_token = __CF_API_TOKEN__
EOF
  tmp_file=$(mktemp)
  render_template "${INSTALL_DIR}/certbot/cloudflare.ini" "$tmp_file"
  mv "$tmp_file" "${INSTALL_DIR}/certbot/cloudflare.ini"
  chmod 600 "${INSTALL_DIR}/certbot/cloudflare.ini"

  mkdir -p "${INSTALL_DIR}/certbot/etc/letsencrypt/live"
  write_template_file "${INSTALL_DIR}/certbot/etc/letsencrypt/live/README" <<'EOF'
This directory stores Let's Encrypt certificates for the generated stack.
EOF
}

write_renew_script() {
  renewal_file="${INSTALL_DIR}/scripts/renew-certs.sh"
  mkdir -p "$(dirname "$renewal_file")"
  cat >"$renewal_file" <<EOF
#!/bin/sh
set -eu

COMPOSE_DIR="${INSTALL_DIR}"
LETSENCRYPT_DIR="\${COMPOSE_DIR}/certbot/etc/letsencrypt"
COMPOSE_FILE="\${COMPOSE_DIR}/docker-compose.yml"

echo "[\$(date)] Starting certificate renewal check..."

docker compose -f "\${COMPOSE_FILE}" --profile manual run --rm certbot renew \\
  --dns-cloudflare \\
  --dns-cloudflare-credentials /etc/cloudflare.ini \\
  --dns-cloudflare-propagation-seconds 60

if [ -d "\${LETSENCRYPT_DIR}/live" ]; then
  chmod 755 "\${LETSENCRYPT_DIR}/live" "\${LETSENCRYPT_DIR}/archive" 2>/dev/null || true
fi

if [ -d "\${LETSENCRYPT_DIR}/archive" ]; then
  find "\${LETSENCRYPT_DIR}/archive" -name "*.pem" -exec chmod 644 {} \;
fi

if docker ps --format '{{.Names}}' | grep -q '^nginx$'; then
  docker exec nginx nginx -s reload
  echo "[\$(date)] Nginx reloaded successfully"
else
  echo "[\$(date)] Warning: nginx container not running, skipping reload"
fi

echo "[\$(date)] Certificate renewal check completed"
EOF
  chmod 755 "$renewal_file"
}

write_client_config() {
  cat >"$CLIENT_CONFIG_FILE" <<EOF
# Xray client configuration
# Generated: $(date)

域名: ${DOMAIN}
端口: 443
协议: VLESS
UUID: ${XRAY_UUID}
传输方式: TCP
安全: Reality
Reality Server Name: ${REALITY_DEST}
Reality Public Key: ${REALITY_PUBLIC_KEY}
Reality Short ID: ${REALITY_SHORT_ID}
EOF
}

ensure_directories() {
  mkdir -p "${INSTALL_DIR}/xray"
  mkdir -p "${INSTALL_DIR}/nginx/conf.d"
  mkdir -p "${INSTALL_DIR}/nginx/stream.d"
  mkdir -p "${INSTALL_DIR}/nginx/snippets"
  mkdir -p "${INSTALL_DIR}/nginx/auth"
  mkdir -p "${INSTALL_DIR}/nginx/cert"
  mkdir -p "${DATA_DIR}/nginx/logs"
  mkdir -p "${DATA_DIR}/certbot/var/lib/letsencrypt"
  mkdir -p "${DATA_DIR}/certbot/var/log/letsencrypt"
}

install_cron_job() {
  cron_line="${CRON_SCHEDULE} ${CRON_TARGET} >> ${DATA_DIR}/certbot/var/log/letsencrypt/renew-cron.log 2>&1"

  if [ "$DRY_RUN" -eq 1 ]; then
    existing_crontab=""
    if [ -f "$MOCK_CRONTAB_FILE" ]; then
      existing_crontab=$(cat "$MOCK_CRONTAB_FILE")
    fi

    if printf '%s\n' "$existing_crontab" | grep -F "$CRON_TARGET" >/dev/null 2>&1; then
      printf '%s\n' "$existing_crontab" >"$MOCK_CRONTAB_FILE"
    else
      if [ -n "$existing_crontab" ]; then
        printf '%s\n%s\n' "$existing_crontab" "$cron_line" >"$MOCK_CRONTAB_FILE"
      else
        printf '%s\n' "$cron_line" >"$MOCK_CRONTAB_FILE"
      fi
    fi
    return
  fi

  current_crontab=$(crontab -l 2>/dev/null || true)
  if printf '%s\n' "$current_crontab" | grep -F "$CRON_TARGET" >/dev/null 2>&1; then
    info "Renewal cron entry already present"
    return
  fi

  if [ -n "$current_crontab" ]; then
    printf '%s\n%s\n' "$current_crontab" "$cron_line" | crontab -
  else
    printf '%s\n' "$cron_line" | crontab -
  fi
}

issue_certificate_if_needed() {
  cert_path="${INSTALL_DIR}/certbot/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
  if [ -f "$cert_path" ]; then
    info "Existing certificate found for ${DOMAIN}, skipping initial certbot request"
    return
  fi

  info "Requesting initial certificate for ${DOMAIN}"
  docker compose -f "$COMPOSE_FILE" --profile manual run --rm certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 60 \
    -d "$DOMAIN"
}

start_services() {
  info "Starting Docker Compose stack"
  docker compose -f "$COMPOSE_FILE" up -d
}

[ -n "$XRAY_UUID" ] || XRAY_UUID=$(generate_uuid)
[ -n "$REALITY_SHORT_ID" ] || REALITY_SHORT_ID=$(generate_short_id)
if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
  generate_reality_keys
fi

ensure_directories
write_compose_file
write_xray_config
write_nginx_files
write_certbot_files
write_renew_script
write_client_config
install_cron_job

info "VLESS Reality bootstrap files written to ${INSTALL_DIR}"
info "Client config saved to ${CLIENT_CONFIG_FILE}"

if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run enabled, skipped Docker and Certbot execution"
  exit 0
fi

issue_certificate_if_needed
start_services

cat <<EOF

Install complete.
Domain: ${DOMAIN}
UUID: ${XRAY_UUID}
Reality Server Name: ${REALITY_DEST}
Reality Public Key: ${REALITY_PUBLIC_KEY}
Reality Short ID: ${REALITY_SHORT_ID}
Client config file: ${CLIENT_CONFIG_FILE}
EOF
