# PVE Win11 企业版全新部署指南(两阶段脚本版)

> 存档日期：2026-09-05(全流程实测 + 踩坑修订版)
>
> 环境：PVE 9.2(内核 7.0.6-2-pve)+ i3-12100 + RX 6650 XT(03:00.0 显卡 / 03:00.1 音频)+ Xbox 无线适配器(`045e:02fe`)+ WD 1TB 直通盘
>
> 注意：**需安装企业版(或专业版)才具备远程桌面(RDP)主机功能**,本文安装企业版。
>
> 本文适用**全新部署**(原 VM 已删除),全程只依赖两个脚本:阶段 A 建机 `win11-htpc-deploy.sh` → noVNC 装系统 → 阶段 B 接入 `win11-htpc-attach.sh`。所有实测踩坑已内嵌在对应步骤,文末有汇总表。

---

## 0. 总体流程与脚本获取

```
宿主机核对(§1) → 上传企业版 ISO(§2) → 阶段A deploy 建机(§3) → noVNC 装系统(§4)
  → 驱动/自动登录/RDP/AMD驱动(§5) → 关机 → 阶段B attach 接入(§6)
    → 点亮电视(§7) → 客厅软件与自启链(§8)
```

脚本在仓库 `PVE/` 目录,宿主机获取(确保最新版,见 §9 版本核对):

```bash
cd /root
curl -fLO https://raw.githubusercontent.com/venusir/wiki/main/PVE/win11-htpc-deploy.sh
curl -fLO https://raw.githubusercontent.com/venusir/wiki/main/PVE/win11-htpc-attach.sh
```

---

## 1. 宿主机前置核对(此前已配好,确认即可)

```bash
# 内核参数生效 + IOMMU 启用
dmesg | grep -i -e DMAR -e IOMMU | head -3
# 显卡已被 vfio-pci 接管(预期 03:00.0 + 03:00.1)
lspci -nnk | grep -A3 -iE 'VGA.*Advanced Micro Devices'
# Xbox 适配器在宿主上
lsusb | grep -i 045e
# 游戏盘仍在(by-id 不变)
ls -l /dev/disk/by-id/ata-WDC_WD10EZEX-08WN4A0_WD-WCC6Y2SSVDTP
```

全部正常即可继续。grep 不到 vfio-pci 就回查 Win11客厅HTPC.md 第 2 节(grub/vfio.conf/initramfs)。

---

## 2. 上传企业版 ISO

1. 下载 Windows 11 **Enterprise** ISO(授权/评估渠道自行解决;评估版注意 90 天期限,24h 常开 HTPC 建议长期授权来源);下载 **ISO 磁盘映像**,不是 Media Creation Tool
2. **⚠️ 坑:浏览器上传大文件会卡 100%**——用 scp 直传(Windows 本机 PowerShell):

```powershell
scp .\Win11_Enterprise.iso root@<PVE-IP>:/var/lib/vz/template/iso/
```

3. **⚠️ 坑:旧的家庭版 ISO 还在 iso 目录时,deploy 自动检测 `*[Ww]in*.iso` 可能选中它**——把旧 ISO 移走或删除,确保目录里只有企业版一份:

```bash
ls -lh /var/lib/vz/template/iso/
mv /var/lib/vz/template/iso/Win11_25H2_Chinese_Simplified_x64_v2.iso /root/ 2>/dev/null   # 旧的移走
```

---

## 3. 阶段 A:一键建机(win11-htpc-deploy.sh)

原 VM 已删除,VMID 200 空闲,脚本会自动复用。先审后跑:

```bash
bash win11-htpc-deploy.sh --dry-run    # 核对:ISO 识别为企业版、存储 local-lvm、VMID 200
bash win11-htpc-deploy.sh              # 输 Y 创建
```

**成功标志**(`qm config 200`):bios ovmf / efitype=4m,pre-enrolled-keys=1 / tpmstate0 v2.0 / ostype win11 / virtio-scsi-single / agent: 1。

> 脚本会自动检测/下载 virtio-win(约 600MB);缺 Windows ISO 会明确提示,不会乱跑。
>
> **坑(已修复,若脚本行为异常先核对版本)**:旧版曾出现"零输出直接退出"(detect_iso 找不到文件返回 1 触发 set -e 静默击杀)、`pvesm path` 传存储名返回空拼错路径。现版本应从 storage.cfg 读路径,并用 `--debug` 可看到逐步执行;异常时贴输出排查。

---

## 4. noVNC 安装 Windows 企业版

1. Web UI → win11-htpc → **控制台(noVNC)** → 启动
2. 到「选择磁盘」页**看不到盘是正常的** → 「加载驱动程序」→ virtio-win 光驱 → `vioscsi\w11\amd64` → 磁盘出现
3. **⚠️⚠️ 选盘警告(最易翻车)**:

