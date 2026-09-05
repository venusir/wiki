# PVE 打造 Win11 客厅 HTPC(RX 6650 XT 直通 + Playnite)

> 存档日期：2026-09-05
>
> 适用环境：Proxmox VE 8.x / 9.x + Intel i3-12100 + RX 6650 XT + Xbox 无线适配器（`045e:02fe`）
>
> 目标：Bazzite 游戏 VM 退役，原直通设备（显卡 / Xbox 适配器 / 游戏盘）全部移交新 Windows 11 虚拟机，配 Playnite 全屏前端与在线流媒体，作为客厅 24h 常开 HTPC
>
> 说明：本文为单文档全流程——宿主机侧（BIOS / IOMMU / VFIO）与虚拟机侧操作均完整包含，可从零执行到底

---

## 1. 方案概述

### 硬件与软件清单

| 项 | 内容 | 说明 |
| --- | --- | --- |
| CPU | Intel i3-12100（Alder Lake） | 4 核 8 线程，支持 VT-d |
| 显卡 | AMD RX 6650 XT（Navi 23，8GB） | 直通给 Win11，含 HDMI/DP 音频功能 |
| 手柄 | Xbox 无线适配器（`045e:02fe`）+ Xbox 手柄 | USB 直通，Windows 原生免驱 |
| 游戏盘 | 原 Bazzite 直通物理盘 | 移交后格式化为 NTFS |
| 虚拟机 | Windows 11 + virtio-win 驱动 | q35 + OVMF(UEFI) + TPM 2.0 |
| 前端 | Playnite（全屏模式） | 聚合 Steam / Epic / Xbox 等游戏库 |
| 流媒体 | Edge（`--app` 站点入口） | Netflix / Disney+ / B 站等 |

### 部署链路总览

```
宿主机准备（BIOS/IOMMU/VFIO，第 2 节）
  → Bazzite 退役交接（第 3 节）
    → 创建 Win11 VM（第 4 节）
      → 安装系统 + VirtIO 驱动（第 5 节）
        → 显卡直通（第 6 节）→ 手柄直通（第 7 节）→ 游戏盘移交（第 8 节）
          → Playnite 客厅自启链（第 9 节）→ 影音音频（第 10 节）
```

> **为什么是 Windows + 直通，而不是继续用 Bazzite**：在线流媒体（Netflix 4K 等）的 DRM 只认 Windows 的 Edge/PlayReady 且要求显卡物理输出，Linux 容器/虚拟机无法满足。Linux 版 Steam 游戏文件与 Windows 不通用，原 Bazzite 盘上的游戏需在 Windows 重新下载。

---

## 2. 宿主机直通准备（一次性配置）

> 以下命令均在 **PVE 宿主机**上执行。若你此前已为 Bazzite 做过显卡直通，本节大部分已就绪，按每步的「验证」命令确认后即可跳到第 3 节。

### 2.1 BIOS 设置

重启进入主板 BIOS（常见路径以实际主板为准）：

1. **开启 VT-d**：`Advanced → Intel Virtualization Technology → Enabled`，`VT-d`（或 `Intel VT for Directed I/O`）→ `Enabled`
2. **开启 Above 4G Decoding**（大显存显卡直通常必需，6650 XT 为 8GB 卡）：`Advanced → PCI Subsystem Settings → Above 4G Decoding → Enabled`
3. **开启 ErP Ready**（可选但推荐）：`Advanced → APM Configuration → ErP Ready → Enabled (S4+S5)`——彻底断电 USB 端口，防止 Xbox 适配器/外设进入卡死状态
4. 保存重启

> 验证：`dmesg | grep -i -e DMAR -e IOMMU` 能看到 DMAR/IOMMU 相关输出即代表 VT-d 已生效（详见 2.3）。

### 2.2 内核 IOMMU 参数

编辑 GRUB 配置：

```bash
nano /etc/default/grub
```

