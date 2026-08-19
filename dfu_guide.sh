#!/bin/bash
# dfu_guide.sh - 引导设备进入 DFU 模式
# 实现参照 Downr1n (downr1n.sh _dfuhelper) 的成熟流程：
#   1. 按 CPID 判定按键组合（0x801* 且非 iPad → 音量减+电源，否则 Home+电源）
#   2. irecovery -n 让设备重启，重启期间按住按键进入 DFU
#   3. step 倒计时 + 实时检测，失败自动重试
#
# 用法:
#   ./dfu_guide.sh            交互菜单
#   ./dfu_guide.sh check      仅检测设备状态
#   ./dfu_guide.sh boot       直接引导（跳过菜单）
# 环境变量:
#   DFU_GUIDE_MAX_RETRIES     最大尝试次数（默认 3）
#   DFU_GUIDE_NO_COUNTDOWN=1  跳过倒计时（测试用）
#   IRECOVERY                 irecovery 路径覆盖（测试用）

DFU_GUIDE_MAX_RETRIES="${DFU_GUIDE_MAX_RETRIES:-3}"
DFU_GUIDE_NO_COUNTDOWN="${DFU_GUIDE_NO_COUNTDOWN:-0}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IRECOVERY="${IRECOVERY:-$SCRIPT_DIR/bin/irecovery}"
IDEVICERESTORE="${IDEVICERESTORE:-$SCRIPT_DIR/bin/idevicerestore}"

trap 'echo ""; echo "已取消"; exit 130' INT

# 检测设备模式：dfu / recovery / normal / none（USB VID/PID 判定，同 Downr1n）
get_device_mode() {
    local sp apples apple
    if [[ "$(uname)" == "Darwin" ]]; then
        sp=$(system_profiler SPUSBDataType 2>/dev/null)
        apples=$(echo "$sp" | grep -B1 'Vendor ID: 0x05ac' | grep 'Product ID:' | cut -dx -f2 | cut -d' ' -f1)
    else
        apples=$(lsusb 2>/dev/null | cut -d' ' -f6 | grep '05ac:' | cut -d: -f2)
    fi
    for apple in $apples; do
        case "$apple" in
            12a8 | 12aa | 12ab) echo "normal" ;;
            1281) echo "recovery" ;;
            1227) echo "dfu" ;;
        esac
    done
    echo "none"
}

# 查询设备信息：_info recovery CPID / PRODUCT；_info normal ProductType
_info() {
    local mode="$1" key="$2"
    if [[ "$mode" == "recovery" ]]; then
        "$IRECOVERY" -q 2>/dev/null | grep "$key:" | sed "s/$key: //"
    else
        command -v ideviceinfo >/dev/null 2>&1 && ideviceinfo 2>/dev/null | grep "$key: " | sed "s/$key: //"
    fi
}

# 倒计时步骤：每 1 秒显示提示；检测到 DFU 立即返回；10 秒步骤在设备出现时提前结束
step() {
    local secs="$1" text="$2" i mode
    for i in $(seq "$secs" -1 0); do
        mode=$(get_device_mode | head -1)
        if [[ "$mode" == "dfu" ]]; then
            return 0
        fi
        if [[ "$secs" == "10" && "$mode" != "none" ]]; then
            return 0
        fi
        if [[ "$DFU_GUIDE_NO_COUNTDOWN" == "1" ]]; then
            continue
        fi
        printf '\r\e[K\e[1;36m%s (%d)' "$text" "$i"
        sleep 1
    done
    printf '\e[0m\n'
}

# 准备倒计时（可跳过）
prep_countdown() {
    local i
    if [[ "$DFU_GUIDE_NO_COUNTDOWN" == "1" ]]; then
        return
    fi
    for i in 3 2 1; do
        printf '\r\e[K\e[1;33m请准备：%d' "$i"
        sleep 1
    done
    printf '\e[0m\n'
}

