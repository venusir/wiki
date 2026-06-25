这是一份为你梳理的 **Debian IPv6 多域名 DDNS（API 令牌版）完整部署步骤总结**。

为了彻底解决“日志过大”的问题，本总结已将定时任务的日志记录方式直接优化为“仅保留最后一次最新日志（覆盖模式）”。

---

# 📝 Debian IPv6 多域名 DDNS 详细部署全流程

## 🛠️ 第一步：Cloudflare 端准备工作

1. **申请 API 令牌（Token）**：
* 登录 CF 后台 ➔ 点击右上角头像 ➔ **我的个人资料** ➔ **API 令牌** ➔ **创建令牌**。
* 选择 **编辑区域 DNS (Edit zone DNS)** 模板。
* **区域资源 (Zone Resources)** 配置：选择 `包括` ➔ `特定区域` ➔ 选中你的主域名。
* 点击创建，**复制并妥善保存生成的 API 令牌**（它长得像 `abc123XYZ...`，只出现一次）。


2. **创建占位解析记录**：
* 去 CF 的 DNS 面板中，为你计划更新的所有二级/三级域名（如 `ipv6.yourdomain.com`、`sub1.yourdomain.com`），手动创建好对应的 **AAAA 记录**。
* 记录的 IP 值随便填（如 `::1`），**按你自己的需求保持或关闭小黄云（Proxy）状态**（脚本会自动动态继承这个状态，绝不擅自修改）。



---

## 📝 第二步：Debian 端脚本部署

1. **安装必要的依赖环境**：
```bash
sudo apt update && sudo apt install curl ca-certificates nano -y

```


2. **查找并记录网卡名称**：
运行以下命令，找到挂载了你公网 `2408/2409/240a` 开头 IPv6 地址的网卡名称（通常为 `ens3`、`enp3s0` 等）：
```bash
ip -6 addr

```


3. **创建并编写脚本文件**：
```bash
sudo mkdir -p /opt/ddns
sudo nano /opt/ddns/cf_multi_ddns.sh

```


4. **粘贴最终版全自动脚本**（请务必修改顶部配置区中的 `CF_TOKEN`、`CF_ZONE_ID`、`INTERFACE` 和 `DOMAINS`）：

```bash
#!/bin/bash

# ==================== 🔑 核心配置区域 ====================
CF_TOKEN="你的_Cloudflare_API_令牌"        # 填入第一步申请的 Token
CF_ZONE_ID="你的_Zone_ID"                  # 你的 Zone ID
INTERFACE="ens3"                          # 填入你实际的 Debian 公网网卡名

# 多个需要同步更新的子域名列表（空格隔开）
DOMAINS=(
    "ipv6.yourdomain.com"
    "sub1.yourdomain.com"
    "sub2.yourdomain.com"
)
# =========================================================

# 核心原理：过滤链路本地地址(fe80)和匿名临时地址(temporary)，精准提取唯一全球单播公网 IPv6
CURRENT_IPV6=$(ip -6 addr show dev "$INTERFACE" | grep -v "deprecated" | grep -v "temporary" | awk '{print $2}' | grep -E '^(240|200)' | cut -d'/' -f1 | head -n1)

if [ -z "$CURRENT_IPV6" ]; then
    CURRENT_IPV6=$(ip -6 addr show | grep -v "deprecated" | grep -v "temporary" | awk '{print $2}' | grep -E '^(240|200)' | cut -d'/' -f1 | head -n1)
fi

if [ -z "$CURRENT_IPV6" ]; then
    echo "$(date): ❌ 错误 - 未在服务器上找到任何有效的公网 IPv6 地址！"
    exit 1
fi

echo "$(date): 🌐 探测到当前本地最新 IPv6: $CURRENT_IPV6"
echo "--------------------------------------------------"

for SUB_DOMAIN in "${DOMAINS[@]}"; do
    echo "🔍 正在处理域名: $SUB_DOMAIN ..."

    # 使用 Token 捞取当前域名的真实配置信息
    RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=AAAA&name=$SUB_DOMAIN" \
         -H "Authorization: Bearer $CF_TOKEN" \
         -H "Content-Type: application/json")

    RECORD_ID=$(echo "$RECORD_INFO" | grep -o '"id":"[^"]*' | head -n1 | cut -d'"' -f4)
    CF_IPV6=$(echo "$RECORD_INFO" | grep -o '"content":"[^"]*' | head -n1 | cut -d'"' -f4)
    CURRENT_PROXIED=$(echo "$RECORD_INFO" | grep -o '"proxied":[a-z]*' | head -n1 | cut -d':' -f2)

    if [ -z "$RECORD_ID" ]; then
        echo "   ⚠️ 警告: 未在 CF 找到 $SUB_DOMAIN 的 AAAA 记录，请先去网页端创建！"
        echo "--------------------------------------------------"
        continue
    fi
    
    if [ -z "$CURRENT_PROXIED" ]; then
        CURRENT_PROXIED="false"
    fi

    # 比对本地 IP 与 CF 现有 IP 是否一致（防刷机制）
    if [ "$CURRENT_IPV6" = "$CF_IPV6" ]; then
        echo "   ✅ IP 未发生变化 ($CF_IPV6)，跳过更新。（当前小黄云状态: $CURRENT_PROXIED）"
    else
        echo "   🔄 IP 发生变动，正在同步到 Cloudflare，保持原有代理状态: $CURRENT_PROXIED ..."
        
        # 继承 $CURRENT_PROXIED 变量进行更新，绝不擅自覆盖用户的小黄云设置
        UPDATE_RES=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$RECORD_ID" \
             -H "Authorization: Bearer $CF_TOKEN" \
             -H "Content-Type: application/json" \
             --data "{\"type\":\"AAAA\",\"name\":\"$SUB_DOMAIN\",\"content\":\"$CURRENT_IPV6\",\"ttl\":60,\"proxied\":$CURRENT_PROXIED}")

        if echo "$UPDATE_RES" | grep -q '"success":true'; then
            echo "   🎉 成功 - 已更新 $SUB_DOMAIN ➔ $CURRENT_IPV6"
        else
            echo "   ❌ 失败 - 接口报错: $UPDATE_RES"
        fi
    fi
    echo "--------------------------------------------------"
done

```

