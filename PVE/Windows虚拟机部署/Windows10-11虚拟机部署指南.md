# PVE 部署 Windows 10/11 虚拟机指南

> 存档日期:2026-09-05(全流程实测修订版)
>
> 适用:Proxmox VE 8.x/9.x;Windows 10 / Windows 11
> 实测环境:i3-12100 + RX 6650 XT(显卡直通示例)+ PVE 9.2
>
> 本文为**通用部署主流程**,基于两阶段脚本;直通/排错细节吸收自实际部署全过程的踩坑记录(存档见本目录其他文档)。

---

## 1. 总览与文档地图

```
宿主机前置核对(§2) → 上传系统 ISO(§3) → 阶段A 建机脚本(§4) → noVNC 装系统(§5)
  → 系统配置五连(§6) → 阶段B 接入直通(§7) → 点亮画面与收尾(§8)
```

- 脚本:**win11-htpc-deploy.sh**(建机)、**win11-htpc-attach.sh**(直通接入)——通用可用,名称沿用原项目,不影响使用
- Windows 10 与 11 的差异点已内嵌标注(主要是 Win11 强制 TPM/UEFI,Win10 无此要求但推荐同一套配置)

## 2. 宿主机前置(一次性)

```bash
# 内核参数生效 + IOMMU 启用(预期有 DMAR/IOMMU 输出)
dmesg | grep -i -e DMAR -e IOMMU | head -3
# 待直通显卡已被 vfio-pci 接管
lspci -nnk | grep -A3 -iE 'VGA|Display controller'
```

未配置过直通的机器按以下就位(Intel CPU 示例):
1. BIOS:开 **VT-d**、**Above 4G Decoding**(大显存卡必需)、ErP(可选)
2. `/etc/default/grub` 的 `GRUB_CMDLINE_LINUX_DEFAULT` 追加 `intel_iommu=on iommu=pt` → `update-grub` → 重启
3. `/etc/modprobe.d/vfio.conf` 写 `options vfio-pci ids=<显卡ID>,<音频ID>`(以 `lspci -nn` 实测为准),`/etc/modules` 加 `vfio vfio_iommu_type1 vfio_pci` → `update-initramfs -u -k all` → 重启
4. 验证:`lspci -nnk` 显示 `Kernel driver in use: vfio-pci`

## 3. 系统镜像准备

1. 微软官网下载 Win10/11 **ISO**(Windows 11 注意选对版本:**家庭版/专业版镜像不包含企业版**;远程桌面 RDP 主机功能仅专业版/企业版有,家庭版只能第三方远程)
2. **⚠️ 大文件别用浏览器上传**(卡 100% 经典坑)——scp 直传:

```powershell
scp .\Win11.iso root@<PVE-IP>:/var/lib/vz/template/iso/
```

3. **⚠️ ISO 目录里保留多个 Windows 镜像时,deploy 脚本自动检测可能选错**——只留要用的那份,或建机时用 `--win-iso` 显式指定

## 4. 阶段 A:一键建机

```bash
bash win11-htpc-deploy.sh --dry-run    # 核对 ISO/存储/VMID
bash win11-htpc-deploy.sh              # 输 Y 创建
```

创建内容:q35 + OVMF(UEFI)+ Secure Boot 预置密钥 + TPM 2.0 + host CPU + VirtIO SCSI(IO Thread)+ VirtIO 网卡 + QEMU Agent + 双光驱(系统 ISO + virtio-win,后者缺失自动下载)。

**参数**:`--vmid`(默认 200 自动顺延)/ `--memory` / `--cores` / `--disk-size` / `--win-iso` / `--storage` / `--iso-store` / `--debug`。

**Windows 10 用户**:脚本 `ostype` 固定为 win11,Win10 建机后补一条 `qm set <vmid> -ostype win10` 即可,其余配置通用(Win10 建议同样 q35+OVMF+TPM 一套,便于以后直升 Win11)。

## 5. noVNC 安装系统

