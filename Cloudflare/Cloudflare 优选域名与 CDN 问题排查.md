# Cloudflare 优选域名与 CDN 问题排查日志

> **来源**：[Gemini 对话分享](https://share.gemini.google/EKHm9r2sxROj)
>
> **存档日期**：2026-06-26

---

## 1. 浏览器缓存导致主域名无法访问

### 问题现象
配置 Cloudflare 优选域名加速站点后，主域名在常规浏览器窗口无法访问，但无痕模式正常。

### 根因分析
- **本地 DNS 缓存未刷新**：浏览器记住了旧的 IP 地址或错误路由
- **Service Worker / HSTS 缓存**：拦截了请求，未向新优选 IP 发起请求
- **Cookie 冲突**：旧 Session/Cookie 与 Cloudflare 新的安全校验冲突

### 解决方案
1. **最有效**：F12 打开开发者工具 → 右键刷新按钮 → **"清空缓存并硬性重新加载"**
2. 清理浏览器 Cookie 和站点数据
3. 刷新系统 DNS 缓存：`ipconfig /flushdns`（Win）/ `sudo killall -HUP mDNSResponder`（Mac）
4. 在 Cloudflare 后台清除全部 CDN 缓存

### 原理
浏览器本地缓存了旧页面/错误连接信息，直接返回缓存内容而不联网请求。**硬性重载**强制丢弃本地缓存，像无痕模式一样重新建立连接。

---

## 2. DNS TTL 设置最佳实践

### 双域名架构中的 TTL 策略

| 域名角色 | 记录类型 | 变更频率 | 推荐 TTL |
|---------|---------|---------|---------|
| 主域名（用户访问） | CNAME 指向优选域名 | 几乎不修改 | Cloudflare 代理（自动）或 10 分钟 |
| 优选域名（跑测速脚本） | A/AAAA 指向优选 IP | 频繁修改 | **60 秒 / 1 分钟** |

### 第三方优选域名场景
- 第三方优选域名 TTL 由服务商控制（通常已设为 60 秒）
- **只需管理好主域名**：
  - Cloudflare 托管 + 小黄标（Proxied）：保持自动即可
  - 纯 DNS（灰标）/国内 DNS 托管：TTL 设为系统允许的最小值（600 秒或 60 秒）

---

## 3. 自建三网自适应优选域名速度不稳定

### 根因分析
1. **IP 超载**：公开优选 IP 被大量用户共用，晚高峰触发 QoS 限速
2. **测速环境 ≠ 真实用户环境**：机房测速快 ≠ 住宅宽带快
3. **地域错配**：全国同一线路用户指向同一个 IP，忽略省份/出口差异

### 优化方案
- **自己定时测速**：用 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest) 替代公开 IP 池
- **多时段轮询**：每 15-30 分钟测速一次，测吞吐量而非仅 Ping
- **精细化分流**：按省份/地域分配不同优选 IP
- **多 IP 负载均衡**：每条线路配置 2-3 个优选 IP，配合健康检查自动切换

### 实现三网自适应的三种方案
1. **单机分段测速**：用 `-f` 参数分别对电信/联通/移动偏好 IP 段测速
2. **利用三网测速公开 API**：爬取已分类的三网 IP JSON
3. **多机分布式测速**：在电信/联通/移动各部署一台测速机

---

## 4. 多站点共用优选 IP 导致互相卡顿

### 问题现象
访问 A 网站后，B 网站奇慢无比（即使 DNS 已配置 3 个 IP）。

### 根因分析
1. **HTTP/2 连接复用（Connection Coalescing）**：同一 IP 多域名共用一条 TCP 连接
2. **浏览器单 IP 最大并发连接数限制**（通常 6 个）
3. **Cloudflare 边缘节点速率限制**：同一宽带 IP 的大量请求触发 QoS
4. **IP 粘滞性**：浏览器短期内复用同一 IP，配置多个 IP 形同虚设
5. **IP 同质化**：3 个 IP 可能属于同一边缘机房，带宽共享

### 解决方案
- **IP 分组隔离（最见效）**：A 网站用 IP1-3，B 网站用 IP4-6
- **开启 HTTP/3 (QUIC)**：基于 UDP，不同请求独立传输，避免队头阻塞
- **不同 CNAME 域名区分**：A 网站 CNAME 到 cname1，B 网站 CNAME 到 cname2

### 第三方优选域名为何不卡？
- **真随机权重轮询**：DNS 返回顺序强制随机，短时间内不同域名拿到不同 IP
- **GeoDNS 精细分流**：按省/市/ASN 返回不同 IP，IP 池庞大
- **CNAME 扁平化 + SaaS 接入**：流量的 SSL 证书链和路由上下文被独立对待

---

## 5. VLESS + WS + Nginx + CDN 代理架构优化

### 代理场景 vs 建网站场景
- **建网站**：多个域名共用同一组优选 IP → 会卡（浏览器并发限制）
- **代理/翻墙**：多网站通过同一代理节点 → **不会卡**（Vless 协议将所有连接合并为一条高效隧道，绕过浏览器限制）

### 代理场景下的潜在问题
- 多人共用同一节点 + 同一固定 IP → 高峰时段互相影响
- 触达 Cloudflare 免费用户 WebSocket 连接数/流量上限

---

## 6. Mux 多路复用在 CDN 场景下的适用性

### 结论：**VLESS + WS + Nginx + CDN 架构 → 强烈建议关闭 Mux**

### 原因
1. **触发 Cloudflare QoS 限速**：高密度单连接大流量行为类似 DDoS，被掐脖子
2. **超时断连风险**：所有请求死磕一条连接，一旦被 CDN/Nginx 判定空闲切断，全部断流
3. **TCP 队头阻塞加剧**：WS 基于 TCP，丢一个包全部卡住

### 何时开 Mux？
- 直连线路（不走 CDN）：如 VLESS + TCP + Reality
- 高延迟多小文件场景：减少 TCP 握手开销

### 正确优化姿势
- 客户端：**关闭 Mux**，保持默认并发
- Nginx：开启 keepalive，`proxy_read_timeout` 设为 300-600s
- 终极方案：将 `ws` 升级为 `gRPC`（基于 HTTP/2，天生多路复用且不影响风控）

---

## 附录：关键命令速查

### 刷新 DNS 缓存
```bash
# Windows
ipconfig /flushdns

# macOS
sudo killall -HUP mDNSResponder
```

### CloudflareSpeedTest 分段测速示例
```bash
# 电信优选
./CloudflareSpeedTest -f dx_ips.txt -o dx_result.csv

# 联通优选
./CloudflareSpeedTest -f lt_ips.txt -o lt_result.csv

# 移动优选
./CloudflareSpeedTest -f yd_ips.txt -o yd_result.csv
```

### Nginx 防缓存配置
```nginx
location ~* \.(html|htm)$ {
    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate";
}