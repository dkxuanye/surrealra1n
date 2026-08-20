# 国内资源全覆盖实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 覆盖 surrealra1n 的全部国内资源需求：GitHub 二进制下载（106 处 curl -L）、git clone、pip3，通过可配置代理前缀 + git insteadOf + 清华 PyPI。

**Architecture:** ① surrealra1n.sh 新增 `curl_l()` 前缀感知函数并批量替换 106 处 `curl -L`；② i18n_verify.py 白名单加 `curl_l`/`GITHUB_PROXY`；③ setup_cn.sh 新增 `set_github_proxy()`/`set_git_insteadof()`/`set_pip_mirror()`（流程 5 步→7 步，`--proxy`/`--no-proxy` 参数）；④ 新增 curl_l 单元测试 + setup_cn 测试扩展（mock git config / pip3）。

**Tech Stack:** bash + Python（verify），仅 macOS。

**关键约束：**
- `GITHUB_PROXY` 为空时 surrealra1n.sh 行为逐字节不变（curl_l 纯透传）
- sed 替换必须在添加 curl_l 函数**之前**执行（否则函数体 `curl -L "$@"` 会被误替换成递归）
- i18n_verify 改动行审计需放行 curl_l 函数体行（含 GITHUB_PROXY 关键字）
- 所有 `$变量` 紧跟全角字符处用 `${变量}`（bash 3.2 兼容）

---

### Task 1: surrealra1n.sh curl_l 改造 + verify 白名单

**Files:**
- Modify: `surrealra1n.sh`（106 处替换 + 新增函数）
- Modify: `scripts/i18n_verify.py`

- [ ] **Step 1: 批量替换 106 处 curl -L（在添加函数之前！）**

Run:
```bash
sed -i '' 's/^\([[:space:]]*\)curl -L /\1curl_l /' surrealra1n.sh
rg -c "curl -L " surrealra1n.sh
```
Expected: `rg -c "curl -L "` 输出 `0`（全部替换完成）；`rg -c "curl_l " surrealra1n.sh` 输出 `106`。

- [ ] **Step 2: 在版本变量之后新增 curl_l 函数**

Edit：oldString
```
CURRENT_VERSION="v2.0 beta 29"
VERSION_DISPLAY="v2.0 测试版 29"
```
newString
```
CURRENT_VERSION="v2.0 beta 29"
VERSION_DISPLAY="v2.0 测试版 29"

# GitHub 下载加速：GITHUB_PROXY 非空时自动为 github.com URL 加前缀
curl_l() {
    local url last
    for last in "$@"; do :; done
    if [[ -n "${GITHUB_PROXY:-}" && "$last" == https://github.com/* ]]; then
        set -- "${@:1:$#-1}" "${GITHUB_PROXY}${last}"
    fi
    curl -L "$@"
}
```

- [ ] **Step 3: 更新 i18n_verify.py 白名单**

Edit：`scripts/i18n_verify.py` 的 OUTPUT_TOKENS：
```
OUTPUT_TOKENS = re.compile(
    r"\b(?:echo|printf|read|pick_file|zenity|title|INFO_TEXT|CURRENT_VERSION|VERSION_DISPLAY)\b"
)
```
改为：
```
OUTPUT_TOKENS = re.compile(
    r"\b(?:echo|printf|read|pick_file|zenity|title|INFO_TEXT|CURRENT_VERSION|VERSION_DISPLAY|curl_l|GITHUB_PROXY)\b"
)
```

- [ ] **Step 4: 验证**

Run:
```bash
bash -n surrealra1n.sh
python3 scripts/i18n_verify.py
```
Expected: bash -n 无输出；verify 最后一行 `全部检查通过`。

- [ ] **Step 5: 提交**

```bash
git add surrealra1n.sh scripts/i18n_verify.py
git commit -m "feat: proxy-aware github downloads via curl_l"
```

---

### Task 2: curl_l 单元测试

**Files:**
- Create: `tests/mocks/curl`（已存在于 setup_cn 测试，这里新建独立 mock 目录或复用——复用 `tests/mocks/curl`，但 curl_l_tests 需要独立日志路径，用环境变量覆盖）
- Create: `tests/curl_l_tests.sh`

- [ ] **Step 1: 创建 tests/curl_l_tests.sh**

