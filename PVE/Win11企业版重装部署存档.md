# PVE Win11 企业版重装部署存档(含全部踩坑记录)

> 存档日期：2026-09-05
>
> 背景：首轮用 Windows 11 **家庭版**部署完成后发现**家庭版无远程桌面(RDP)主机功能**(与激活无关,按版本划分),决定**重装企业版**。
>
> 环境：PVE 9.2(内核 7.0.6-2-pve)+ i3-12100 + RX 6650 XT(03:00.0 显卡 / 03:00.1 音频,独立 IOMMU group)+ Xbox 无线适配器(`045e:02fe`)+ WD 1TB 直通盘 + Win11 虚拟机(VMID 200,`win11-htpc`)
>
> 本文按**实测流程 + 踩坑修正**编写,重装时可直接照做。

---

## 0. 重装前状态检查(必做)

| 检查项 | 当前状态 | 说明 |
| --- | --- | --- |
| 虚拟机运行中,noVNC 可用 | ✅ | 当前处于**回退态**:显卡已摘(`-delete hostpci0`)、显示为标准 VGA——**正好用于重装,先别恢复直通** |
| 直通设备 conf | 音频 03:00.1 / 游戏盘 scsi1 / 适配器 usb0 / startup 仍挂着 | 重装系统不影响它们,保持不动 |
| 游戏盘(WD 1TB) | 仍是 Bazzite 旧数据,未被格式化 | **重装时绝对不要选中它**(见 3.3 警告) |
| 备份 | Windows 里没有需要保留的数据(重装全清) | 需要保留的先拷出 |

> 版本说明:两个部署脚本(win11-htpc-deploy.sh / win11-htpc-attach.sh)已修复多处 bug,重装全程直接用 GitHub 最新版即可,无需再踩旧坑(见第 11 节错误记录)。

---

## 1. 下载企业版 ISO 并上传

1. 下载 Windows 11 Enterprise ISO
   - 授权/评估渠道自行解决(微软 Eval Center 提供 90 天评估版;组织授权走 VLSC)。**评估版注意到期时间**,24h 常开 HTPC 建议用有长期授权的来源
   - 与家庭版同样:下载**ISO 磁盘映像**,不是 Media Creation Tool
2. 上传:**不要用浏览器上传大文件**(上次卡 100%)。Windows 本机 PowerShell 直传:

```powershell
scp .\Win11_Enterprise.iso root@<PVE-IP>:/var/lib/vz/template/iso/
```

3. 验证落盘完整:

```bash
ls -lh /var/lib/vz/template/iso/
```

---

## 2. 挂载 ISO 并进入安装

VM 关机状态下(noVNC 里正常关机即可):

```bash
# 挂载企业版 ISO 到光驱,并把引导顺序临时改为光驱优先
qm set 200 -ide2 local:iso/Win11_Enterprise.iso,media=cdrom
qm set 200 -boot 'order=ide2;scsi0'
qm start 200
```

noVNC 控制台应出现企业版安装界面。

> 首轮经验:OVMF 下光驱引导**不会**有"Press any key"提示,直接进安装器;自动重启时若再次进安装界面,关掉/退出即可(装完后记得摘除 ISO,见第 4 步)。

---

## 3. 安装要点与 ⚠️ 大坑警告

### 3.1 磁盘不可见 → 加载 VirtIO 驱动

到「选择磁盘」页看不到盘是正常的(无 vioscsi 驱动):「加载驱动程序」→ 浏览 virtio-win 光驱 → `vioscsi\w11\amd64` → 磁盘出现。

### 3.2 ⚠️ 选盘警告(重装最容易翻车的点)

安装程序会列出磁盘,注意区分:

| 磁盘 | 大小 | 处置 |
| --- | --- | --- |
| QEMU/QEMU HARDDISK(虚拟系统盘) | **~128 GB** | ✅ **选它**:删除其上的全部分区 → 新建 → 下一步 |
| WD 直通盘(直通盘无 Windows 分区表,会显示为**未分配 ~931.5 GB**)| **~931 GB** | ❌ **绝不选中、绝不格式化/删除** |

> 判断标准只看**容量**:128GB 是系统盘,931GB 是游戏盘。装错盘 = 游戏盘数据全毁(虽然本来也要格式化,但顺序应该在装完系统后由磁盘管理来做,而不是被安装器覆盖)。

### 3.3 OOBE:建本地账户