# 正常模式 → 恢复模式（自动工具优先，失败给手动指引并等待）
enter_recovery() {
    local waited=0 mode tool udid
    echo "正在切换到恢复模式..."
    udid=$(idevice_id -l 2>/dev/null | head -1)
    if command -v ideviceenterrecovery >/dev/null 2>&1; then
        tool="ideviceenterrecovery $udid"
    elif [[ -x "$(ls /usr/local/Cellar/libimobiledevice/*/bin/ideviceenterrecovery 2>/dev/null | head -1)" ]]; then
        tool="$(ls /usr/local/Cellar/libimobiledevice/*/bin/ideviceenterrecovery 2>/dev/null | head -1) $udid"
    elif [[ -x "$IDEVICERESTORE" ]]; then
        tool="$IDEVICERESTORE -e"
    elif command -v idevicerestore >/dev/null 2>&1; then
        tool="idevicerestore -e"
    fi
    if [[ -n "$tool" ]]; then
        echo "正在使用 ${tool} 切换..."
        $tool >/dev/null 2>&1
    fi
    echo "如果设备没有自动进入恢复模式，请手动操作："
    echo "按住「音量减 + 电源键」，直到屏幕出现恢复模式画面后松开。"
    while (( waited < 20 )); do
        mode=$(get_device_mode | head -1)
        if [[ "$mode" == "recovery" ]]; then
            return 0
        fi
        if [[ "$DFU_GUIDE_NO_COUNTDOWN" == "1" ]]; then
            waited=$((waited + 1))
            continue
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "未检测到恢复模式，请手动进入恢复模式后重试。"
    return 1
}

# 引导进 DFU（Downr1n _dfuhelper 流程，带重试上限）
_dfuhelper() {
    local attempts=0 cpid deviceid step_one step_two
    while true; do
        if [[ "$(get_device_mode | head -1)" == "dfu" ]]; then
            echo "✅ 设备已进入 DFU 模式！"
            return 0
        fi
        if (( attempts >= DFU_GUIDE_MAX_RETRIES )); then
            echo "❌ 进入 DFU 模式失败，请检查按键操作后重新运行。"
            return 1
        fi
        attempts=$((attempts + 1))
        echo ""
        echo "第 ${attempts} 次尝试（共 ${DFU_GUIDE_MAX_RETRIES} 次）："
        cpid=$(_info recovery CPID | xargs)
        deviceid=$(_info recovery PRODUCT | xargs)
        if [[ -z "$deviceid" ]]; then
            deviceid=$(_info normal ProductType | xargs)
        fi
        if [[ "$deviceid" == *"iPad"* ]]; then
            step_one="按住 返回键(Home) + 电源键"
            step_two="松开 电源键, 继续按住 返回键(Home)"
        elif [[ "$cpid" == 0x801* || "$cpid" == 0x8030 ]]; then
            step_one="按住 音量减 + 电源键"
            step_two="松开 电源键, 继续按住 音量减"
        elif [[ -z "$cpid" ]] && [[ "$deviceid" == iPhone1[0-9],* || "$deviceid" == iPhone2[0-9],* ]]; then
            step_one="按住 音量减 + 电源键"
            step_two="松开 电源键, 继续按住 音量减"
        else
            step_one="按住 返回键(Home) + 电源键"
            step_two="松开 电源键, 继续按住 返回键(Home)"
        fi
        echo "按键组合：$step_one"
        if [[ "$(get_device_mode | head -1)" == "normal" ]]; then
            enter_recovery || continue
        fi
        echo "按回车开始引导，请同时将手指放在按键上做好准备："
        read -r _ || true
        prep_countdown
        "$IRECOVERY" -n 2>/dev/null
        step 4 "$step_one"
        step 10 "$step_two"
        sleep 1
    done
}

# 打印设备状态描述
print_state() {
    case "$1" in
        dfu)      echo "设备状态：DFU 模式（已就绪）" ;;
        recovery) echo "设备状态：恢复模式" ;;
        normal)   echo "设备状态：正常模式" ;;
        *)        echo "设备状态：未检测到设备" ;;
    esac
}

main() {
    local action="${1:-menu}" state opt
    state=$(get_device_mode | head -1)
    if [[ "$action" == "check" ]]; then
        print_state "$state"
        return 0
    fi
    if [[ "$action" == "boot" ]]; then
        _dfuhelper
        exit $?
    fi
    while true; do
        echo ""
        echo "=== DFU 引导工具 ==="
        print_state "$state"
        echo ""
        echo "选项："
        echo "1. 引导设备进入 DFU 模式"
        echo "2. 仅检测设备状态"
        echo "3. 退出"
        read -p "请输入选项（1-3）：" opt || return 0
        case "$opt" in
            1) _dfuhelper; return $? ;;
            2) state=$(get_device_mode | head -1); print_state "$state" ;;
            3) echo "正在退出"; return 2 ;;
            *) echo "无效的选项。" ;;
        esac
    done
}

main "$@"
