# PVE Bazzite 虚拟机部署

> **方案状态(2026-09-05)**:Bazzite 游戏 VM 已退役。原「Bazzite 客厅游戏机」目标先后尝试 Windows 方案后一并放弃(沿革见 [Windows虚拟机部署/Windows10-11虚拟机部署指南.md](../Windows虚拟机部署/Windows10-11虚拟机部署指南.md) §11)。
> 本目录收录 Bazzite/Linux 桌面客机的**操作案例存档**,通用知识不重复收录,一律指向 PVE 顶层通用指南。

## 目录内容

| 文件 | 说明 |
| --- | --- |
| [Steam硬盘库.md](Steam硬盘库.md) | 案例:直通硬盘添加 Steam 游戏库(Flatpak 权限 + 无显卡回桌面模式) |

## 通用参考(客户机无关,PVE 顶层)

- [显卡直通](../显卡直通.md) — GPU PCIe 直通/回退法(本目录案例的"禁用显卡回控制台"即此法)
- [硬盘直通](../硬盘直通.md) — 整盘/控制器直通
- [Xbox直通](../Xbox直通.md) — USB 直通(含 Linux xone 深度排错)
- [Flirc遥控开关机](../Flirc遥控开关机.md) — 宿主侧遥控电源管理

## 关联说明

- Bazzite 是 Linux 客机:VM 创建/驱动链/直通姿势与 Windows 客机基本一致,流程参照 [Windows虚拟机部署/Windows10-11虚拟机部署指南.md](../Windows虚拟机部署/Windows10-11虚拟机部署指南.md)(仅客机内系统配置不同)
- 若未来重建 Bazzite/Linux 游戏机,可将本目录扩展为完整部署指南(README + 指南 + 脚本的形态,与 Windows 目录对仗)
