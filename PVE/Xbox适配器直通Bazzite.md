# PVE 直通 Xbox 无线适配器到 Bazzite 虚拟机

> 存档日期：2026-06-28
>
> 来源：DeepSeek 对话分享 `846945okfrhgwkq7se`
>
> 环境：Proxmox VE 9.2 + Bazzite + Xbox Wireless Adapter (`045e:02fe`)

---

## 1. 问题概述

将 Xbox 无线适配器通过 USB 直通到 PVE 中的 Bazzite 虚拟机后，**无法进入配对模式**（按适配器尾部按键无慢闪），且 `/sys/class/xone/` 目录不存在，手柄无法无线连接。

### 现象

- `lsusb` 显示 Microsoft Xbox Wireless Adapter for Windows（ID `045e:02fe`）
- `lsmod | grep xone` 显示 `xone_dongle`、`xone_gip` 驱动已加载
- `/sys/bus/usb/drivers/xone-dongle/` 中设备已绑定（`9-1:1.0` 符号链接存在）
- 但 `/sys/class/xone/` 目录缺失，缺少 `dongle0` 设备节点
- `journalctl -k | grep -i xone` 仅显示 `usbcore: registered new interface driver xone-dongle`，无固件加载日志

### 根本原因

驱动成功注册并绑定了 USB 设备，但**固件加载阶段失败**，具体原因包括：

1. **SELinux 阻止固件加载**（日志：`Permission firmware_load in class system not defined in policy`）
2. **Bazzite 不可变文件系统**无法直接写入 `/lib/firmware/`
3. **PVE 宿主机 `mt76x2u` 驱动冲突**抢占设备

---

## 2. 排查路线图

```
xone 驱动已加载 ──→ 设备已绑定 ──→ /sys/class/xone/ 不存在
                                    │
                                    ├── 固件文件缺失？
                                    ├── SELinux 阻止？
                                    ├── 宿主机驱动冲突？
                                    └── 硬件状态卡死？
```

---

## 3. 排查命令速查

### 3.1 检查适配器是否被系统识别

```bash
lsusb | grep -i microsoft
# 预期输出：Bus 009 Device 002: ID 045e:02fe Microsoft Corp. Xbox Wireless Adapter for Windows
```

### 3.2 检查 xone 驱动加载状态

```bash
lsmod | grep -E "xone|xpad"
# 预期看到 xone_dongle、xone_gip

# 检查驱动是否绑定到设备
ls -l /sys/bus/usb/drivers/xone-dongle/
# 应看到 9-1:1.0 -> ... 的符号链接
```

### 3.3 检查设备类节点是否存在

```bash
ls /sys/class/xone/
# 成功时应显示 dongle0
```

### 3.4 查看内核日志

```bash
# 查看 xone 相关日志
sudo journalctl -k | grep -i xone

# 查看固件加载错误
sudo dmesg | grep -i -E "xow|firmware.*fail|direct firmware"

# 查看 SELinux 相关日志
sudo journalctl -k | grep -i selinux
```

### 3.5 检查固件文件

```bash
ls -l /lib/firmware/xow*.bin
ls -l /usr/lib/firmware/xow*.bin
ls -l /etc/firmware/xow*.bin
ls -l /usr/local/lib/firmware/xow*.bin
```

### 3.6 PVE 宿主机冲突检查

```bash
# 在 PVE 宿主机执行
lsmod | grep mt76
# 如果有输出，说明存在驱动冲突
```

---

## 4. 解决方案

### 方案 4.1：PVE 宿主机禁用 mt76 冲突驱动

在 **PVE 宿主机**执行：

```bash
# 创建黑名单配置文件
sudo tee /etc/modprobe.d/blacklist-mt76.conf << 'EOF'
blacklist mt76
blacklist mt76x2u
blacklist mt76x2_common
blacklist mt76x02_usb
blacklist mt76_usb
blacklist mt76x02_lib

install mt76 /bin/false
install mt76x2u /bin/false
install mt76x2_common /bin/false
install mt76x02_usb /bin/false
install mt76_usb /bin/false
install mt76x02_lib /bin/false
EOF

# 更新 initramfs 并重启
sudo update-initramfs -u -k all
sudo reboot
```

重启后验证：

```bash
lsmod | grep mt76        # 应无输出
```

**注意**：禁用 mt76 只影响 MediaTek 芯片的 USB 无线网卡，不会影响普通 USB 设备（键鼠、U 盘等）。

### 方案 4.2：手动放置 xow 固件文件

在 **Bazzite 虚拟机**中执行：

```bash
# 1. 安装提取工具
rpm-ostree install cabextract

# 2. 下载 Windows 驱动包并提取固件
cd ~
curl -L -o driver.cab 'http://download.windowsupdate.com/c/msdownload/update/driver/drvs/2017/07/1cd6a87c-623f-4407-a52d-c31be49e925c_e19f60808bdcbfbd3c3df6be3e71ffc52e43261e.cab'
cabextract -F FW_ACC_00U.bin driver.cab
mv FW_ACC_00U.bin xow_dongle.bin

# 3. 复制到备用可写路径（Bazzite 的 /lib/firmware 为只读）
sudo mkdir -p /usr/local/lib/firmware
sudo cp xow_dongle.bin /usr/local/lib/firmware/

# 4. 清理临时文件
rm driver.cab
```

