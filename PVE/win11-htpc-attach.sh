#!/usr/bin/env bash
# =============================================================================
# win11-htpc-attach.sh —— Win11 HTPC 虚拟机直通设备接入(第二阶段)
#
# 适用:Proxmox VE 8.x/9.x,配合 Win11客厅HTPC.md 第 6~9 节
# 前置:win11-htpc-deploy.sh 已建机、Windows 已安装完成并正常进过桌面
#
# 本脚本对「已关机」的 VM 执行:
#   1. 显卡直通:RX 6650 XT(1002:73ef)+ HDMI 音频(1002:ab28)
#      ——地址动态检测;x-vga=1 + pcie=1
#   2. 显示设备置 none(画面完全走直通卡物理输出)
#   3. Xbox 无线适配器 USB 直通(host=045e:02fe,usb3=0)
#   4. 直通游戏盘(整盘 by-id 方式,供 Windows 格式化 NTFS)
#   5. 开机自启(startup order=1,配合 24h 常开方案)
#
# 安全承诺:
#   - VM 运行中会拒绝操作(要求先关机)
#   - 检测到其他 VM 配置占用了同一设备时拒绝执行
#   - 执行前备份 conf 到 /root/backup/
#   - 不删除、不格式化任何数据(直通盘交给 Windows 侧处理)
#
# 用法:
#   ./win11-htpc-attach.sh [参数]
#   --vmid N        VMID(默认自动检测名为 win11-htpc 的 VM)
#   --disk PATH     直通盘路径(如 /dev/disk/by-id/ata-XXXX;默认交互选择)
#   --no-disk       不接直通盘(稍后手动加)
#   --no-usb        不接 Xbox 适配器(稍后手动加)
#   --gpu ADDR      显卡 PCI 地址(默认自动检测,如 03:00)
#   --dry-run       只展示将执行的 qm set,不执行
#   -h, --help      帮助
# =============================================================================
set -euo pipefail

VMID=""
DISK=""
NO_DISK=0
NO_USB=0
GPU_ADDR=""
DRY_RUN=0

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

die() { echo "[错误] $*" >&2; exit 1; }
log() { echo "[步骤] $*"; }
warn() { echo "[警告] $*"; }

# ---- 参数解析 ---------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --vmid)      [[ $# -ge 2 ]] || die "--vmid 需要参数值"; VMID="$2"; shift 2 ;;
        --disk)      [[ $# -ge 2 ]] || die "--disk 需要参数值"; DISK="$2"; shift 2 ;;
        --no-disk)   NO_DISK=1; shift ;;
        --no-usb)    NO_USB=1; shift ;;
        --gpu)       [[ $# -ge 2 ]] || die "--gpu 需要参数值"; GPU_ADDR="$2"; shift 2 ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -h|--help)   usage ;;
        *) die "未知参数: $1(用 -h 查看帮助)" ;;
    esac
done

# ---- 预检 -------------------------------------------------------------------
[[ $EUID -eq 0 ]] || die "请以 root 运行"
command -v qm >/dev/null || die "未找到 qm,确认这是在 PVE 宿主机上运行"

# 定位 VM
if [[ -z "$VMID" ]]; then
    candidates=()
    for f in /etc/pve/qemu-server/*.conf; do
        [[ -e "$f" ]] || continue
        if grep -qi '^name:win11-htpc' "$f"; then
            candidates+=("${f##*/}")
        fi
    done
    case "${#candidates[@]}" in
        0) die "未找到名为 win11-htpc 的 VM,请用 --vmid 指定" ;;
        1) VMID="${candidates[0]%.conf}"; echo "[信息] 自动定位 VMID=$VMID" ;;
        *) echo "检测到多个候选,请用 --vmid 指定:" >&2; printf '  - %s\n' "${candidates[@]%.conf}" >&2; exit 1 ;;
    esac
fi
CONF="/etc/pve/qemu-server/$VMID.conf"
[[ -e "$CONF" ]] || die "VMID $VMID 配置文件不存在"