找到 `GRUB_CMDLINE_LINUX_DEFAULT`，在引号内追加参数：

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

更新引导并重启：

```bash
update-grub
reboot
```

### 2.3 查询设备与 IOMMU 分组

重启后确认 IOMMU 已启用，并查看显卡实际 PCI 地址与设备 ID：

```bash
# IOMMU 已启用（应有输出）
dmesg | grep -i -e DMAR -e IOMMU

# 存在 IOMMU 分组
ls /sys/kernel/iommu_groups/ | wc -l

# 查看显卡与音频功能（6650 XT 参考 ID：VGA=1002:73ef，Audio=1002:ab28，以实测为准）
lspci -nn | grep -iE "VGA|Audio"
```

预期输出类似（地址以你机器实测为准）：

```text
01:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD] Navi 23 ... [1002:73ef]
01:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD] Navi 21/23 HDMI/DP Audio Controller [1002:ab28]
```

确认显卡与音频同属一个 IOMMU 分组（同组设备必须一起直通）：

```bash
# 显卡槽位替换为实测地址，如 01:00
ls -l /sys/kernel/iommu_groups/*/devices/ | grep "01:00"
```

### 2.4 VFIO 绑定显卡与音频

将实测的两个设备 ID 写入 VFIO 配置（多个 ID 用逗号分隔）：

```bash
# 将 1002:73ef,1002:ab28 替换为 2.3 实测到的两个 ID
echo "options vfio-pci ids=1002:73ef,1002:ab28" > /etc/modprobe.d/vfio.conf
cat /etc/modprobe.d/vfio.conf
```

加载 VFIO 内核模块（追加到文件末尾，不要覆盖其他内容）：

```bash
echo -e "vfio\nvfio_iommu_type1\nvfio_pci" >> /etc/modules
```

> **提示**：宿主机无 AMD 卡需求（核显 UHD 730 即可，实际也不占用控制台输出），无需额外黑名单；若后续发现宿主把卡抢走（`lspci -nnk` 显示 `amdgpu`），再补 `blacklist amdgpu` 并 `update-initramfs -u -k all`。

重建 initramfs 并重启：

```bash
update-initramfs -u -k all
reboot
```

**验证**：重启后显卡应已被 vfio-pci 接管：

```bash
lspci -nnk -s 01:00.0
# 输出中应包含：Kernel driver in use: vfio-pci
```

---

## 3. Bazzite 退役交接

1. 关闭 Bazzite 虚拟机（Web UI → 选中 VM → 关机，或 `qm stop <bazzite-vmid>`）
2. 记录其配置文件（`/etc/pve/qemu-server/<bazzite-vmid>.conf`）中显卡 `hostpci*`、USB `usb0` 与直通盘配置，作为第 6/7/8 节配置参考
3. **从 Bazzite 配置中删除**上述直通行（Web UI → 硬件 → 选中设备 → 移除）：
   - 同一显卡/USB 设备若仍挂在 Bazzite 配置上，Win11 VM 启动时会提示设备被占用或抢不到设备
   - 游戏盘若走 SCSI 直通引用同一块物理盘，同样需要移除
4. Bazzite VM 本体可保留但不再开机（不放心可整机备份后删除，释放存储）
5. 游戏盘数据处置：盘上是 Bazzite（ext4/btrfs）文件系统，Windows 不识别且 Linux 版游戏不可复用——**若有需要保留的数据，先在此步骤从 Bazzite 内拷出或备份**，第 8 节将整盘格式化为 NTFS

---

## 4. 创建 Windows 11 虚拟机

> 关键前提：**Windows 11 强制要求 TPM 2.0 + UEFI**，缺了安装器直接报「这台电脑无法运行 Windows 11」。三个要素必须在创建时就定好：**q35 芯片组 + OVMF(UEFI) 引导 + TPM 2.0 设备**，BIOS 类型后期无法切换。

### 4.1 准备两个 ISO