```bash
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
```

- [ ] **Step 2: 检查 mock curl 兼容**

Run: `bash -c 'MOCK_CURL_LOG=/tmp/t.log tests/mocks/curl -L -o /tmp/x https://github.com/a/b; cat /tmp/t.log'`
Expected: 输出 `curl -L -o /tmp/x https://github.com/a/b`（现有 mock 已记录完整参数，兼容）。

- [ ] **Step 3: 运行测试**

Run: `bash tests/curl_l_tests.sh`
Expected: 5 项全部 PASS，退出码 0。

- [ ] **Step 4: 提交**

```bash
git add tests/curl_l_tests.sh
git commit -m "test: add curl_l proxy prefix unit tests"
```

---

### Task 3: setup_cn.sh 扩展（GitHub 代理 + git insteadOf + pip3）

**Files:**
- Modify: `setup_cn.sh`

- [ ] **Step 1: 新增变量与三个函数**

Edit：在 `DEPS=(...)` 之后、`ZSHRC=` 之前插入：

```
GH_PROXY="${SETUP_CN_GH_PROXY:-https://ghfast.top/}"
PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
```

Edit：在 `set_mirrors()` 函数之后新增：

```bash
# [5/7] GitHub 下载加速（GITHUB_PROXY 环境变量 + git insteadOf）
set_github_proxy() {
    if [[ $NO_PROXY -eq 1 ]]; then
        printy "已跳过 GitHub 代理配置（--no-proxy）"
        return 0
    fi
    if [[ -n "${GITHUB_PROXY:-}" && "$GITHUB_PROXY" != "$GH_PROXY" ]]; then
        printy "检测到已配置 GITHUB_PROXY=${GITHUB_PROXY}，跳过覆盖"
        return 0
    fi
    append_zshrc "export GITHUB_PROXY=$GH_PROXY"
    export GITHUB_PROXY="$GH_PROXY"
    # git insteadOf（幂等）
    local key="url.${GH_PROXY}https://github.com/.insteadOf"
    if git config --global --get-all "$key" >/dev/null 2>&1; then
        printg "✅ git insteadOf 已配置"
    else
        run git config --global "$key" "https://github.com/"
        printg "✅ git insteadOf 配置完成"
    fi
    printg "✅ GitHub 下载加速配置完成（${GH_PROXY}）"
}

# [6/7] pip3 清华源
set_pip_mirror() {
    if [[ -n "${PIP_INDEX_URL_USER:-}" && "$PIP_INDEX_URL_USER" != "$PIP_INDEX_URL" ]]; then
        printy "检测到已配置 pip 源=${PIP_INDEX_URL_USER}，跳过覆盖"
        return 0
    fi
    if pip3 config get global.index-url 2>/dev/null | grep -qF "$PIP_INDEX_URL"; then
        printg "✅ pip3 已使用清华源"
    else
        run pip3 config set global.index-url "$PIP_INDEX_URL"
        printg "✅ pip3 清华源配置完成"
    fi
}
```

注意：`set_github_proxy` 中 git insteadOf 的 key 变量 `$key` 在幂等检查里使用 `git config --global --get-all "$key"` —— mock 测试中 `$key` 含 `https://` 和 `.`，用双引号包裹即可。bash 3.2 检查：`$key` 后紧跟 `"`（ASCII）无隐患；`${GH_PROXY}https://github.com/.insteadOf` 中 `GH_PROXY` 用花括号 ✓。

- [ ] **Step 2: 更新 main() 流程与参数**

Edit：`main()` 的参数解析 case 增加：

```
            --proxy) GH_PROXY="${2:-}"; shift 2 ;;
            --no-proxy) NO_PROXY=1; shift ;;
```

Edit：`main()` 的流程（在 set_mirrors 与 install_deps 之间插入两行）：

```
    check_os
    ensure_xcode_clt
    install_homebrew
    set_mirrors
    set_github_proxy
    set_pip_mirror
    install_deps
    print_summary
```

Edit：顶部变量初始化区（`DRY_RUN=0` 附近）增加：

```
NO_PROXY=0
```

- [ ] **Step 3: 语法检查**

Run: `bash -n setup_cn.sh`
Expected: 无输出，退出码 0

- [ ] **Step 4: 提交**

