#!/bin/sh
set -eu

COMPOSE_DIR="${HOME}/docker-compose"
LETSENCRYPT_DIR="${COMPOSE_DIR}/certbot/etc/letsencrypt"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"

echo "[$(date)] Starting certificate renewal check..."

docker compose -f "${COMPOSE_FILE}" --profile manual run --rm certbot renew \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/cloudflare.ini \
  --dns-cloudflare-propagation-seconds 60

if [ -d "${LETSENCRYPT_DIR}/live" ]; then
  chmod 755 "${LETSENCRYPT_DIR}/live" "${LETSENCRYPT_DIR}/archive" 2>/dev/null || true
fi

if [ -d "${LETSENCRYPT_DIR}/archive" ]; then
  find "${LETSENCRYPT_DIR}/archive" -name "*.pem" -exec chmod 644 {} \;
fi

if docker ps --format '{{.Names}}' | grep -q '^nginx$'; then
  docker exec nginx nginx -s reload
  echo "[$(date)] Nginx reloaded successfully"
else
  echo "[$(date)] Warning: nginx container not running, skipping reload"
fi

echo "[$(date)] Certificate renewal check completed"