| ISO | 来源 |
| --- | --- |
| Windows 11 官方镜像 | Microsoft 官网下载（software-download.microsoft.com），上传到 PVE 存储 |
| virtio-win（驱动） | 官方源 <https://fedorapeople.org/groups/virt/virtio-win/>（stable 直链 `direct-downloads/stable-virtio/virtio-win.iso`） |

Web UI 上传：选中存储 → `ISO 镜像 → 上传`。

### 4.2 Web UI 向导关键选项

| 页面 | 选项 | 值 |
| --- | --- | --- |
| General | VM ID / 名称 | 如 `200` / `win11-htpc` |
| OS | ISO 镜像 | Win11 ISO |
| OS | Type | `Microsoft Windows` → `11/2022/2025`（生成 `ostype: win11`） |
| System | 机型（Machine） | **q35** |
| System | BIOS | **OVMF (UEFI)** |
| System | 勾选 | 添加 EFI 磁盘 + **Pre-Enrolled Keys**（即 Secure Boot 预置微软密钥） |
| System | TPM | 添加 TPM 设备：`swtpm`，版本 **2.0**，存储选 local-lvm（无此选项请先更新到 PVE 8.x+） |
| Disks | 总线 | **VirtIO Block / VirtIO SCSI**（SCSI 控制器选 VirtIO SCSI single） |
| Disks | 磁盘 | 128 GiB+（系统盘，放 NVMe/SSD 存储池） |
| CPU | 类型 | **host** |
| CPU | 核心 | 4（i3-12100 共 8 线程，宿主还跑着 LXC 服务则按负载下调） |
| Memory | 内存 | **16384 MiB** 建议（宿主机总内存富余时；至少 8192） |
| Network | 网卡 | **VirtIO**（半虚拟化，性能最好） |
| 确认页 | 光驱 | Win11 ISO 为主光驱；若向导支持，把 virtio-win ISO 加为第二光驱（不支持则创建后再加） |

**此阶段先不要挂载显卡**——用默认虚拟显示（标准 VGA），后面通过 noVNC 控制台完成系统安装，第 6 节再直通。

### 4.3 等效命令行（qm create）

存储名（如 `local-lvm`）、ISO 文件名按你的实际替换：

```bash
qm create 200 --name win11-htpc \
  --memory 16384 --cores 4 --cpu host \
  --machine q35 --bios ovmf \
  --efidisk0 local-lvm:1,efitype=4m,pre-enrolled-keys=1 \
  --tpmstate0 local-lvm:1,version=v2.0 \
  --ostype win11 \
  --scsihw virtio-scsi-single \
  --scsi0 local-lvm:128,iothread=1 \
  --net0 virtio,bridge=vmbr0 \
  --ide2 local:iso/Win11.iso,media=cdrom \
  --ide0 local:iso/virtio-win.iso,media=cdrom \
  --boot 'order=ide2;scsi0'
```

> 参数说明：`efitype=4m,pre-enrolled-keys=1` = 4M EFI 盘 + Secure Boot；`tpmstate0 ... version=v2.0` = TPM 2.0（PVE 9.1+ 也可把 TPM 状态放 qcow2 目录存储以支持快照，本方案用 local-lvm 即可）。iothread 需要 VirtIO SCSI；若存储不支持 discard 不要加 `discard=on`。
>
> 安装完成后把引导顺序改为只从系统盘启动：
> `qm set 200 --boot order=scsi0`

---

## 5. 安装 Windows 11 + VirtIO 驱动

### 5.1 安装系统