```bash
git add setup_cn.sh
git commit -m "feat: add github proxy, git insteadOf and pip mirror to setup_cn"
```

---

### Task 4: 测试扩展（mock git config / pip3 + 新场景）

**Files:**
- Modify: `tests/mocks/git`
- Create: `tests/mocks/pip3`
- Modify: `tests/setup_cn_tests.sh`

- [ ] **Step 1: 更新 tests/mocks/git（支持 config 子命令）**

当前内容：
```bash
#!/bin/bash
echo "git $*" >> "${MOCK_GIT_LOG:-/tmp/setup_cn_git_log}"
exit 0
```
改为：
```bash
#!/bin/bash
# 模拟 git：config --global --get-all 返回 MOCK_GIT_INSTEADOF；其余记录日志
if [[ "$1" == "config" && "$2" == "--global" && "$3" == "--get-all" ]]; then
    if [[ -n "${MOCK_GIT_INSTEADOF:-}" ]]; then
        echo "$MOCK_GIT_INSTEADOF"
        exit 0
    fi
    exit 1
fi
echo "git $*" >> "${MOCK_GIT_LOG:-/tmp/setup_cn_git_log}"
exit 0
```

- [ ] **Step 2: 创建 tests/mocks/pip3**

```bash
#!/bin/bash
# 模拟 pip3 config：get 返回 MOCK_PIP_INDEX（未配置时 exit 1）；set 记录日志
if [[ "$1" == "config" && "$2" == "get" ]]; then
    if [[ -n "${MOCK_PIP_INDEX:-}" ]]; then
        echo "$MOCK_PIP_INDEX"
        exit 0
    fi
    exit 1
fi
if [[ "$1" == "config" && "$2" == "set" ]]; then
    echo "pip3 $*" >> "${MOCK_PIP_LOG:-/tmp/setup_cn_pip_log}"
fi
exit 0
```

- [ ] **Step 3: 更新 tests/setup_cn_tests.sh（run() 透传 + 场景 10 断言 + 新场景）**

**先更新场景 10 的断言**（新增的 GITHUB_PROXY/pip 配置会正常写入 zshrc，原断言"未写 zshrc"不再成立——改为只断言 HOMEBREW 镜像配置未被覆盖）：

Edit：oldString
```
if [[ ! -f "$TMPD/zshrc" ]]; then
    echo "PASS: 已有配置时未写 zshrc"
    PASS=$((PASS + 1))
else
    echo "FAIL: 已有配置时仍写 zshrc"
    FAIL=$((FAIL + 1))
fi
```
newString
```
if ! grep -qF "HOMEBREW_BOTTLE_DOMAIN" "$TMPD/zshrc" 2>/dev/null; then
    echo "PASS: 已有镜像配置时未覆盖 HOMEBREW_BOTTLE_DOMAIN"
    PASS=$((PASS + 1))
else
    echo "FAIL: 已有镜像配置时仍写 HOMEBREW_BOTTLE_DOMAIN"
    FAIL=$((FAIL + 1))
fi
```

**再更新 run() 的环境前缀**，在 `HOMEBREW_BOTTLE_DOMAIN=...` 行后增加：

```
        GITHUB_PROXY=\"\${MOCK_GH_PROXY:-}\" PIP_INDEX_URL_USER=\"\${MOCK_PIP_INDEX:-}\" \\
        MOCK_GIT_INSTEADOF=\"\${MOCK_GIT_INSTEADOF:-}\" MOCK_PIP_LOG=\"$TMPD/pip.log\" \\
        SETUP_CN_GH_PROXY=\"\${MOCK_GH_PROXY_URL:-https://ghfast.top/}\" \\
```

Edit reset_env() 的 unset 与 rm 增加：

```
    unset MOCK_BREW_INSTALLED MOCK_BREW_FAIL MOCK_BREW_PREFIX MOCK_CLT_FAIL MOCK_UNAME MOCK_HBB_DOMAIN MOCK_GH_PROXY MOCK_PIP_INDEX MOCK_GIT_INSTEADOF
    rm -f "$TMPD/zshrc" "$TMPD/brew.log" "$TMPD/git.log" "$TMPD/curl.log" "$TMPD/clt" "$TMPD/brew_state" "$TMPD/pip.log"
```