# VM 必须已关机
STATUS=$(qm status "$VMID" | awk '{print $2}')
if [[ "$STATUS" != "stopped" ]]; then
    die "VM 当前状态为 $STATUS,必须关机后才能接入直通设备(请先在 Web UI 关机)"
fi

# ---- 设备检测 ---------------------------------------------------------------
detect_pci() {  # $1=设备 ID;输出首个匹配的 PCI 地址,无则返回 1
    local addr
    addr=$(lspci -nn | awk -v id="$1" '$0 ~ "\\[" id "\\]" {print $1; exit}' || true)
    [[ -n "$addr" ]] || return 1
    echo "$addr"
}

if [[ -z "$GPU_ADDR" ]]; then
    GPU_ADDR=$(detect_pci '1002:73ef') || die "未检测到 RX 6650 XT(1002:73ef),请检查显卡是否插好,或用 --gpu 指定地址"
fi

# 音频功能(HDMI/DP 音频,Navi 23 音频 ID 1002:ab28;可与显卡同槽或不同槽,单独接入均可)
AUDIO_ADDR=$(detect_pci '1002:ab28') || true
if [[ -n "$AUDIO_ADDR" && "${AUDIO_ADDR%%.*}" != "${GPU_ADDR%%.*}" ]]; then
    warn "音频设备 ${AUDIO_ADDR} 与显卡 ${GPU_ADDR} 不在同一总线,将单独接入(仍可用,少见)"
fi

# 显卡必须已被 vfio-pci 接管
if ! lspci -nnk -s "$GPU_ADDR" 2>/dev/null | grep -q 'Kernel driver in use: vfio-pci'; then
    die "显卡 ${GPU_ADDR} 未被 vfio-pci 接管,请按文档第 2 节配置(vfio.conf + update-initramfs)后重启"
fi

# Xbox 适配器
USB_PRESENT=0
if lsusb 2>/dev/null | grep -qi '045e:02fe'; then
    USB_PRESENT=1
fi

# 冲突检测:其他 VM 是否占用了这些设备
check_conflict() {  # $1=conf 行匹配模式;$2=说明
    local hit=0 line f
    for f in /etc/pve/qemu-server/*.conf; do
        [[ -e "$f" ]] || continue
        [[ "$f" == "$CONF" ]] && continue
        line=$(grep -E "$1" "$f" 2>/dev/null || true)
        if [[ -n "$line" ]]; then
            hit=1
            warn "VM ${f##*/} 仍引用 ${2}:$line —— 请先在该 VM 中移除"
        fi
    done
    [[ $hit -eq 0 ]]
}
check_conflict "^(hostpci|usb)[0-9]*:" "直通设备" || die "存在设备占用冲突,解决后重试"