1. Web UI → VM → 控制台(noVNC)→ 启动
2. **磁盘不可见是正常的**(无 VirtIO 驱动):「加载驱动程序」→ virtio-win 光驱 → `vioscsi\w11\amd64`(Win10 用 `\w10\` 目录)
3. **⚠️ 选盘只认系统盘容量**:有直通盘时它显示为"未分配",千万别把系统装上去(区分:虚拟盘 ~128G vs 直通盘按实际容量)
4. OOBE 卡联网:`Shift+F10` → `OOBE\BYPASSNRO` → 重启 →「我没有 Internet 连接」→ 建**本地账户**(自动登录需要;个别版本命令无效用注册表 `BypassNRO` 法)
5. 装完会重启,**OVMF 可能再次进安装器**:进桌面后立即移除安装 ISO(§6.3)

## 6. 系统配置五连(noVNC 桌面)

1. **VirtIO 全量驱动**:virtio-win 光驱根目录 `virtio-win-gt-x64.msi` → 重启(含网卡/balloon/GA)
2. **验证 QEMU Agent**:`sc query QEMU-GA`;服务缺失 → 光驱 `qemu-ga\` 目录找独立 MSI 补装;仍缺**可跳过**(只影响面板 IP/优雅关机)
3. **摘安装 ISO + 引导顺序**(宿主):`qm set <vmid> -delete ide2` + `qm set <vmid> -boot order=scsi0`
4. **自动登录**(可选,常开场景推荐):
   - 解锁被 Win11 隐藏的 netplwiz 勾选框:`reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" /v DevicePasswordLessBuildVersion /t REG_DWORD /d 0 /f` → netplwiz 取消勾选
   - 或注册表三件套(Winlogon 的 AutoAdminLogon=1 / DefaultUserName / DefaultPassword;⚠️ 用户名必须与 `net user` 完全一致)
5. **远程管理**:
   - 专业版/企业版:设置 → 系统 → 远程桌面 → 开(或命令行 `fDenyTSConnections=0` + 防火墙规则);远程连接用 `mstsc /admin`(管理直通机的控制台会话)
   - 家庭版:无 RDP 主机,用 RustDesk/ToDesk 等第三方

## 7. 阶段 B:接入直通设备(关机状态)

物理准备:HDMI/DP 接直通显卡口;USB 设备插宿主。

```bash
bash win11-htpc-attach.sh --vmid <vmid> --dry-run    # 先审
bash win11-htpc-attach.sh --vmid <vmid>              # 输 Y;交互选直通盘
```

自动完成:显卡直通(x-vga=1,pcie=1)+ HDMI 音频 + 显示置 none + Xbox/USB 设备 + 直通盘 + 开机自启。

**通用化适配**:
- 非 6650 XT 显卡:脚本按 ID 检测 `1002:73ef`/`1002:ab28`,其他型号先用 `--gpu <地址>` 指定显卡地址;音频功能可另行在硬件里手动添加
- 其他 USB 设备:直通用例 `qm set <vmid> -usbN host=<VID:PID>`
- 直通盘:`qm set <vmid> -scsiN /dev/disk/by-id/<盘>`(整盘方式,数据盘到 Windows 磁盘管理里初始化 GPT/NTFS)

**⚠️ 注意事项**:
- USB/PCI 配置改动**必须完全关机再开机**(重启不生效)
- 显示置 none 后 **noVNC 黑屏 = 正常**,画面走直通卡物理输出
- **PVE GUI 的 PCI 设备没有「启用」勾选**——回退 noVNC 用命令行:
  ```bash
  qm stop <vmid> && qm set <vmid> -delete hostpci0 && qm set <vmid> -vga std && qm start <vmid>
  # 恢复:
  qm stop <vmid> && qm set <vmid> -hostpci0 <显卡地址>,pcie=1,x-vga=1 && qm set <vmid> -vga none && qm start <vmid>
  ```
- 摘显卡仅留音频时 QEMU 报 `Cannot reset device ... depends on group N` 警告**无害**

## 8. 踩坑速查(实测精选)

| # | 坑 | 解决 |
| --- | --- | --- |
| 1 | 浏览器上传大 ISO 卡 100% | scp 直传 |
| 2 | 脚本零输出退出 / 路径报错 | 已修复;拉最新版(核对含 `storage.cfg`);`--debug` 跟踪 |
| 3 | attach 报"未找到 VM" | 已修复(name 正则);或 `--vmid` 显式指定 |
| 4 | 安装器看不到磁盘 | 加载 `vioscsi\w11\amd64`(Win10 用 w10 目录) |
| 5 | 选错安装盘 | 只看容量:虚拟盘 vs 直通盘 |
| 6 | OOBE 卡联网 | `OOBE\BYPASSNRO` / 注册表 BypassNRO |
| 7 | 自动登录仍要密码 | 解锁 netplwiz;DefaultUserName 与账户名一致;删 Windows Hello PIN |
| 8 | 转微软账户后本地密码失效 + BitLocker 锁盘 | 本地账户 + 关闭设备加密;恢复密钥在 account.microsoft.com |
| 9 | Guest Agent 未运行 | 补装 qemu-ga MSI;非必需可跳过 |
| 10 | noVNC 无法连接 | 关旧控制台页签 / `systemctl restart pveproxy` |
| 11 | 直通后电视/显示器无画面 | 回退法(§7)排查;驱动先行再挂卡 |
| 12 | 显示器一段时间后自动断开 | Windows 电源:屏幕/睡眠设**从不**;PCIe ASPM 关闭 |
| 13 | 手柄等 USB 设备感叹号/失联 | 冷启动 VM;宿主重插;必要时去掉 `usb3=0` |

## 9. 命令速查

```bash
# 阶段 A / B
bash win11-htpc-deploy.sh --dry-run && bash win11-htpc-deploy.sh
bash win11-htpc-attach.sh --vmid <vmid> --dry-run && bash win11-htpc-attach.sh --vmid <vmid>

# 回退/恢复直通
qm stop <vmid> && qm set <vmid> -delete hostpci0 && qm set <vmid> -vga std && qm start <vmid>
qm stop <vmid> && qm set <vmid> -hostpci0 <地址>,pcie=1,x-vga=1 && qm set <vmid> -vga none && qm start <vmid>

# USB / 盘直通(关机状态)
qm set <vmid> -usb0 host=<VID:PID>
qm set <vmid> -scsi1 /dev/disk/by-id/<盘>

# 挂摘安装 ISO
qm set <vmid> -ide2 local:iso/<镜像>,media=cdrom
qm set <vmid> -delete ide2 && qm set <vmid> -boot order=scsi0

# conf 核对
qm config <vmid> | grep -E '^(hostpci|usb|vga|scsi|startup|boot|agent|ostype)'
```

## 关联文档

- [README.md](README.md) — 目录索引与快速开始
- [Win11客厅HTPC方案存档.md](Win11客厅HTPC方案存档.md) — 客厅方案全记录(已放弃;含双遥控/流媒体/DRM 经验)
- [Win11重装部署存档.md](Win11重装部署存档.md) — 企业版重装专项存档
