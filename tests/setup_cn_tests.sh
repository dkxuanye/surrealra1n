#!/bin/bash
# setup_cn.sh 离线测试（mock 命令模拟各场景）
# 用法: bash tests/setup_cn_tests.sh
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MOCKS="$ROOT/tests/mocks"
TMPD=$(mktemp -d /tmp/setup_cn_test.XXXXXX)
trap 'rm -rf "$TMPD"' EXIT
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

run() { # run <额外环境变量串> <参数...>  → 全局 out/rc
    local extra="$1"
    shift
    out=$(eval "PATH=\"$MOCKS:\$PATH\" SETUP_CN_FAST=1 SETUP_CN_ZSHRC=\"$TMPD/zshrc\" \
        MOCK_BREW_LOG=\"$TMPD/brew.log\" MOCK_GIT_LOG=\"$TMPD/git.log\" \
        MOCK_CURL_LOG=\"$TMPD/curl.log\" MOCK_CLT_COUNTER=\"$TMPD/clt\" \
        MOCK_BREW_STATE=\"$TMPD/brew_state\" \
        MOCK_BREW_INSTALLED=\"\${MOCK_BREW_INSTALLED:-}\" MOCK_BREW_FAIL=\"\${MOCK_BREW_FAIL:-}\" \
        MOCK_BREW_PREFIX=\"\${MOCK_BREW_PREFIX:-}\" MOCK_CLT_FAIL=\"\${MOCK_CLT_FAIL:-}\" \
        MOCK_UNAME=\"\${MOCK_UNAME:-}\" \
        HOMEBREW_BOTTLE_DOMAIN=\"\${MOCK_HBB_DOMAIN:-}\" HOMEBREW_API_DOMAIN=\"\${MOCK_API_DOMAIN:-}\" \
        $extra \
        bash \"$ROOT/setup_cn.sh\" \"\$@\" 2>&1" )
    rc=$?
}

reset_env() {
    unset MOCK_BREW_INSTALLED MOCK_BREW_FAIL MOCK_BREW_PREFIX MOCK_CLT_FAIL MOCK_UNAME MOCK_HBB_DOMAIN
    rm -f "$TMPD/zshrc" "$TMPD/brew.log" "$TMPD/git.log" "$TMPD/curl.log" "$TMPD/clt" "$TMPD/brew_state"
}

# --- 场景 1：非 macOS ---
reset_env
MOCK_UNAME=Linux run ""
check "非 macOS 拒绝" "仅支持 macOS" "$out" 1 "$rc"

# --- 场景 2：brew 已装 + 依赖全装 ---
reset_env
MOCK_BREW_INSTALLED="libimobiledevice libirecovery libusb binutils jq aria2" run ""
check "全部依赖已装" "全部依赖就绪" "$out" 0 "$rc"
if ! grep -qF "brew install libimobiledevice" "$TMPD/brew.log" 2>/dev/null; then
    echo "PASS: 已装依赖被跳过安装"
    PASS=$((PASS + 1))
else
    echo "FAIL: 已装依赖被重复安装"
    FAIL=$((FAIL + 1))
fi

# --- 场景 3：brew 已装 + 部分依赖缺失（全部安装成功）---
reset_env
MOCK_BREW_INSTALLED="libimobiledevice" run ""
check "缺失依赖被安装" "正在安装 jq" "$out" 0 "$rc"
check "整体成功" "全部依赖就绪" "$out" 0 "$rc"

# --- 场景 4：依赖安装失败（不中断，退出码 1）---
reset_env
MOCK_BREW_INSTALLED="" MOCK_BREW_FAIL="jq aria2" run ""
check "失败提示与重试命令" "brew install jq" "$out" 1 "$rc"
check "失败不中断其余依赖" "正在安装 binutils" "$out" 1 "$rc"

# --- 场景 5：--dry-run（不执行网络/写盘操作）---
reset_env
run "" "--dry-run"
check "演练提示" "演练" "$out" 0 "$rc"
if [[ ! -f "$TMPD/curl.log" ]]; then
    echo "PASS: dry-run 未调用 curl"
    PASS=$((PASS + 1))
else
    echo "FAIL: dry-run 调用了 curl"
    FAIL=$((FAIL + 1))
fi
if [[ ! -f "$TMPD/zshrc" ]]; then
    echo "PASS: dry-run 未写 zshrc"
    PASS=$((PASS + 1))
else
    echo "FAIL: dry-run 写了 zshrc"
    FAIL=$((FAIL + 1))
fi

# --- 场景 6：镜像配置幂等（zshrc 只写一次）---
reset_env
run ""
run ""
lines=$(grep -c "^export HOMEBREW_BOTTLE_DOMAIN=" "$TMPD/zshrc" 2>/dev/null || echo 0)
check "zshrc 幂等" "export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles" "$(cat "$TMPD/zshrc" 2>/dev/null)" 0 0
if [[ "$lines" == "1" ]]; then
    echo "PASS: zshrc 无重复行"
    PASS=$((PASS + 1))
else
    echo "FAIL: zshrc 重复行数 $lines"
    FAIL=$((FAIL + 1))
fi

# --- 场景 7：--mirror ustc ---
reset_env
run "" "--mirror" "ustc"
check "USTC 切换" "中科大 USTC" "$out" 0 "$rc"
check "USTC URL" "mirrors.ustc.edu.cn/homebrew-bottles" "$(cat "$TMPD/zshrc" 2>/dev/null)" 0 0

# --- 场景 8：未知镜像 ---
reset_env
run "" "--mirror" "foo"
check "未知镜像报错" "未知镜像" "$out" 1 "$rc"

# --- 场景 9：CLT 缺失后补装 ---
reset_env
MOCK_CLT_FAIL=1 run ""
check "CLT 补装后继续" "Xcode 命令行工具已安装" "$out" 0 "$rc"

# --- 场景 10：尊重已有镜像配置（不覆盖）---
reset_env
MOCK_HBB_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles" run ""
check "已有镜像配置被保留" "跳过镜像覆盖" "$out" 0 "$rc"
if [[ ! -f "$TMPD/zshrc" ]]; then
    echo "PASS: 已有配置时未写 zshrc"
    PASS=$((PASS + 1))
else
    echo "FAIL: 已有配置时仍写 zshrc"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "通过 ${PASS}，失败 ${FAIL}"
[[ $FAIL -eq 0 ]]