在文件末尾（场景 10 之后）新增场景 11-14：

```bash
# --- 场景 11：默认 GitHub 代理写入（幂等）---
reset_env
run ""
run ""
lines=$(grep -c "^export GITHUB_PROXY=" "$TMPD/zshrc" 2>/dev/null || echo 0)
check "代理写入 zshrc" "export GITHUB_PROXY=https://ghfast.top/" "$(cat "$TMPD/zshrc" 2>/dev/null)" 0 0
if [[ "$lines" == "1" ]]; then
    echo "PASS: GITHUB_PROXY 无重复行"
    PASS=$((PASS + 1))
else
    echo "FAIL: GITHUB_PROXY 重复行数 $lines"
    FAIL=$((FAIL + 1))
fi

# --- 场景 12：--no-proxy 不写 GITHUB_PROXY ---
reset_env
run "" "--no-proxy"
if ! grep -qF "GITHUB_PROXY" "$TMPD/zshrc" 2>/dev/null; then
    echo "PASS: --no-proxy 未写 GITHUB_PROXY"
    PASS=$((PASS + 1))
else
    echo "FAIL: --no-proxy 仍写 GITHUB_PROXY"
    FAIL=$((FAIL + 1))
fi

# --- 场景 13：git insteadOf 已配置则跳过 ---
reset_env
MOCK_GIT_INSTEADOF="https://github.com/" run ""
check "insteadOf 跳过" "git insteadOf 已配置" "$out" 0 "$rc"

# --- 场景 14：pip3 清华源（未配置→写入；已配置→跳过）---
reset_env
run ""
check "pip3 写入清华源" "pip3 清华源配置完成" "$out" 0 "$rc"
if grep -qF "pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple" "$TMPD/pip.log" 2>/dev/null; then
    echo "PASS: pip3 set 已调用"
    PASS=$((PASS + 1))
else
    echo "FAIL: pip3 set 未调用"
    FAIL=$((FAIL + 1))
fi
reset_env
MOCK_PIP_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple" run ""
check "pip3 已配置跳过" "pip3 已使用清华源" "$out" 0 "$rc"
```

- [ ] **Step 4: chmod + 运行全部测试**

Run:
```bash
chmod +x tests/mocks/pip3
bash tests/setup_cn_tests.sh
bash tests/curl_l_tests.sh
```
Expected: setup_cn 全部 PASS（原 18 + 新 8 断言）；curl_l 5 项 PASS。

- [ ] **Step 5: 提交**

```bash
git add tests/
git commit -m "test: extend setup_cn tests for github proxy, git insteadOf and pip mirror"
```

---

### Task 5: 回归 + 收尾

**Files:**
- Review: 全部改动

- [ ] **Step 1: 全面回归**

Run:
```bash
bash -n surrealra1n.sh
bash -n setup_cn.sh
python3 scripts/i18n_verify.py | tail -2
bash tests/setup_cn_tests.sh | tail -2
bash tests/curl_l_tests.sh | tail -2
bash tests/dfu_guide_tests.sh | tail -2
```
Expected: 全部无错误；i18n_verify `全部检查通过`；三个测试套件各 `通过 N，失败 0`。

- [ ] **Step 2: bash 3.2 隐患扫描**

Run:
```bash
python3 -c "
import re
for f in ['surrealra1n.sh', 'setup_cn.sh', 'tests/curl_l_tests.sh', 'tests/setup_cn_tests.sh']:
    t = open(f, encoding='utf-8').read()
    hits = re.findall(r'\\\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]', t)
    print(f, len(hits), hits[:3])"
```
Expected: 全部为 0。

- [ ] **Step 3: 提交收尾（如有修复）**

若有修复：
```bash
git add -A && git commit -m "fix: reconcile china coverage changes"
```

- [ ] **Step 4: 汇总验收**

向控制器报告：
1. 各验证输出
2. 实机验证步骤：`./setup_cn.sh` → `surrealra1n.sh` 启动（binaries 下载应走 ghfast.top 前缀，可观察日志）→ 若代理失效用 `./setup_cn.sh --no-proxy` 或 `--proxy <其他前缀>` 重新配置
3. 提示：教程中注明 ghfast.top 为第三方服务，失效时可切换
