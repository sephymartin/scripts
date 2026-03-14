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

### BBR 启用

自动启用当前内核支持的最佳 BBR 版本：

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/enable_bbr.sh | sudo bash -s -- -a
```

只查看当前状态：

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/enable_bbr.sh | sudo bash -s -- -s
```

### xray 安装

```bash
curl -fsSL https://raw.githubusercontent.com/sephymartin/scripts/main/start_xray.sh | sh -s -- \
  --domain relay.example.com \
  --fallback-domain www.example.com \
  --cf-api-token <cloudflare-api-token>
```
查看客户端配置

```bash
cat ~/docker-compose/client-config.txt
```