1. Web UI 打开该 VM 的 noVNC 控制台 → 启动
2. 正常进入 Windows 安装程序；走到 **「您想将 Windows 安装在哪里？」磁盘选择页时看不到任何磁盘是正常的**——Windows 安装介质不含 VirtIO 驱动
3. 点击 **「加载驱动程序 Load driver」→「浏览 Browse」** → 选择 virtio-win 光驱（盘符一般是 D: 或 E:）→ 进入存储驱动目录 **`vioscsi\w11\amd64`**（旧版 ISO 为 `viostor\w11\amd64`）→ 安装 → 磁盘出现后选中继续安装
4. OOBE 阶段建议用**本地账户**（配合第 9 节自动登录）；若被强制要求微软账户，按 `Shift + F10` 输入：

   ```text
   OOBE\BYPASSNRO
   ```

   回车重启后即可选「我没有此人的登录信息」创建本地账户

### 5.2 补驱动与 Guest Tools

装完进桌面后：

1. **网络驱动**：设备管理器 → 找到带黄色感叹号的以太网控制器 → 更新驱动 → 指向 virtio-win 光驱的 **`NetKVM\w11\amd64`**，网络即通
2. **Guest Tools**：运行 virtio-win 光驱里的 `virtio-win-gt-x64.msi`（一次性装完 Balloon 内存、显示、QEMU Agent 等剩余驱动）
3. **启用 Agent**（宿主机上执行）：

   ```bash
   qm set 200 --agent enabled=1
   qm reboot 200
   ```

   之后 PVE 界面能显示 VM IP/内存，关机更干净

### 5.3 设置 Windows 自动登录（为第 9 节铺路）

- 方法一：`Win + R` → 输入 `netplwiz` → 取消勾选「要使用本计算机，用户必须输入用户名和密码」→ 输入两次密码
- 方法二（新版 Win11 无该勾选框时）：注册表 `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon` 下新建：

  | 值名称 | 类型 | 值 |
  | --- | --- | --- |
  | `AutoAdminLogon` | REG_SZ | `1` |
  | `DefaultUserName` | REG_SZ | 你的用户名 |
  | `DefaultPassword` | REG_SZ | 你的密码 |

---

## 6. 显卡直通（RX 6650 XT）

### 6.1 挂载直通

1. **关机** Win11 VM
2. Web UI → 该 VM → `硬件 → 添加 → PCI 设备`：
   - 设备：选中显卡（`01:00.0`，以第 2.3 节实测为准）
   - 勾选 **All Functions（所有功能）**：把同卡的音频功能（`01:00.1`）一并带入（若列表里是分开两条则两条都添加）
   - 勾选 **PCI-Express**
   - 勾选 **Primary GPU（x-vga=1）**：直通卡作为唯一主显示
3. `硬件 → 显示 → 设为「无 (none)」`——移除虚拟显卡，画面完全交给直通卡
4. 开机，**电视/显示器接在 6650 XT 的 HDMI/DP 物理口上**（不是主板核显口）

等效 conf 配置（对应 `/etc/pve/qemu-server/200.conf`）：

```text
hostpci0: 0000:01:00.0,pcie=1,x-vga=1
hostpci1: 0000:01:00.1,pcie=1
```

> 注意：显卡直通后 **PVE 控制台（noVNC）黑屏 = 正常现象**，不是故障——画面已经走物理显卡输出到电视了。排查问题走第 6.3 节回退法。

### 6.2 安装 AMD 驱动

1. 开机进 Windows 后，打开浏览器到 AMD 官网下载 **Adrenalin** 驱动（amd.com → 支持 → RX 6650 XT）
2. 安装重启后，设备管理器应看到 Radeon RX 6650 XT 与 **AMD High Definition Audio（HDMI 音频）** 两个设备
3. 桌面右键 → 显示设置确认分辨率与刷新率正确；任务栏音量图标确认输出设备为 HDMI/电视

### 6.3 黑屏/无画面排查（回退法）

直通卡没画面、需要回 PVE 控制台排查时（方法沿用 Bazzite 时代已验证流程）：

1. 关机 → `硬件 → PCI 设备（显卡）→ 编辑 → 取消勾选「启用」`
2. `硬件 → 显示 → 改回「标准 VGA (std)」`
3. 开机 → noVNC 控制台恢复画面 → 排查（驱动问题、显示输出设置等）
4. 修复后重复 6.1 步骤恢复直通

