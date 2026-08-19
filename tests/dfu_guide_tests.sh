#!/bin/bash
# dfu_guide.sh 离线测试（mock 命令模拟四种设备状态）
# 用法: bash tests/dfu_guide_tests.sh
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MOCKS="$ROOT/tests/mocks"
STATEDIR="/tmp/dfu_guide_test"
mkdir -p "$STATEDIR"
PASS=0
FAIL=0

check() { # check <名称> <期望包含> <实际输出> <期望退出码> <实际退出码>
    local name="$1" expect="$2" out="$3" want_rc="$4" got_rc="$5"
    if echo "$out" | grep -qF "$expect" && [[ "$got_rc" == "$want_rc" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (期望包含 '$expect' 且 rc=${want_rc}，实际 rc=${got_rc})"
        echo "$out" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

run() { # run <MOCK_STATE> <stdin内容> <参数...>  → 全局 out/rc
    local state="$1" input="$2"
    shift 2
    out=$(IRECOVERY="$MOCKS/irecovery" IDEVICEENTER="$MOCKS/ideviceenterrecovery" \
        IDEVICERESTORE="$MOCKS/idevicerestore" \
        PATH="$MOCKS:$PATH" MOCK_STATE="$state" \
        MOCK_STATE_FILE="$STATEDIR/state" MOCK_COUNTER_FILE="$STATEDIR/counter" \
        MOCK_PRODUCT="${MOCK_PRODUCT:-}" MOCK_DFU_AFTER="${MOCK_DFU_AFTER:-}" \
        DFU_GUIDE_MAX_RETRIES=3 DFU_GUIDE_NO_COUNTDOWN=1 \
        bash "$ROOT/dfu_guide.sh" "$@" 2>&1 <<<"$input")
    rc=$?
}

reset_state() {
    rm -f "$STATEDIR/state" "$STATEDIR/counter"
}

# --- 状态检测（check 子命令）---
reset_state
run DFU "" check
check "DFU 状态检测" "DFU 模式" "$out" 0 "$rc"

reset_state
run Recovery "" check
check "Recovery 状态检测" "恢复模式" "$out" 0 "$rc"

reset_state
run Normal "" check
check "Normal 状态检测" "正常模式" "$out" 0 "$rc"

reset_state
run NONE "" check
check "无设备状态检测" "未检测到设备" "$out" 0 "$rc"

# --- boot 子命令 ---
reset_state
run DFU "" boot
check "已在 DFU 直接退出" "已进入 DFU 模式" "$out" 0 "$rc"

reset_state
MOCK_DFU_AFTER=1 run Recovery "" boot
check "引导中途进入 DFU" "已进入 DFU 模式" "$out" 0 "$rc"

reset_state
run Recovery "" boot
check "重试后仍失败" "进入 DFU 模式失败" "$out" 1 "$rc"

reset_state
run Normal "" boot
check "正常模式+SE2（音量减组合）" "音量减" "$out" 1 "$rc"

reset_state
MOCK_PRODUCT=iPhone8,1 run Normal "" boot
check "正常模式+6s（Home 组合）" "返回键" "$out" 1 "$rc"

reset_state
MOCK_PRODUCT=iPad11,2 run Recovery "" boot
check "恢复模式+iPad（Home 组合）" "返回键" "$out" 1 "$rc"

reset_state
MOCK_DFU_AFTER=1 run Normal "" boot
check "正常模式自动切恢复后引导成功" "已进入 DFU 模式" "$out" 0 "$rc"

# --- 菜单 ---
reset_state
run Normal "3"
check "菜单退出" "正在退出" "$out" 2 "$rc"

reset_state
run Normal "9"
check "菜单无效选项" "无效的选项" "$out" 0 "$rc"

echo ""
echo "通过 ${PASS}，失败 ${FAIL}"
[[ $FAIL -eq 0 ]]