- 企业版 OOBE 同样可能要求联网/微软账户:`Shift+F10` → `OOBE\BYPASSNRO` → 回车 → 重启 → 「我没有 Internet 连接」→ 建**本地账户**(自动登录需要)
- 若该命令无效(个别新 build):注册表法 → `reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f` + `shutdown /r /t 0`

---

## 4. 装完系统第一轮配置(noVNC 桌面)

顺序固定,别跳:

1. **装 VirtIO 全量驱动**:打开 virtio-win 光驱(自动挂载的 ide0)→ 运行根目录 `virtio-win-gt-x64.msi` → 重启
   - 重启后验证:设备管理器无感叹号、能开网页(NetKVM 生效)
2. **验证 QEMU Agent**:
   ```cmd
   sc query QEMU-GA
   ```
   - RUNNING → PVE 面板应显示 IP ✅
   - 「指定的服务未安装」→ 首轮已知问题(MSI 正常结束但 GA 服务缺失):到光驱找独立 GA 安装包补装
     ```cmd
     dir D:\qemu-ga
     msiexec /i D:\qemu-ga\x86_64\qemu-ga-x86_64.msi
     ```
     再不行:**跳过**,GA 只影响面板 IP/优雅关机,不影响使用(首轮即带病完成部署)
3. **摘除安装 ISO**:PVE → 硬件 → CD/DVD 驱动器(IDE 2)→ 移除;并把引导顺序改回硬盘:
   ```bash
   qm set 200 -boot order=scsi0
   ```

---

## 5. 自动登录(24h 常开自启链第 2 环)

- 首选:注册表解锁被 Win11 隐藏的 netplwiz 勾选框,然后图形化设置:

```cmd
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device" /v DevicePasswordLessBuildVersion /t REG_DWORD /d 0 /f
```

`Win+R` → `netplwiz` → 取消勾选「要使用本计算机,用户必须输入用户名和密码」→ 输密码两次。

- 若勾选框仍不出现,直接注册表三件套(`DefaultUserName` 必须与 `net user` 里的账户名**完全一致**,这是首轮"设了还问密码"的根因):

```cmd
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d 你的用户名 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d 你的密码 /f
```

- 重启验证直接进桌面。

---

## 6. 启用远程桌面(RDP)——重装企业版的核心理由

企业版/专业版才有 RDP 主机(家庭版无此功能,激活也变不出来):

1. `Win + I` → 系统 → 远程桌面 → 打开(或命令行):
   ```cmd
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
   netsh advfirewall firewall set rule group="远程桌面" new enable=Yes
   ```
2. `ipconfig` 记下 IPv4
3. 从管理机 `mstsc` → IP → 本地账户名 + 密码连接
4. 之后所有操作走 RDP,noVNC 退役

> RDP 会话无 GPU 加速、破坏 HDCP:**远程只用于管理**;影音 4K 与游戏串流仍走电视直连 / Moonlight,别用 RDP 干这两件事。

---

## 7. 恢复显卡直通并点亮电视

RDP 已通、AMD 驱动**先装好**再恢复直通(首轮经验:驱动就位后首次点亮容错最高):

1. RDP 里到 AMD 官网装 **Adrenalin**(RX 6650 XT)
2. 宿主机恢复直通(注意:**PVE GUI 的 PCI 设备没有「启用」勾选框**,用命令行最清晰):

```bash
qm stop 200
qm set 200 -hostpci0 03:00.0,pcie=1,x-vga=1
qm set 200 -vga none
qm start 200
```

3. 电视上出现画面(noVNC 从此黑屏 = 正常);RDP 断开重连即可继续管理
4. 设备管理器确认:Radeon RX 6650 XT / AMD High Definition Audio / Xbox Wireless Adapter

> 若电视无画面需要回 noVNC 排查(回退法):
> ```bash
> qm stop 200
> qm set 200 -delete hostpci0
> qm set 200 -vga std
> qm start 200
> ```
> 音频(03:00.1)与显卡分属独立 IOMMU group,回退时不用动;显卡单独摘除时 QEMU 会报 `Cannot reset device ... depends on group 10` 警告,**无害,忽略**。

---

## 8. 游戏盘格式化(数据清空点)

1. `Win+X` → 磁盘管理 → WD 1TB 显示"未初始化"
2. 初始化 → **GPT** → 新建简单卷 → **NTFS** → 盘符 `D:`
3. Steam 等下载库指到 D:(Steam:设置 → 存储 → 添加驱动器)

> 到这一步 Bazzite 旧数据才真正消失——确认无保留价值再动手。