# ---- 直通盘选择 -------------------------------------------------------------
choose_disk() {
    local candidates=() i d size mounts
    echo "[信息] 宿主未挂载的整盘(排除系统盘)候选:"
    i=0
    for d in /dev/disk/by-id/ata-* /dev/disk/by-id/nvme-* /dev/disk/by-id/usb-*; do
        [[ -e "$d" ]] || continue
        case "$d" in *-part*) continue ;; esac
        mounts=$(lsblk -no MOUNTPOINTS "$d" 2>/dev/null | grep -v '^$' || true)
        [[ -n "$mounts" ]] && continue
        size=$(lsblk -dno SIZE "$d" 2>/dev/null || echo "?")
        candidates+=("$d")
        printf '  [%d] %s  (%s)\n' "$i" "$d" "$size"
        i=$((i + 1))
    done
    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "  无候选盘。可稍后手动添加,或检查:游戏盘是否被宿主挂载/盘符是否还在。"
        return 1
    fi
    read -r -p "输入要直通的盘编号(其他键跳过): " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [[ $sel -lt ${#candidates[@]} ]]; then
        DISK="${candidates[$sel]}"
    else
        echo "已跳过直通盘(稍后可在硬件中手动添加)。"
        return 1
    fi
}

if [[ $NO_DISK -eq 0 && -z "$DISK" ]]; then
    choose_disk || true
fi
if [[ -n "$DISK" ]]; then
    [[ -e "$DISK" ]] || die "直通盘不存在: $DISK"
fi

# ---- 动作总览 ---------------------------------------------------------------
echo "============================================================"
echo "将对 VMID=$VMID 执行以下接入(VM 当前已关机):"
echo "  显卡     : hostpci0  $GPU_ADDR,pcie=1,x-vga=1"
if [[ -n "$AUDIO_ADDR" ]]; then
    echo "  HDMI音频 : hostpci1  $AUDIO_ADDR,pcie=1"
else
    echo "  HDMI音频 : <未检测到 1002:ab28,跳过(稍后可在硬件中手动添加)>"
fi
echo "  显示     : vga=none(画面走直通卡,noVNC 将黑屏 = 正常)"
if [[ $NO_USB -eq 0 ]]; then
    if [[ $USB_PRESENT -eq 1 ]]; then
        echo "  Xbox适配器: usb0 host=045e:02fe,usb3=0"
    else
        echo "  Xbox适配器: <宿主 lsusb 未检测到 045e:02fe,将跳过;插上后重跑或手动添加>"
    fi
else
    echo "  Xbox适配器: 已跳过(--no-usb)"
fi
if [[ -n "$DISK" ]]; then
    echo "  直通盘   : scsi1 $DISK(仅接入,不格式化——格式化为 NTFS 请在 Windows 磁盘管理中操作)"
else
    echo "  直通盘   : 跳过"
fi
echo "  自启     : startup order=1(宿主机开机自动启动本 VM)"
echo "============================================================"

[[ $DRY_RUN -eq 1 ]] && { echo "[信息] dry-run:以上为将执行的接入,未做任何修改。"; exit 0; }

read -r -p "确认接入?输入 Y 继续,其他键退出: " ans
[[ "$ans" == "Y" || "$ans" == "y" ]] || { echo "已取消。"; exit 0; }

# ---- 执行接入 ---------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p /root/backup
log "备份 conf → /root/backup/win11-htpc-$VMID-$TS.conf"
cp "$CONF" "/root/backup/win11-htpc-$VMID-$TS.conf"

log "接入显卡 $GPU_ADDR ..."
qm set "$VMID" -hostpci0 "$GPU_ADDR,pcie=1,x-vga=1"

if [[ -n "$AUDIO_ADDR" ]]; then
    log "接入 HDMI 音频 $AUDIO_ADDR ..."
    qm set "$VMID" -hostpci1 "$AUDIO_ADDR,pcie=1"
fi

log "显示设备置 none ..."
qm set "$VMID" -vga none

if [[ $NO_USB -eq 0 && $USB_PRESENT -eq 1 ]]; then
    log "接入 Xbox 无线适配器(045e:02fe,usb3=0)..."
    qm set "$VMID" -usb0 host=045e:02fe,usb3=0
fi

if [[ -n "$DISK" ]]; then
    log "接入直通盘 $DISK ..."
    qm set "$VMID" -scsi1 "$DISK"
fi

log "设置开机自启(startup order=1)..."
qm set "$VMID" -startup order=1

# ---- 验证 ----------------------------------------------------------------
echo
log "验证配置:"
qm config "$VMID" | grep -E '^(hostpci|usb0|vga|scsi1|startup)' || die "配置验证失败"

echo
log "接入完成。接下来的操作:"
echo "  1. 把 HDMI/DP 线接到 6650 XT 物理口(不是主板核显口),电视切到对应输入源"
echo "  2. 启动 VM → 进 Windows → 设备管理器应出现 Radeon RX 6650 XT 与 AMD HDMI 音频"
echo "  3. 安装 AMD Adrenalin 驱动(amd.com),装前无画面属正常,耐心等待"
echo "  4. 磁盘管理 → 初始化直通盘(GPT)→ 新建卷 NTFS → 分配给 D:"
echo "  5. Xbox 手柄长按配对键 + 适配器侧按键配对"
echo "  6. noVNC 黑屏 = 正常;需要回控制台排查时,按文档第 6.3 节回退法处理"
