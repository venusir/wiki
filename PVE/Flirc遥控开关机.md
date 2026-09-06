# PVE + Flirc + TriggerHappy 遥控器一键启动虚拟机方案

> 存档日期：2026-06-28
>
> 来源：DeepSeek 对话分享 `846945okfrhgwkq7se`
>
> 最终方案：**PVE + Bazzite + Flirc USB 红外接收器 + TriggerHappy + Proxmox VE API Token**

---

## 1. 方案概述

利用 **Flirc USB 红外接收器** 将任意红外遥控器（如电视遥控器）的按键信号转换为标准键盘按键（KEY_F12），配合 **triggerhappy** 在 PVE 宿主机上监听该按键，并通过 **Proxmox VE API Token** 认证调用 `curl` 启动指定的虚拟机（如 Bazzite 游戏系统）。

### 方案优势

- **无需网络**：完全本地化硬件通路，不受网络波动影响
- **响应迅速**：红外信号延迟极低
- **无需 Homelab 关机**：PVE 宿主机 24h 运行也不影响
- **即插即用**：Flirc 配置存储在设备内部，跨平台无需重配
- **稳定可靠**：triggerhappy 是 Debian 官方工具，久经考验

---

## 2. 探索历程与方案演进

| 方案                                   | 核心思路                        | 放弃原因                                    |
| -------------------------------------- | ------------------------------- | ------------------------------------------- |
| BIOS USB 唤醒 + 直通接收器             | Xbox 手柄唤醒物理机             | 需关机宿主机，与 NAS 需求冲突               |
| PCIe 直通 USB 控制器                   | 完整接管物理 USB 端口           | 仅有一个 USB 控制器，直通后宿主机失联       |
| SPICE USB 重定向 + 钩子脚本            | 虚拟机关闭后适配器归还宿主      | 宿主机无法监听已直通设备的按键信号          |
| **Flirc + evsieve**                    | 红外接收器模拟键盘 + 事件监听   | evsieve 参数语法兼容性差，反复调试失败      |
| **Flirc + triggerhappy** ✅             | 改用成熟稳定的 triggerhappy     | qm/pvesh 在服务环境下因缺少认证上下文而失败 |
| **Flirc + triggerhappy + API Token** 🎯 | 最终方案：curl 调用 Proxmox API | ✅ 成功                                      |

### 关键突破点

1. **evsieve 弃用**：evsieve 1.4.0 的 `--hook` 参数格式在不同版本间差异大（`KEY_F12` / `key:KEY_F12` / `KEY_F12:1` / `ev:KEY_F12` 均尝试失败），最终改用 triggerhappy

2. **triggerhappy 环境问题**：triggerhappy 服务执行脚本时 `HOME=/` 且无 PVE 会话票证，导致 `qm start` 返回 `exit code 255`（IPC/ACL 错误）

3. **API Token 终极方案**：创建 `root@pam!triggerhappy` Token，使用 `curl` 直接调用 REST API，完全绕过会话依赖

---

## 3. 所需硬件与软件

### 硬件

