#!/bin/bash
# dfu_guide.sh - 引导设备进入 DFU 模式
# 灵感来源（spironolactone 项目商业工具逆向报告）：
#   rkeytools - 分步按键引导文案设计
#   ifine / skynet - DFUDetector 先检测后引导
#   iezpro - 完整设备状态机
#
# 用法:
#   ./dfu_guide.sh            交互菜单
#   ./dfu_guide.sh check      仅检测设备状态
#   ./dfu_guide.sh boot       直接引导（跳过菜单）
# 环境变量:
#   DFU_GUIDE_TIMEOUT         等待进 DFU 超时秒数（默认 120）
#   DFU_GUIDE_NO_COUNTDOWN=1  跳过倒计时（测试用）
#   IRECOVERY                 irecovery 路径覆盖（测试用）

DFU_VID="05ac"
DFU_PID_DFU="1227"
DFU_PID_RECOVERY="1281"
DFU_GUIDE_TIMEOUT="${DFU_GUIDE_TIMEOUT:-120}"
DFU_GUIDE_NO_COUNTDOWN="${DFU_GUIDE_NO_COUNTDOWN:-0}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IRECOVERY="${IRECOVERY:-$SCRIPT_DIR/bin/irecovery}"

trap 'echo ""; echo "已取消"; exit 130' INT

# 列出 USB 设备（macOS: ioreg；Linux: lsusb）
usb_devices() {
    if [[ "$(uname)" == "Darwin" ]]; then
        ioreg -r -c IOUSBHostDevice 2>/dev/null
    else
        lsusb 2>/dev/null
    fi
}

# 检测设备状态：DFU / Recovery / Normal / NONE
detect_device_state() {
    local mode out
    if [[ -x "$IRECOVERY" ]]; then
        out=$("$IRECOVERY" -q 2>/dev/null)
        mode=$(echo "$out" | grep "^MODE:" | cut -d ':' -f2 | xargs)
        if [[ "$mode" == "DFU" ]]; then
            echo "DFU"
            return
        elif [[ "$mode" == "Recovery" ]]; then
            echo "Recovery"
            return
        fi
    fi
    if usb_devices | grep -qiE "idProduct.*(1227|4647)|$DFU_VID:$DFU_PID_DFU"; then
        echo "DFU"
        return
    fi
    if usb_devices | grep -qiE "idProduct.*(1281|4737)|$DFU_VID:$DFU_PID_RECOVERY"; then
        echo "Recovery"
        return
    fi
    if command -v idevice_id >/dev/null 2>&1 && idevice_id -l 2>/dev/null | grep -q .; then
        echo "Normal"
        return
    fi
    echo "NONE"
}

# 识别机型（ProductType），失败输出空
identify_model() {
    local product
    if command -v ideviceinfo >/dev/null 2>&1; then
        product=$(ideviceinfo -k ProductType 2>/dev/null | xargs)
        if [[ -n "$product" ]]; then
            echo "$product"
            return
        fi
    fi
    echo ""
}

# 判断机型是否有 Home 键：0=有，1=无，2=未知
has_home_button() {
    case "$1" in
        iPod* | iPhone1,* | iPhone2,* | iPhone3,* | iPhone4,* | iPhone5,* | iPhone6,* | iPhone7,* | iPhone8,*)
            return 0 ;;
        iPhone*)
            return 1 ;;
        iPad1,* | iPad2,* | iPad3,* | iPad4,* | iPad5,* | iPad6,* | iPad7,* | iPad11,1 | iPad11,2 | iPad11,3 | iPad11,4 | iPad11,6 | iPad11,7 | iPad12,1 | iPad12,2)
            return 0 ;;
        iPad*)
            return 1 ;;
        *)
            return 2 ;;
    esac
}

# 倒计时（可跳过）
countdown() {
    local i
    if [[ "$DFU_GUIDE_NO_COUNTDOWN" == "1" ]]; then
        return
    fi
    for i in "$@"; do
        echo "$i"
        sleep 1
    done
}

# 分步引导文案（借鉴 rkeytools 的 stepText 分步设计）
guide_to_dfu() {
    local product home=1 second="音量减键" home_ans
    product=$(identify_model)
    if [[ -n "$product" ]]; then
        has_home_button "$product"
        home=$?
        if [[ $home -eq 2 ]]; then
            home=1
        fi
    else
        read -p "检测不到设备机型。你的设备有 Home 键吗？(y/n): " home_ans
        if [[ "$home_ans" == y || "$home_ans" == Y ]]; then
            home=0
        fi
    fi
    if [[ $home -eq 0 ]]; then
        second="Home 键"
    fi
    echo ""
    echo "=== 引导设备进入 DFU 模式 ==="
    if [[ -n "$product" ]]; then
        echo "设备：$product"
    else
        echo "设备：未知机型（${second}方案）"
    fi
    echo "当前状态：$(detect_device_state)"
    echo "按键组合：电源键 + $second"
    echo ""
    echo "请按以下步骤操作："
    echo "① 同时按住「电源键」和「${second}」，保持 10 秒"
    countdown 10 9 8 7 6 5 4 3 2 1
    echo "② 松开「电源键」，继续按住「${second}」"
    echo "   （屏幕保持黑屏，等待设备进入 DFU）"
    echo "③ 保持按住，等待自动进入 DFU 模式..."
}

# 打印设备状态描述
print_state() {
    case "$1" in
        DFU)      echo "设备状态：DFU 模式（已就绪）" ;;
        Recovery) echo "设备状态：恢复模式" ;;
        Normal)   echo "设备状态：正常模式" ;;
        *)        echo "设备状态：未检测到设备" ;;
    esac
}

# 轮询验证进入 DFU（依赖 detect_device_state 的 irecovery + USB VID/PID 检测）
wait_for_dfu() {
    local waited=0 state
    while (( waited < DFU_GUIDE_TIMEOUT )); do
        state=$(detect_device_state)
        if [[ "$state" == "DFU" ]]; then
            echo "✅ 设备已进入 DFU 模式！"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
        echo "[验证中，已等待 ${waited} 秒...]"
    done
    echo "❌ 超时：设备未在 ${DFU_GUIDE_TIMEOUT} 秒内进入 DFU 模式。"
    echo "   请检查按键操作是否正确，然后重试。"
    return 1
}

main() {
    local action="${1:-menu}" state opt
    state=$(detect_device_state)
    if [[ "$action" == "check" ]]; then
        print_state "$state"
        return 0
    fi
    if [[ "$state" == "DFU" ]]; then
        echo "设备已处于 DFU 模式，无需引导"
        exit 0
    fi
    if [[ "$action" == "boot" ]]; then
        guide_to_dfu
        wait_for_dfu
        exit $?
    fi
    while true; do
        echo ""
        echo "=== DFU 引导工具 ==="
        echo "设备状态：$state"
        echo ""
        echo "选项："
        echo "1. 引导设备进入 DFU 模式"
        echo "2. 仅检测设备状态"
        echo "3. 退出"
        read -p "请输入选项（1-3）：" opt || return 0
        case "$opt" in
            1) guide_to_dfu; wait_for_dfu; return $? ;;
            2) state=$(detect_device_state); print_state "$state" ;;
            3) echo "正在退出"; return 2 ;;
            *) echo "无效的选项。" ;;
        esac
    done
}

main "$@"