| 安装程序列出的盘 | 大小 | 处置 |
| --- | --- | --- |
| QEMU 虚拟盘 | **~128 GB** | ✅ 删除其上分区 → 新建 → 安装 |
| WD(直通盘,无分区表会显示为未分配) | **~931 GB** | ❌ **绝不选中/格式化**——它是游戏盘,留到 §7 由磁盘管理处理 |

   → 判断只看容量:128GB 是系统盘。
4. OOBE:**⚠️ 坑:卡在"连接到网络"** → `Shift+F10` → `OOBE\BYPASSNRO` → 回车自动重启 → 「我没有 Internet 连接」→ 建**本地账户**(自动登录必需)。命令无效时用注册表法:

```cmd
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f
shutdown /r /t 0
```

5. 进桌面后第一件事(noVNC 分辨率低属正常)。

---

## 5. 系统配置五连(全部在 noVNC 桌面完成,顺序固定)

### 5.1 装 VirtIO 全量驱动
打开 virtio-win 光驱 → 运行 `virtio-win-gt-x64.msi` → 重启。验证:设备管理器无感叹号、能开网页。

### 5.2 验证 QEMU Agent(⚠️ 已知坑)
```cmd
sc query QEMU-GA
```
- RUNNING → PVE 面板显示 IP ✅
- **「指定的服务未安装」**(实测 MSI 装完无报错仍可能缺 GA):到光驱找独立包补装:
  ```cmd
  dir D:\qemu-ga
  msiexec /i D:\qemu-ga\x86_64\qemu-ga-x86_64.msi
  ```
  仍不行:**跳过不阻塞部署**(GA 只影响面板 IP/优雅关机)。

### 5.3 摘除安装 ISO + 引导顺序
- PVE → 硬件 → CD/DVD 驱动器 → 移除(不然重启又进安装器)
- 宿主机:`qm set 200 -boot order=scsi0`

### 5.4 自动登录(⚠️ 坑:设了仍要密码)
- 首选解锁被隐藏的 netplwiz 勾选框(企业版同样适用):
  ```cmd
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" /v DevicePasswordLessBuildVersion /t REG_DWORD /d 0 /f
  ```
  `netplwiz` → 取消勾选 → 输密码两次。
- 失效则注册表三件套:**`DefaultUserName` 必须与 `net user` 账户名完全一致**(不一致 = 重启仍问密码的根因):
  ```cmd
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d 你的用户名 /f
  reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d 你的密码 /f
  ```
- 重启验证直接进桌面。

### 5.5 启用 RDP(企业版的核心理由)+ AMD 驱动先行
```cmd
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
netsh advfirewall firewall set rule group="远程桌面" new enable=Yes
```
- `ipconfig` 记下 IPv4;从管理机 `mstsc` 连一次验证(此后 noVNC 退役)
- **趁显卡还没挂,先把 AMD Adrenalin 驱动装了**(RX 6650 XT,amd.com)——驱动进系统后,阶段 B 恢复直通时显卡一出现即自动套用,首次点亮电视成功率最高
- 全部完成后 Windows 内**关机**

> RDP 会话无 GPU 加速且破坏 HDCP:远程只做管理;影音 4K/游戏串流仍走电视直连或 Moonlight。

---

## 6. 阶段 B:直通接入(win11-htpc-attach.sh)

关机状态下,先物理接线:HDMI 插 **6650 XT 物理口**、Xbox 适配器插宿主、电视开机记下输入源。

```bash
bash win11-htpc-attach.sh --vmid 200 --dry-run    # 审:03:00.0/03:00.1、usb0、vga none、startup
bash win11-htpc-attach.sh --vmid 200              # 输 Y;交互选盘:选 WD 1TB 编号
```

**成功标志**(`qm config 200`):
```
hostpci0: 03:00.0,pcie=1,x-vga=1
hostpci1: 03:00.1,pcie=1
vga: none
usb0: host=045e:02fe,usb3=0
scsi1: /dev/disk/by-id/ata-WDC_WD10EZEX-08WN4A0_...
startup: order=1
```

> **坑(已修复)**:attach 旧版自动定位 VM 报"未找到 win11-htpc"——conf 格式是 `name: win11-htpc`(冒号后空格),正则漏空格。现版本已修;不想更新就用 `--vmid 200`。

---

## 7. 点亮电视与 Windows 收尾

1. `qm start 200` → **画面在电视**(noVNC 黑屏 = 正常);RDP 可全程远程操作
2. 设备管理器确认:Radeon RX 6650 XT / AMD High Definition Audio / Xbox Wireless Adapter
3. 显示设置:电视原生分辨率(4K 设 3840×2160);音量输出选 HDMI
4. **磁盘管理**(`Win+X`):WD 1TB 显示未初始化 → 初始化 **GPT** → 新建卷 **NTFS** → 盘符 `D:`(旧 Bazzite 数据到这一步才清空,确认无保留再动手)
5. **手柄配对**:适配器圆键 + 手柄配对键
6. 若电视无画面(回退法排查,⚠️ 坑:PVE GUI 的 PCI 设备**没有「启用」勾选项**,用命令行):