---

## 9. 手柄与音频

- **Xbox 手柄配对**:Windows 免驱,适配器侧圆键 + 手柄顶部配对键,灯常亮即连上
- **声音输出**:任务栏音量 → 选 HDMI(AMD);无声先查默认设备与音频是否随卡直通

---

## 10. 客厅软件与自启链(引用主文档)

- Playnite 安装/登录平台 → 全屏自启(`Playnite.DesktopApp.exe --startfullscreen` + 启动文件夹)
- Edge `--app=<网址>` 做流媒体条目;Flirc 遥控操作流媒体
- HEVC 视频扩展(`ms-windows-store://pdp/?ProductId=9n4wgh0z6vhq`)→ Netflix 4K 前置
- 详见 [Win11客厅HTPC.md](Win11客厅HTPC.md) 第 9/10 节
- 自启链终验:宿主机断电重启 → VM 自启 → 自动登录 → Playnite 全屏

---

## 11. 首轮踩坑记录(重装时不再踩)

| # | 现象 | 根因 | 解决 |
| --- | --- | --- | --- |
| 1 | 浏览器上传 ISO 卡 100% | 大文件走 WebSocket 易断 | scp 直传 `/var/lib/vz/template/iso/` |
| 2 | deploy 脚本零输出直接退出 | `detect_iso` 找不到文件返回 1 → `$( )` 赋值触发 `set -e` 静默击杀 | 脚本已修:找不到返回 0 + ERR 陷阱打印行号 + `--debug` |
| 3 | `pvesm path` 返回空 | pvesm path 只接受 `存储:卷`,不能只传存储名 | 已改从 `/etc/pve/storage.cfg` 读 path |
| 4 | 装完重启仍要密码 | `DefaultUserName` 与账户名不一致 / netplwiz 勾选框被隐藏 | 解锁 `DevicePasswordLessBuildVersion=0`;核对账户名 |
| 5 | noVNC「无法连接到服务器」 | 旧控制台会话占住单会话名额 | 关旧页签或 `systemctl restart pveproxy` |
| 6 | Guest Agent 显示未运行 | qemu-ga 服务未装(MSI 装完仍缺) | 光驱 `qemu-ga\` 目录单独装 MSI;非必需可跳过 |
| 7 | 家庭版无远程桌面 | RDP 主机按版本划分,家庭版砍掉 | 换企业版/Pro(本文缘由)或第三方远程(RustDesk) |
| 8 | PCI 设备编辑框无「启用」勾选 | GUI 没有该选项 | 用「移除/重新添加」或 `qm set -delete hostpci0` |
| 9 | attach 脚本报"未找到 win11-htpc VM" | conf 格式 `name: win11-htpc`(冒号后空格),正则漏空格 | 已修复(用 `--vmid 200` 亦可绕过) |
| 10 | 虚拟化/VM 环境下安装器磁盘不可见 | 无 vioscsi 驱动 | virtio-win 光驱 `vioscsi\w11\amd64` |

---

## 12. 命令速查

```bash
# 建机(全新 VM 才用;本机已存在跳过)
bash /root/win11-htpc-deploy.sh --dry-run
bash /root/win11-htpc-deploy.sh

# 接入直通(系统装好、关机后)
bash /root/win11-htpc-attach.sh --vmid 200 --dry-run
bash /root/win11-htpc-attach.sh --vmid 200

# 回退到 noVNC / 恢复直通
qm stop 200 && qm set 200 -delete hostpci0 && qm set 200 -vga std && qm start 200
qm stop 200 && qm set 200 -hostpci0 03:00.0,pcie=1,x-vga=1 && qm set 200 -vga none && qm start 200

# 挂 ISO / 改引导
qm set 200 -ide2 local:iso/<企业版ISO>,media=cdrom
qm set 200 -boot 'order=ide2;scsi0'

# conf 核对
qm config 200 | grep -E '^(hostpci|usb0|vga|scsi1|startup|boot|agent)'
```

---

## 相关文档

- [Win11客厅HTPC.md](Win11客厅HTPC.md) — 主方案文档(Playnite/影音/DRM/自启链)
- [win11-htpc-deploy.sh](win11-htpc-deploy.sh) / [win11-htpc-attach.sh](win11-htpc-attach.sh) — 两阶段部署脚本
- [Xbox适配器直通Bazzite.md](Xbox适配器直通Bazzite.md) — Linux 客户机适配器排错对照参考