常见原因：HDMI 线插错口（插到主板核显了）、电视未切到对应输入源、AMD 驱动未装完（首次进系统用 Microsoft Basic Display 也能点亮）。

---

## 7. Xbox 无线适配器直通

Windows 对 Xbox 适配器**原生免驱**（对比 Linux 需要 xone/xow + 固件 + SELinux 放行那一整套，Windows 里即插即用，这正是换 Windows 的红利）。

### 7.1 宿主机确认设备

```bash
lsusb | grep -i microsoft
# 预期：Bus xxx Device xxx: ID 045e:02fe Microsoft Corp. Xbox Wireless Adapter for Windows
```

### 7.2 添加到虚拟机

Web UI → `硬件 → 添加 → USB 设备` → 选 `使用 USB 厂商/产品 ID` → 填 `045e:02fe`；等效 conf 行：

```text
usb0: host=045e:02fe,usb3=0
```

- 用 **VID:PID** 而非端口号，稳定不易漂移
- `usb3=0` 强制 USB 2.0 模式，兼容性更好（沿用已验证写法）
- **修改后需完全关机再开机（不是重启）**

### 7.3 验证

Windows 设备管理器应出现 Xbox Wireless Adapter 设备；按手柄顶部配对键 + 适配器侧按键，连接成功后手柄灯常亮。若连不上，先确认第 3 节已从 Bazzite 配置删除同一 `usb0`（两个 VM 抢同一 USB 设备会导致谁都用不了）。

---

## 8. 游戏盘移交

### 8.1 宿主识别并挂给 VM

```bash
ls -l /dev/disk/by-id/
# 找到目标盘，如 ata-Samsung_SSD_870_EVO_XXXXXXXX
lsblk
```

**方式 A：整盘直通（推荐，最常用）**——把物理盘当块设备直接给 VM（盘上不要有宿主机数据）：

```bash
# 路径替换为实测 by-id；scsi1 表示作为第二个 SCSI 盘
qm set 200 -scsi1 /dev/disk/by-id/ata-Samsung_SSD_870_EVO_XXXXXXXX
```

> 方式 B：**SATA 控制器整体直通**（`hostpci` 加控制器）仅在该控制器独立、不挂宿主系统盘时可行——i3-12100 板载 SATA 通常连系统盘，不适用；若用 PCIe SATA 扩展卡接游戏盘才走此路。

### 8.2 Windows 内格式化

1. 启动 VM → `Win + X → 磁盘管理`
2. 找到新磁盘（未初始化）→ 右键 **初始化磁盘 → GPT**
3. 右键未分配空间 → **新建简单卷 → NTFS**，分配盘符（如 `D:`）
4. Steam / Epic 等客户端安装后把下载库指到 D:（Steam：设置 → 存储 → 添加驱动器），游戏需**重新下载 Windows 版**（Linux 版文件不通用）

> 数据安全：只有确认原 Bazzite 盘数据无保留价值才执行格式化（第 3 节已提示备份）。

---

## 9. Playnite 客厅前端与 24h 自启链

### 9.1 为什么选 Playnite（对比）

| 方案 | 优点 | 不适合的原因 |
| --- | --- | --- |
| **Playnite 全屏**（免费）✅ | 聚合 Steam/Epic/Xbox 等所有库；全屏模式手柄可用；能把流媒体入口做成条目；无广告无付费 | ——（本文采用） |
| Steam 大屏模式 | 手柄体验最成熟 | **只显示 Steam 游戏**，Epic/Xbox/流媒体都要另开，客厅要来回切 |
| LaunchBox Big Box | 界面最炫（$75 买断） | 付费且重心在模拟器/复古游戏，对现代 PC 游戏与在线流媒体无实质优势 |
| 不装前端 | 最轻 | 桌面点图标不像家电，遥控/手柄操作断层 |

### 9.2 安装与登录