| 物品                 | 说明                                      |
| -------------------- | ----------------------------------------- |
| Proxmox VE 宿主机    | 需 24h 运行                               |
| Flirc USB 接收器     | [flirc.tv](https://flirc.tv) 购买，约 $20 |
| 任意红外遥控器       | 电视/机顶盒/空调遥控器均可                |
| Windows PC（一次性） | 用于 Flirc GUI 按键映射                   |

### 软件

- Proxmox VE 8.x / 9.x
- `triggerhappy`（apt 安装）
- `evtest`（调试用，可选）

---

## 4. 完整部署步骤

### 步骤 1：在 Windows 上映射 Flirc 按键

Flirc 的按键映射存储在设备内部 EEPROM，配置后即插即用于任何系统。

1. 下载安装 [Flirc GUI](https://flirc.tv/software)
2. 插入 Flirc，打开软件
3. 选择 **Controllers → Full Keyboard**（全键盘模式）
4. 在虚拟键盘上点击 **F12**（或你偏好的其他按键）
5. 软件提示"请按下遥控器按钮"时，按下遥控器上的目标按键
6. 提示 **Recorded Successfully** 即成功
7. 可选：File → Save Configuration 备份配置
8. 拔出 Flirc，插入 PVE 宿主机 USB 口

**注意**：建议选择遥控器上不常用的按键（如红色电源键、Favorites 键），避免与电视正常操作冲突。

### 步骤 2：在 PVE 宿主机安装 triggerhappy

```bash
apt update
apt install -y triggerhappy
```

### 步骤 3：验证 Flirc 设备与按键

```bash
# 查找 Flirc 设备路径
ls /dev/input/by-id/*flirc*

# 示例输出：/dev/input/by-id/usb-flirc.tv_flirc_xxxx-if01-event-kbd

# 安装 evtest 并监听
apt install -y evtest
evtest /dev/input/by-id/usb-flirc.tv_flirc_xxxx-if01-event-kbd
```

按下遥控器按键，确认输出包含：

```
Event: time ... type 1 (EV_KEY), code 88 (KEY_F12), value 1
```

记录按键名：**KEY_F12**。按 `Ctrl+C` 退出。

### 步骤 4：创建 Proxmox VE API Token

#### 4.1 在 Web 界面创建

1. 登录 PVE Web 管理界面
2. 点击 **Datacenter → Permissions → API Tokens**
3. 点击 **Add**：
   - User：`root@pam`
   - Token ID：`triggerhappy`
   - Privilege Separation：**不勾选**（继承 root 权限，最简单）
4. 点击 Add，弹出窗口显示 **Secret**（Token 密钥）
5. **⚠️ 务必立即复制保存**，关闭后无法再次查看

记录信息：
- Token ID：`root@pam!triggerhappy`
- Secret：`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

#### 4.2 编写启动脚本

```bash
nano /usr/local/bin/start-bazzite-vm.sh
```

粘贴以下内容（**替换 `SECRET` 为实际值**）：

```bash
#!/bin/bash

VM_ID="100"                               # 你的虚拟机 ID
PVE_HOST="localhost"                      # PVE 主机地址
NODE_NAME="localhost"                     # 节点名称
TOKEN_ID="root@pam!triggerhappy"          # API Token ID
SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # 你的 Secret

LOG_FILE="/tmp/bazzite-api.log"

echo "$(date): Script executed." >> $LOG_FILE

response=$(curl --silent --insecure -X POST \
  -H "Authorization: PVEAPIToken=$TOKEN_ID=$SECRET" \
  "https://$PVE_HOST:8006/api2/json/nodes/$NODE_NAME/qemu/$VM_ID/status/start")

echo "$(date): API response - $response" >> $LOG_FILE

if echo "$response" | grep -q '"data":null'; then
    echo "$(date): VM $VM_ID started successfully." >> $LOG_FILE
else
    echo "$(date): Failed to start VM $VM_ID." >> $LOG_FILE
fi
```

赋予执行权限：

```bash
chmod +x /usr/local/bin/start-bazzite-vm.sh
```

#### 4.3 手动测试脚本

```bash
qm stop 100
/usr/local/bin/start-bazzite-vm.sh
qm status 100       # 应显示 status: running
cat /tmp/bazzite-api.log
```

若日志中 API 返回 `{"data":null}` 且虚拟机启动成功，则脚本正常。

### 步骤 5：配置 triggerhappy 规则

创建规则文件：

```bash
echo "KEY_F12 1 /usr/local/bin/start-bazzite-vm.sh" > /etc/triggerhappy/triggers.d/bazzite-start.conf
```

重启服务并设置开机自启：

```bash
systemctl restart triggerhappy
systemctl enable triggerhappy
```

### 步骤 6：最终测试

1. 确保虚拟机已关闭：`qm stop 100`
2. 按下遥控器上已映射的按键
3. 等待 2-3 秒，检查状态：`qm status 100` → 应显示 `running`
4. 查看日志：

```bash
journalctl -u triggerhappy -f
cat /tmp/bazzite-api.log
```

---

## 5. 防重复启动（可选增强）

当前脚本每次按键都会调用 API，即使 VM 已运行也会发送启动请求（API 会返回错误但不影响）。

如需严格防重复启动，可将脚本改为：

```bash
#!/bin/bash

VM_ID="100"
PVE_HOST="localhost"
NODE_NAME="localhost"
TOKEN_ID="root@pam!triggerhappy"
SECRET="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

LOG_FILE="/tmp/bazzite-api.log"

echo "$(date): Script executed." >> $LOG_FILE

# 先查询当前状态
status_response=$(curl --silent --insecure \
  -H "Authorization: PVEAPIToken=$TOKEN_ID=$SECRET" \
  "https://$PVE_HOST:8006/api2/json/nodes/$NODE_NAME/qemu/$VM_ID/status/current")

echo "$(date): Status check - $status_response" >> $LOG_FILE

if echo "$status_response" | grep -q '"status":"running"'; then
    echo "$(date): VM already running, ignoring." >> $LOG_FILE
else
    response=$(curl --silent --insecure -X POST \
      -H "Authorization: PVEAPIToken=$TOKEN_ID=$SECRET" \
      "https://$PVE_HOST:8006/api2/json/nodes/$NODE_NAME/qemu/$VM_ID/status/start")
    
    echo "$(date): Start response - $response" >> $LOG_FILE
    
    if echo "$response" | grep -q '"data":null'; then
        echo "$(date): VM $VM_ID started successfully." >> $LOG_FILE
    else
        echo "$(date): Failed to start VM $VM_ID." >> $LOG_FILE
    fi
fi
```

---

## 6. 故障排查速查表

| 现象                             | 可能原因                  | 排查方法                                              |
| -------------------------------- | ------------------------- | ----------------------------------------------------- |
| 按遥控器无反应                   | Flirc 未识别              | `lsusb \| grep -i flirc`                              |
|                                  | 按键未映射                | 回到 Windows Flirc GUI 重新学习                       |
| evtest 能捕获但 VM 不启动        | triggerhappy 未运行       | `systemctl status triggerhappy`                       |
|                                  | 规则配置错误              | `cat /etc/triggerhappy/triggers.d/bazzite-start.conf` |
| API 返回 401                     | Token ID 或 Secret 错误   | 核对脚本中的值，必要时重新创建 Token                  |
| 手动脚本启动成功，遥控器启动失败 | triggerhappy 执行环境问题 | `journalctl -u triggerhappy -e`                       |
| qm start 返回 exit code 255      | 缺少认证上下文            | 已通过 API Token 方案解决                             |
| 启动时 PCI reset 警告            | 直通设备正常现象          | 忽略，不影响启动                                      |

### 调试命令速查

```bash
# 检查 Flirc 设备
lsusb | grep -i flirc
ls /dev/input/by-id/*flirc*

# 实时监听按键
evtest /dev/input/by-id/usb-flirc.tv_flirc_xxx-if01-event-kbd

# triggerhappy 服务状态与日志
systemctl status triggerhappy
journalctl -u triggerhappy -f

# 查看 API 调用日志
cat /tmp/bazzite-api.log

# 测试脚本
/usr/local/bin/start-bazzite-vm.sh

# 虚拟机状态
qm status 100
```

---

## 7. 扩展：遥控器关机

若需实现遥控器一键关机，可将另一个按键映射为 `KEY_F11`，创建类似脚本：

```bash
# 关机脚本 /usr/local/bin/stop-bazzite-vm.sh
response=$(curl --silent --insecure -X POST \
  -H "Authorization: PVEAPIToken=$TOKEN_ID=$SECRET" \
  "https://$PVE_HOST:8006/api2/json/nodes/$NODE_NAME/qemu/$VM_ID/status/stop")
```

并添加 triggerhappy 规则：

```bash
echo "KEY_F11 1 /usr/local/bin/stop-bazzite-vm.sh" > /etc/triggerhappy/triggers.d/bazzite-stop.conf
systemctl restart triggerhappy
```

---

## 8. 安全建议

1. **Token 权限最小化**：可创建专用 PVE 用户（非 root），仅赋予 `PVEVMAdmin` 角色
2. **脚本权限**：`chmod 700 /usr/local/bin/start-bazzite-vm.sh` 仅 root 可读
3. **Secret 保护**：避免将 Token 写入版本控制（如 GitHub）
4. **HTTPS 证书**：如对外暴露 PVE API，请配置有效 SSL 证书（替换 `--insecure`）

---

## 9. 总结

经过约 3 小时的深度调试，从最初 "Xbox 手柄唤醒" 的设想，逐步排查了 USB 控制器直通、SPICE 重定向、evsieve 参数语法、triggerhappy 环境认证等一系列技术障碍，最终通过 **Flirc USB 红外接收器 + triggerhappy + Proxmox VE API Token** 的组合方案，成功实现了 **用电视遥控器一键启动 PVE 中 Bazzite 虚拟机** 的目标。

此方案稳定、低延迟、无需网络，完美融入家庭影音/游戏场景。按下遥控器的瞬间，Bazzite 游戏系统应声启动 —— 这就是 Homelab 折腾的终极浪漫。