5. **赋予脚本可执行权限并进行首次手动测试**：
```bash
sudo chmod +x /opt/ddns/cf_multi_ddns.sh
sudo /opt/ddns/cf_multi_ddns.sh

```


*检查控制台输出，若未报错且 CF 后台 IP 成功刷新，说明配置完全正确。*

---

## ⏱️ 第三步：配置“双重保险”自动化触发机制

为了实现“平时 0 功耗，IP 变化瞬间同步”的完美体验，我们采用**网络事件驱动为主，定时任务覆盖覆盖覆盖为辅**的复合方案。

### 保险一：配置 Debian 底层网络事件监听（主要动力）

1. 创建 `dhclient` 自动退出钩子脚本：
```bash
sudo nano /etc/dhcp/dhclient-exit-hooks.d/cloudflare-ddns

```


2. 粘贴以下联动调度逻辑（当运营商重新分配 IPv6 前缀时，瞬间在后台拉起脚本）：
```bash
#!/bin/sh
if [ "$reason" = "BOUND6" ] || [ "$reason" = "RENEW6" ] || [ "$reason" = "REBIND6" ]; then
    /opt/ddns/cf_multi_ddns.sh > /dev/null 2>&1 &
fi

```


3. 赋予可执行权限：
```bash
sudo chmod +x /etc/dhcp/dhclient-exit-hooks.d/cloudflare-ddns

```



### 保险二：挂载长周期 Crontab 兜底定时任务（覆盖日志版）

1. 输入命令打开定时任务：
```bash
crontab -e

```


2. 移动到最底端，另起一行加入以下配置（每 6 小时检查一次。**注意使用的是单大于号 `>`，每次运行都会彻底覆盖旧文件，使日志永远只有几 KB，永不爆磁盘**）：
```text
0 */6 * * * /opt/ddns/cf_multi_ddns.sh > /opt/ddns/multi_ddns.log 2>&1

```


3. **保存退出 nano**：
* 按下 **`Ctrl + O`**，然后敲击 **`回车键 (Enter)`** 确认保存。
* 按下 **`Ctrl + X`** 退出编辑器。



---

## 🔍 日志随时查阅

无论何时，你想确认系统最后一次执行 DDNS 是成功还是失败，只需在终端输入：

```bash
cat /opt/ddns/multi_ddns.log

```

你将看到一份干净、清爽、没有任何历史垃圾废话的最新多域名同步报告。