### 方案 4.3：处理 SELinux 阻止固件加载

**临时测试**（重启后失效）：

```bash
sudo setenforce 0
# 重新插拔适配器
ls /sys/class/xone/
```

**永久解决**（生成 SELinux 策略模块）：

```bash
sudo rpm-ostree install policycoreutils-python-utils
sudo ausearch -c 'xone-dongle' --raw | sudo audit2allow -M my-xone
sudo semodule -i my-xone.pp
```

### 方案 4.4：硬件层面解决 - 启用 BIOS ErP Ready

重启 PV E物理机，进入 BIOS：

1. 找到 **ErP Ready** 或 **ErP Support** 选项
   - 常见路径：`Advanced → APM Configuration → ErP Ready`
2. 设置为 **Enable (S4+S5)**
3. 保存并退出

**作用**：关机/休眠时彻底切断 USB 端口电源，强制适配器硬件复位，避免"卡死"状态。

**注意**：ErP Ready 是设置 **PVE 宿主机物理 BIOS**，不是 Bazzite 虚拟机的虚拟 BIOS。

### 方案 4.5：强制软重置适配器

```bash
# 安装 usbutils
rpm-ostree install usbutils

# 重置适配器
sudo usbreset 045e:02fe

# 重新加载驱动
echo "9-1:1.0" | sudo tee /sys/bus/usb/drivers/xone-dongle/unbind
sleep 2
echo "9-1:1.0" | sudo tee /sys/bus/usb/drivers/xone-dongle/bind

# 检查
ls /sys/class/xone/
```

### 方案 4.6：手动创建固件软链接（应对路径不匹配）

```bash
# 创建软链接覆盖驱动可能查找的所有文件名
sudo ln -sf /usr/local/lib/firmware/xow_dongle.bin /etc/firmware/xow_dongle.bin
sudo ln -sf /usr/local/lib/firmware/xow_dongle.bin /etc/firmware/xow_dongle_045e_02fe.bin
sudo ln -sf /usr/local/lib/firmware/xow_dongle.bin /etc/firmware/xow_dongle_045e_02e6.bin
```

---

## 5. 验证成功

执行以下命令应出现 `dongle0`：

```bash
ls /sys/class/xone/
# 预期输出：dongle0
```

强制进入配对模式（替代物理按键）：

```bash
echo 1 | sudo tee /sys/class/xone/dongle0/led
```

适配器 LED 应快速闪烁，此时按住手柄顶部配对键即可完成连接。

### 成功标志

- `/sys/class/xone/dongle0/` 目录存在
- `echo 1 | sudo tee /sys/class/xone/dongle0/led` 执行后适配器进入配对模式
- 手柄成功无线连接到 Bazzite

---

## 6. PVE USB 直通建议

修改虚拟机配置文件（`/etc/pve/qemu-server/<VMID>.conf`）：

```text
# 推荐使用 VID:PID 方式直通，强制 USB 2.0 模式
usb0: host=045e:02fe,usb3=0
```

- 用 **VID:PID** 而非端口号直通，更稳定
- `usb3=0` 强制 USB 2.0 模式，兼容性更好
- 修改后需完全关机再开机（非重启）

---

## 7. 关键经验教训

| 经验                         | 说明                                                               |
| ---------------------------- | ------------------------------------------------------------------ |
| xone 驱动已加载 ≠ 正常工作   | 即使 `lsmod` 有输出，也可能因固件未加载而无 `/sys/class/xone/`     |
| Bazzite 根文件系统只读       | `/lib/firmware/` 无法直接写入，需用 `/usr/local/lib/firmware/`     |
| PVE 宿主机驱动可能"抢走"硬件 | 即使直通给 VM，宿主机上已加载的驱动也可能先占用                    |
| SELinux 可能静默阻止         | `Permission firmware_load` 错误不会直接显示在 dmesg 的 xone 过滤中 |
| ErP Ready 解决硬件状态卡死   | 这是社区验证的"终极方案"，修复适配器休眠/重启后不工作的问题        |

---

## 8. 总结

Xbox 无线适配器在 PVE + Bazzite 环境下无法工作的核心原因是 **固件加载链断裂**：SELinux 阻止 → 固件文件缺失/路径不对 → 驱动初始化失败。通过以下组合拳解决：

1. **PVE 宿主机**：禁用 mt76 冲突驱动 → `update-initramfs -u` → 重启
2. **Bazzite 虚拟机**：手动提取固件 → 放至 `/usr/local/lib/firmware/` → 处理 SELinux
3. **BIOS**：启用 ErP Ready (S4+S5) 防止硬件状态卡死

三条链路同时打通，适配器即可正常进入配对模式。