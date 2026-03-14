### 用户环境初始化

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/init_debian_user_env.sh | sh
```

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/install_omz.sh | sh
```

### docker 安装

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/install_docker.sh | sh
```

### xray 安装

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/start_xray.sh | sh -s -- \
  --domain relay.example.com \
  --fallback-domain www.example.com \
  --cf-api-token <cloudflare-api-token>
```