```bash
qm stop 200
qm set 200 -delete hostpci0     # 摘显卡
qm set 200 -vga std             # 回虚拟显示
qm start 200                    # noVNC 恢复
# 修复后恢复:
qm stop 200
qm set 200 -hostpci0 03:00.0,pcie=1,x-vga=1
qm set 200 -vga none
qm start 200
```

> 音频(03:00.1)与显卡独立 IOMMU group,回退时不用动;仅摘显卡时 QEMU 报 `Cannot reset device ... depends on group 10` 警告**无害,忽略**。

---

## 8. 客厅软件与自启链

Playnite 安装/平台登录 → 全屏自启(`Playnite.DesktopApp.exe --startfullscreen` + 启动文件夹)→ Edge `--app=<网址>` 流媒体条目 → HEVC 视频扩展(`ms-windows-store://pdp/?ProductId=9n4wgh0z6vhq`)→ Flirc 遥控流媒体。详见 [Win11客厅HTPC.md](Win11客厅HTPC.md) 第 9/10 节。

**自启链终验**:宿主机断电重启 → VM 自动启动 → 自动登录 → Playnite 全屏。

---

## 9. 踩坑速查表(全流程实测)

| # | 坑 | 现象 | 解决 |
| --- | --- | --- | --- |
| 1 | 浏览器上传大 ISO | 进度条卡 100% | scp 直传 `/var/lib/vz/template/iso/` |
| 2 | deploy 静默退出 | 零输出直接消失 | 旧 bug 已修;新版含 ERR 陷阱,`--debug` 可跟踪;还异常贴输出 |
| 3 | deploy ISO 路径错误 | 报 pvesm path 失败 | 旧 bug 已修(storage.cfg 读路径);确认拉到最新版 |
| 4 | attach 找不到 VM | 报"未找到 win11-htpc" | 旧 bug 已修(名称正则空格);或 `--vmid 200` |
| 5 | 脚本旧版残留 | 行为与本文不符 | 版本核对:`grep -c storage.cfg win11-htpc-deploy.sh`(≥1 为新版);attach 查 `name:[[:space:]]*win11-htpc` |
| 6 | 安装器磁盘不可见 | 选择磁盘页空白 | virtio-win 光驱 `vioscsi\w11\amd64` |
| 7 | OOBE 卡联网 | 无法下一步 | `OOBE\BYPASSNRO` / 注册表 BypassNRO |
| 8 | 选错安装盘 | 装到 WD 游戏盘上 | 只看容量:128GB 系统盘 / 931GB 直通盘 |
| 9 | 自动登录仍要密码 | 重启回到锁屏 | 解锁 netplwiz(DevicePasswordLessBuildVersion=0);核对 DefaultUserName 与账户名一致 |
| 10 | Guest Agent 未运行 | PVE 面板不显示 IP | 补装光驱 `qemu-ga\` 下 MSI;非必需可跳过 |
| 11 | noVNC 无法连接 | 打开控制台报连不上服务器 | 关旧控制台页签;`systemctl restart pveproxy` |
| 12 | 直通后 noVNC 黑屏 | 控制台无画面 | 正常!画面在电视;排查用回退法(§7) |
| 13 | PCI 设备无「启用」勾选 | GUI 编辑框找不到 | 用「移除/添加」或 `qm set -delete hostpci0` |
| 14 | 重启又进安装界面 | OVMF 光驱优先引导 | 装完移除安装 ISO + `boot order=scsi0` |
| 15 | 无原生 RDP | 需要远程控制 | 企业版/专业版才有 RDP 主机;第三方远程(RustDesk)兜底 |

---

## 10. 命令速查

```bash
# 阶段 A 建机
bash /root/win11-htpc-deploy.sh --dry-run
bash /root/win11-htpc-deploy.sh

# 阶段 B 接入(系统装好、关机后)
bash /root/win11-htpc-attach.sh --vmid 200 --dry-run
bash /root/win11-htpc-attach.sh --vmid 200

# 回退到 noVNC / 恢复直通
qm stop 200 && qm set 200 -delete hostpci0 && qm set 200 -vga std && qm start 200
qm stop 200 && qm set 200 -hostpci0 03:00.0,pcie=1,x-vga=1 && qm set 200 -vga none && qm start 200

# 挂/摘安装 ISO、引导顺序
qm set 200 -ide2 local:iso/Win11_Enterprise.iso,media=cdrom
qm set 200 -boot 'order=ide2;scsi0'
qm set 200 -boot order=scsi0
qm set 200 -delete ide2

# conf 核对
qm config 200 | grep -E '^(hostpci|usb0|vga|scsi1|startup|boot|agent)'
```

---

## 相关文档

- [Win11客厅HTPC.md](Win11客厅HTPC.md) — 主方案文档(Playnite/影音/DRM/自启链/宿主机直通准备)
- [win11-htpc-deploy.sh](win11-htpc-deploy.sh) / [win11-htpc-attach.sh](win11-htpc-attach.sh) — 两阶段部署脚本
- [Xbox适配器直通Bazzite.md](Xbox适配器直通Bazzite.md) — Linux 客户机适配器排错对照参考
