# IPv6-only VPS 节点延迟测试与自建测速地址

## 问题本质

VPS 只有 IPv6 → Cloudflare 仅转发 Web（HTTP/HTTPS/WS）→ 客户端测速需访问 HTTP 端点 → 如果没有返回 200 的页面，测试失败。

## v2rayN "真延迟" 原理

v2rayN 的"真延迟"是一次完整的代理连接建立过程：

1. 用 TCP/QUIC 连接节点入口（WS → TCP:443, H3 → QUIC:443）
2. 完成 TLS 加密握手
3. 完成协议握手（VLESS UUID 校验等）
4. 发送极小的测试数据包并等待回应
5. 记录往返时间 = 真延迟（RTT）

**关键：** v2rayN 会先对你的域名做 HTTP 探测（访问 `https://yourdomain.com/`），如果该 URL 不返回 200，延迟测试直接失败。

## 解决方案：`/ping` 端点

在 Nginx 中添加一个返回 200 的 `/ping` 路径，同时支持 v2rayN 真延迟和 mihomo url-test：

### Nginx 配置（完整版）

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate     /etc/nginx/ssl/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # 测速专用（v2rayN + mihomo）
    location /ping {
        return 200 "pong";
    }

    # VLESS + WebSocket 反代
    location /ws {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    # XHTTP / H2/H3 反代
    location /xhttp {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:20000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }

    # 禁止扫描首页
    location / {
        return 404;
    }
}
```

### 验证

```bash
curl -I https://yourdomain.com/ping
# 应返回 HTTP/2 200
```

## mihomo url-test 配置

```yaml
proxy-groups:
  - name: auto
    type: url-test
    proxies:
      - Japan
      - US
      - HK
    url: "https://yourdomain.com/ping"
    interval: 300
```

## sing-box 配置

```jsonc
{
    "url": "https://yourdomain.com/ping",
    "interval": "5m"
}
```

## 路径设计总结

| 路径 | 作用 | 客户端 |
|------|------|--------|
| `/ping` | 测速（HTTP 200） | v2rayN, mihomo, sing-box |
| `/ws` | VLESS/VMess + WebSocket | 代理 |
| `/xhttp` | VLESS + XHTTP (H2/H3) | 代理 |

## Cloudflare 注意事项

- DNS 必须开启**代理（橙色云）**，否则 IPv4 用户无法访问 IPv6-only VPS
- SSL/TLS 设为 **Full**
- 关闭 Bot Fight Mode 和 Browser Integrity Check
- 开启 HTTP/2 和 HTTP/3

## 常见错误检查清单

| 错误 | 原因 |
|------|------|
| ❌ 关闭 Cloudflare 代理（灰色云） | IPv6-only VPS 无法被 IPv4 用户访问 |
| ❌ Nginx 未监听 IPv6 | Cloudflare AAAA 解析无法访问 |
| ❌ `/ping` 未返回 200 | 延迟测试 HTTP 探测失败 |
| ❌ 防火墙未开放 80/443 | Cloudflare 无法连接 |

## 替代方案

- **伪装首页：** 不推荐，容易被扫描暴露
- **静态测速文件：** 创建 `/var/www/test/speed.txt`，适合想测一点下载速度的场景
- **Flask / Python HTTP Server：** 适合需要独立端口、加认证的高级场景