1. 官方站下载安装 Playnite（playnite.link）
2. `设置 → 游戏库 → 添加平台`，逐个登录 Steam / Epic / Xbox 等账号（首次配置耗时较长属正常），库自动同步封面与元数据
3. 也可用 `添加游戏 → 自动扫描已安装游戏` 导入本地客户端游戏

### 9.3 双遥控架构（客厅操作设计）

| 层级 | 内容 | 控制方式 |
| --- | --- | --- |
| 游戏层 | Playnite 全屏 | Xbox 手柄直接导航（摇杆/方向键 + A 确认） |
| 流媒体层 | Edge（Netflix/Disney+/B 站） | 浏览器网页**手柄无法导航** → 用 **Flirc 红外遥控**（模拟键盘）或迷你键鼠 |

Flirc 键位映射建议（在你已有的 Flirc 配置上调整）：

| 遥控按键 | 映射键盘 | 用途 |
| --- | --- | --- |
| 方向键 / OK | ↑↓←→ / Enter | Playnite 与浏览器通用导航 |
| 返回 | Esc / Alt+← | 退出全屏视频、返回列表 |
| 主页（红色） | Win 键 或 Alt+Tab | 随时切回 Playnite |

### 9.4 流媒体入口纳入 Playnite（一个壳启动所有内容）

把流媒体站点做成 Playnite 条目：`Playnite → 添加游戏 → 手动添加`，名称如 `Netflix`，操作目标填 Edge 的 `--app` 参数：

```text
路径（Path）    : C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe
参数（Arguments）: --app=https://www.netflix.com
```

同样方式添加 Disney+、YouTube、B 站等。全屏模式下点条目即以**独立窗口**打开对应站点（Edge 的 app 模式保留 PlayReady DRM 能力），比普通标签页更像"应用"。**播放流媒体用 Flirc 遥控操作**（见 9.3），退出后切回 Playnite 继续选游戏。

### 9.5 自启三步（上电 → 全屏 Playnite）

| 步骤 | 操作 | 目的 |
| --- | --- | --- |
| ① PVE 开机自启 VM | Web UI → VM → `选项 → 开机自启动` 打勾（或 `qm set 200 --startup order=1`） | 宿主机通电即拉起 Win11 |
| ② Windows 自动登录 | 第 5.3 节已设置 | 无需输密码进桌面 |
| ③ Playnite 全屏自启 | 桌面右键新建快捷方式，目标填： | 开机直接进全屏库 |

```text
"C:\Program Files\Playnite\Playnite.DesktopApp.exe" --startfullscreen
```

> `--startfullscreen` 参数小写；exe 名与安装路径以你机器实际安装为准（绿色版/不同版本可能为 Playnite.exe）。把该快捷方式放入启动文件夹：`Win+R` → `shell:startup`。

**完整链条检查清单**：宿主机通电 → PVE 自启 VM（等待进入 Windows）→ 自动登录 → Playnite 全屏出现 → 手柄选游戏 / 遥控选流媒体。哪一环断了就按第 11 节 FAQ 查。

---

## 10. 影音与音频（在线流媒体为主）

### 10.1 声音输出

- 任务栏音量图标 → 输出设备选 **HDMI/Display Audio（AMD，直通卡）**，即电视/功放出声
- 没这个设备？确认第 6 节音频功能（`01:00.1`）随卡一起直通，且 AMD 驱动装完（设备管理器有 AMD High Definition Audio）
- 电视通过 ARC/eARC 接回音壁/功放时，回传声道交给电视设置，Windows 侧选 HDMI 输出即可
- （可选）微软商店装 **Dolby Access**，杜比全景声内容（DD+ Atmos 流媒体）可正常点亮

### 10.2 DRM 现实边界（重要，别抱不切实际的期望）

