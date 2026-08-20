#!/bin/bash
# curl_l 函数单元测试（从 surrealra1n.sh 提取函数定义，mock curl 断言 URL 变换）
# 用法: bash tests/curl_l_tests.sh
set -u
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MOCKS="$ROOT/tests/mocks"
TMPD=$(mktemp -d /tmp/curl_l_test.XXXXXX)
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

# 提取 curl_l 函数定义（bash 3.2 不支持 source <()，用临时文件）
curl_l() { :; }
sed -n '/^curl_l()/,/^}/p' "$ROOT/surrealra1n.sh" > "$TMPD/curl_l_fn.sh"
source "$TMPD/curl_l_fn.sh"

run_curl() { # run_curl <GITHUB_PROXY> <URL...>  → 全局 out/rc（curl_log 记录）
    local proxy="$1"
    shift
    rm -f "$TMPD/curl.log"
    out=$(GITHUB_PROXY="$proxy" PATH="$MOCKS:$PATH" \
        MOCK_CURL_LOG="$TMPD/curl.log" curl_l "$@" 2>&1)
    rc=$?
    out=$(cat "$TMPD/curl.log" 2>/dev/null)
}

# 1. 无代理：URL 不变
run_curl "" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4"
check "无代理 URL 不变" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4" "$out" 0 "$rc"

# 2. 有代理：github.com 加前缀
run_curl "https://ghfast.top/" "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4"
check "代理加前缀" "https://ghfast.top/https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4" "$out" 0 "$rc"

# 3. 有代理：非 github.com 不变
run_curl "https://ghfast.top/" "https://updates.cdn-apple.com/foo.ipsw"
check "非 github 不变" "https://updates.cdn-apple.com/foo.ipsw" "$out" 0 "$rc"

# 4. 有代理：releases/download 链接也加前缀
run_curl "https://ghfast.top/" "https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64"
check "releases 链接加前缀" "https://ghfast.top/https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64" "$out" 0 "$rc"

# 5. 无代理时 -L 透传（mock curl 记录参数）
rm -f "$TMPD/curl.log"
GITHUB_PROXY="" PATH="$MOCKS:$PATH" MOCK_CURL_LOG="$TMPD/curl.log" \
    curl_l -o /tmp/x https://github.com/a/b 2>/dev/null
if grep -qF -- "-L -o /tmp/x https://github.com/a/b" "$TMPD/curl.log"; then
    echo "PASS: 无代理时 -L 透传"
    PASS=$((PASS + 1))
else
    echo "FAIL: -L 未透传: $(cat "$TMPD/curl.log" 2>/dev/null)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "通过 ${PASS}，失败 ${FAIL}"
[[ $FAIL -eq 0 ]]
