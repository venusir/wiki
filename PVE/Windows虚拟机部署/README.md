# PVE 下部署 Windows 10/11 虚拟机

> 本目录收录在 Proxmox VE 上部署 Windows 虚拟机(10/11)的**通用部署流程、一键脚本与实测踩坑记录**。
>
> 存档日期:2026-09-05 | 实测环境:PVE 9.2 + Intel i3-12100 + RX 6650 XT

## 目录内容

| 文件 | 说明 |
| --- | --- |
| [Windows10-11虚拟机部署指南.md](Windows10-11虚拟机部署指南.md) | ⭐ 通用部署主流程(全新部署从这里开始) |
| [win11-htpc-deploy.sh](win11-htpc-deploy.sh) | 阶段 A:一键建机脚本(OVMF/TPM2.0/VirtIO 全参数) |
| [win11-htpc-attach.sh](win11-htpc-attach.sh) | 阶段 B:系统装好后一键接入直通设备(显卡/USB/盘/自启) |
| [Win11客厅HTPC方案存档.md](Win11客厅HTPC方案存档.md) | 存档:客厅影音+游戏方案全过程(已放弃,含直通/遥控排错经验) |
| [Win11重装部署存档.md](Win11重装部署存档.md) | 存档:企业版重装流程与踩坑记录 |

## 快速开始

```bash
# 1. 上传系统 ISO 到 PVE(大文件用 scp,别用浏览器)
scp .\Win11.iso root@<PVE-IP>:/var/lib/vz/template/iso/

# 2. 阶段 A:一键建机(先 dry-run 审阅)
bash win11-htpc-deploy.sh --dry-run
bash win11-htpc-deploy.sh

# 3. noVNC 安装系统(按指南第 5 节,磁盘不可见时加载 vioscsi 驱动)

# 4. 阶段 B:接入直通设备(系统装好、关机后)
bash win11-htpc-attach.sh --vmid 200 --dry-run
bash win11-htpc-attach.sh --vmid 200
```

## 方案状态说明

- 本目录最初服务于「PVE Win11 客厅 HTPC(影音+游戏)」项目,该项目**已放弃**(桌面网页与电视遥控交互不兼容等,见存档文档横幅)。
- **部署部分与客厅方案解耦**,作为通用「PVE 部署 Windows 虚拟机」知识保留,适用于 Windows 10/11 的服务器、桌面、测试等各种用途。

## 关联文档(上层目录)

- [PVE/Xbox适配器直通Bazzite.md](../Xbox适配器直通Bazzite.md) — USB 直通与宿主驱动冲突排错对照
- [PVE/Bazzite直通硬盘Steam库.md](../Bazzite直通硬盘Steam库.md) — 整盘直通背景
- [PVE/Flirc遥控启动虚拟机.md](../Flirc遥控启动虚拟机.md) — PVE API 遥控开机方案