| 内容 | 能否高清播放 | 条件与说明 |
| --- | --- | --- |
| Netflix / Disney+ **4K HDR** | 视环境，不保证 | 只认 **Edge（PlayReady）+ HDCP 2.2**；必须物理直连电视且电视开对应增强 HDMI/HDCP 设置；**经 noVNC / RDP / 串流会话观看会直接降级或黑屏**（远程会话破坏 HDCP 链路） |
| Netflix / Disney+ **1080p** | 一般稳定 | 同上链路，1080p 握手压力小 |
| YouTube / B 站 / 其他 | 无此限制 | 网页任意清晰度 |

> 实操建议：物理 HDMI 直连是唯一可靠姿势——这台机器本来就直通显卡直连电视，属标准形态；调试阶段千万别开着 noVNC/RDP 去测 4K 播放，会得出错误结论。社区没有"所有环境都能稳定 Netflix 4K"的保证，本篇按「1080p 稳、4K 视 HDCP 握手」如实表述。

### 10.3 画质设置提示

- 电视 HDMI 端口开 **增强格式**（对应 4K/VRR，不同品牌叫法不同：Enhanced HDMI / 增强模式）
- Windows `设置 → 系统 → 屏幕 → HDR`：电视支持时开启，Netflix/Disney+ 的 HDR 内容才能正确输出
- 确认电视输入源是 6650 XT 所接的 HDMI 口，分辨率设为电视原生分辨率（4K 下建议 100% 缩放 + 大字体方便客厅远看）

---

## 11. 常见问题速查

| 问题 | 原因与处理 |
| --- | --- |
| 安装时看不到磁盘 | 正常：点「加载驱动程序」选 virtio-win 光驱 `vioscsi\w11\amd64`（5.1 节） |
| 装完没网 | NetKVM 驱动未装：设备管理器指向 virtio-win 的 `NetKVM\w11\amd64`（5.2 节） |
| 提示「这台电脑无法运行 Windows 11」 | TPM 2.0 / OVMF(UEFI) 没配齐：回查第 4.2 节三项（q35 + OVMF + TPM），虚拟机只能重建或补齐后重装 |
| 直通后电视无画面 | 先确认线插在 6650 XT 上、电视输入源正确；再走第 6.3 节回退法进系统排查 |
| 无声 / 声音走错设备 | 输出设备选 AMD HDMI Audio；检查音频功能是否随卡直通（6.1 节）；AMD 驱动装全 |
| Netflix 4K 掉回 1080p 或报错 | HDCP 链路问题：确认物理直连、未开远程会话、电视增强 HDMI 已开；4K 不保证（10.2 节） |
| 手柄连不上 | 适配器在宿主机被别的驱动抢占（`lsusb` 不可见则先处理宿主）；从 Bazzite 配置删掉同一 `usb0`；**完全关机再开机**（7.3 节） |
| 开机没进 Playnite 全屏 | 逐环查自启链：VM 自启 → 自动登录（5.3）→ 启动文件夹快捷方式参数是否正确（9.5 节） |
| Windows 更新后显卡/音频异常 | 重新装一遍 Adrenalin；AMD 驱动被系统替换属常见问题，可在 Windows 更新设置里排除显卡驱动更新 |
| 24h 常开功耗顾虑 | i3-12100 平台待机功耗低；显卡空闲时让 Windows 进入可恢复睡眠或设置 AMD 节能；PVE 层 `选项 → 启动模式` 可调 |

---

## 相关文档（扩展阅读，非前置依赖）

- [Xbox适配器直通Bazzite](Xbox适配器直通Bazzite.md) — Linux 客户机下手柄适配器固件/SELinux 排错（Windows 下无需这些步骤，作为对照参考）
- [Bazzite直通硬盘Steam库](Bazzite直通硬盘Steam库.md) — 直通盘挂载与「禁用显卡回控制台」背景
- [Flirc遥控启动虚拟机](Flirc遥控启动虚拟机.md) — Flirc + PVE API 遥控开机方案（本文第 9 节遥控方案基于同一硬件）
