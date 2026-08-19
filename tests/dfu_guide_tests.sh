#!/bin/bash
# dfu_guide.sh 离线测试（mock 命令模拟四种设备状态）
# 用法: bash tests/dfu_guide_tests.sh
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MOCKS="$ROOT/tests/mocks"
rm -f /tmp/dfu_guide_mock_counter
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
    out=$(IRECOVERY="$MOCKS/irecovery" PATH="$MOCKS:$PATH" MOCK_STATE="$state" \
        DFU_GUIDE_TIMEOUT=3 DFU_GUIDE_NO_COUNTDOWN=1 \
        bash "$ROOT/dfu_guide.sh" "$@" 2>&1 <<<"$input")
    rc=$?
}

# --- 状态检测（check 子命令）---
run DFU "" check
check "DFU 状态检测" "DFU 模式" "$out" 0 "$rc"

run Recovery "" check
check "Recovery 状态检测" "恢复模式" "$out" 0 "$rc"

run Normal "" check
check "Normal 状态检测" "正常模式" "$out" 0 "$rc"

run NONE "" check
check "无设备状态检测" "未检测到设备" "$out" 0 "$rc"

# --- boot 子命令 ---
rm -f /tmp/dfu_guide_mock_counter
run DFU "" boot
check "已在 DFU 直接退出" "设备已处于 DFU 模式，无需引导" "$out" 0 "$rc"

rm -f /tmp/dfu_guide_mock_counter
run Normal "" boot
check "引导超时（3 秒）" "超时" "$out" 1 "$rc"

rm -f /tmp/dfu_guide_mock_counter
MOCK_DFU_AFTER=2 run Normal "" boot
check "引导中途进入 DFU" "设备已进入 DFU 模式" "$out" 0 "$rc"

rm -f /tmp/dfu_guide_mock_counter
run NONE "y" boot
check "无机型时询问 Home 键（y）" "Home 键" "$out" 1 "$rc"

rm -f /tmp/dfu_guide_mock_counter
run NONE "n" boot
check "无机型时询问 Home 键（n）" "音量减键" "$out" 1 "$rc"

# --- 菜单 ---
rm -f /tmp/dfu_guide_mock_counter
run Normal "3"
check "菜单退出" "正在退出" "$out" 0 "$rc"

echo ""
echo "通过 ${PASS}，失败 ${FAIL}"
[[ $FAIL -eq 0 ]]
