# PVE USB 设备直通通用指南(Xbox 无线适配器为例)

> 通用性:USB 直通姿势适用于任意 USB 设备;Xbox 无线适配器(`045e:02fe`)为完整案例
> 实测环境:PVE 9.2;Xbox 无线适配器 + Series X|S 手柄;Windows 与 Linux(Bazzite)双客户机经验
> 关联:显卡直通见 [显卡直通.md](显卡直通.md),硬盘直通见 [硬盘直通.md](硬盘直通.md)

---

## 1. USB 直通通用姿势

```bash
# 1) 宿主确认设备在(记下 VID:PID)
lsusb | grep -i microsoft
# 例:Bus 001 Device 010: ID 045e:02fe Microsoft Corp. Xbox Wireless Adapter for Windows

# 2) 挂给虚拟机(VID:PID 方式最稳,端口号会漂移)
qm set <vmid> -usb0 host=045e:02fe            # 默认走 xHCI(USB3 通路)
qm set <vmid> -usb0 host=045e:02fe,usb3=0     # 强制 USB2 通路(部分设备/Linux 客户机需要)

# 3) 验证
qm config <vmid> | grep usb
```

**铁律**:
- USB/PCI 配置改动后**必须完全关机再开机**(重启不生效)
- 同一 USB 设备**不能同时配给两个 VM**(占用冲突)
- 设备物理拔插后,VM 内可能失联 → 冷启动恢复

## 2. Xbox 无线适配器型号与配对

| 型号 | USB ID | 说明 |
| --- | --- | --- |
| 现行款(小圆润) | `045e:02fe` | Series 世代,最常见 |
| 初代(大块头 2015) | `045e:02e6` | Xbox One 时代 |

**⚠️ 配对键位置(最容易搞错的点)**:手柄的配对键**不是 Xbox logo 键**——是手柄**顶部边缘、USB 口旁的小圆凸钮**。长按 logo 只是开关机,按顶部小圆钮 logo 灯才会快闪进入配对。

配对流程:按适配器侧圆键(快闪)→ 30cm 内按住手柄顶部小圆钮 → 灯常亮即连上(以后开机自动回连)。

## 3. 客户机差异

| | Windows | Linux(如 Bazzite) |
| --- | --- | --- |
| 驱动 | 原生免驱 | xone/xow 第三方 |
| 设备位置 | 设备管理器 → **网络适配器**分类(正常!它按网络设备枚举) | `/sys/class/xone/dongle0` |
| 固件 | Windows Update / Xbox Accessories 更新 | xow 固件包 + 路径/SELinux 处理 |
| 配对 | 顶部小圆钮,即插即用 | 需固件链路完整(见存档文档) |

Linux 客户机完整排错见 [Xbox适配器直通Bazzite.md](Xbox适配器直通Bazzite.md)(固件缺失/SELinux/mt76 冲突三链路)。

## 4. 宿主侧冲突与卡死

- **mt76 无线网卡驱动抢占适配器**(USB 枚举正常但客户机拿不到)→ 宿主黑名单 mt76 系列
- **适配器硬件卡死**(重启/休眠后不响应)→ 硬复位:拔插 10 秒;`usbreset 045e:02fe`;终极:BIOS 开 **ErP Ready**(S4+S5,彻底断 USB 供电)

## 5. 排错流程(按序)

```
设备在客户机里看不到?
  ├─ 宿主 lsusb 有设备吗? 没有 → 物理/宿主驱动问题(§4)
  ├─ conf 里 usb0 在吗?    没有 → 重新挂载(§1)
  └─ 都在 → VM 冷启动 → 设备管理器/lsusb 复查
手柄配不上?
  ├─ 确认按的是顶部配对键(§2)!logo 键是开关机
  ├─ 换新电池(电压不足表现为"能闪连不上")
  ├─ 换 USB2 口/远离 USB3 设备(射频干扰)
  ├─ 冷启动 / 去掉 usb3=0 换通路
  └─ 裸机 A/B 测试:适配器插真 Windows 电脑试配——能配=VM 链路问题;不能配=固件/硬件问题(数据线刷手柄固件或换适配器)
```

## 6. 关联文档

- [Windows虚拟机部署/Windows10-11虚拟机部署指南.md](Windows虚拟机部署/Windows10-11虚拟机部署指南.md) — 完整 Windows 部署流程
- [Xbox适配器直通Bazzite.md](Xbox适配器直通Bazzite.md) — Linux 客户机固件/SELinux 排错案例
- [显卡直通.md](显卡直通.md) / [硬盘直通.md](硬盘直通.md)
