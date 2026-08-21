#!/bin/bash
# setup_cn.sh - 国内镜像一键安装 surrealra1n 依赖（仅 macOS + Homebrew）
# 用法:
#   ./setup_cn.sh               默认清华 TUNA 镜像
#   ./setup_cn.sh --mirror ustc 切换中科大 USTC
#   ./setup_cn.sh --proxy <前缀> GitHub 下载代理前缀（默认 https://ghfast.top/）
#   ./setup_cn.sh --no-proxy    跳过 GitHub 加速配置（自备代理）
#   ./setup_cn.sh --dry-run     只打印将执行的操作（演练）
#   ./setup_cn.sh --help        帮助
#
# 环境变量（测试/高级用）:
#   SETUP_CN_ZSHRC   ~/.zshrc 路径覆盖
#   SETUP_CN_FAST=1  跳过等待循环的 sleep

set -u

MIRROR="tuna"
DRY_RUN=0
NO_PROXY=0
DEPS=(libimobiledevice libirecovery libusb binutils jq aria2)
GH_PROXY="${SETUP_CN_GH_PROXY:-https://ghfast.top/}"
PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
ZSHRC="${SETUP_CN_ZSHRC:-$HOME/.zshrc}"
BREW=""


trap 'echo ""; echo "已取消"; exit 130' INT

printg() { printf "\e[32m%s\e[m\n" "$1"; }
printy() { printf "\e[33;1m%s\e[m\n" "$1"; }
printr() { printf "\e[31;1m%s\e[m\n" "$1"; }

usage() {
    echo "用法: ./setup_cn.sh [--mirror tuna|ustc] [--proxy <前缀>] [--no-proxy] [--dry-run] [--help]"
}

# 执行命令；dry-run 时只打印
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[演练] $*"
    else
        "$@"
    fi
}

# 定位 brew（PATH 优先，其次固定路径；测试用 PATH mock 生效）
find_brew() {
    if command -v brew >/dev/null 2>&1; then
        BREW="$(command -v brew)"
        return 0
    fi
    local p
    for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$p" ]]; then
            BREW="$p"
            return 0
        fi
    done
    return 1
}

# 按镜像设置 URL 变量
set_mirror_vars() {
    case "$MIRROR" in
        tuna)
            MIRROR_NAME="清华 TUNA"
            BREW_URL="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
            CORE_URL="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
            API_URL="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
            BOTTLE_URL="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            ;;
        ustc)
            MIRROR_NAME="中科大 USTC"
            BREW_URL="https://mirrors.ustc.edu.cn/brew.git"
            CORE_URL="https://mirrors.ustc.edu.cn/homebrew-core.git"
            API_URL="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            BOTTLE_URL="https://mirrors.ustc.edu.cn/homebrew-bottles"
            ;;
        *)
            printr "未知镜像: ${MIRROR}（可选 tuna/ustc）"
            exit 1
            ;;
    esac
}

# [1/7] 系统检测
check_os() {
    if [[ "$(uname)" != "Darwin" ]]; then
        printr "仅支持 macOS"
        exit 1
    fi
    printg "✅ 系统检测通过（macOS）"
}

# [2/7] Xcode 命令行工具
ensure_xcode_clt() {
    if xcode-select -p >/dev/null 2>&1; then
        printg "✅ Xcode 命令行工具已安装"
        return 0
    fi
    printy "❌ Xcode 命令行工具未安装"
    echo "请执行以下命令安装（会弹出图形安装窗口）："
    echo "  xcode-select --install"
    echo "安装完成后按回车继续..."
    read -r _ || true
    while ! xcode-select -p >/dev/null 2>&1; do
        if [[ "${SETUP_CN_FAST:-0}" != "1" ]]; then
            sleep 3
        fi
    done
    printg "✅ Xcode 命令行工具已安装"
}

# [3/7] Homebrew 安装（镜像脚本 + 预置镜像变量）
install_homebrew() {
    if find_brew; then
        printg "✅ Homebrew 已安装"
        return 0
    fi
    printy "正在安装 Homebrew（HomebrewCN 中国一键安装脚本）..."
    echo "脚本会询问镜像源选择，请按提示操作（推荐选 1 清华 或 2 中科大）。"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[演练] /bin/zsh -c \"\$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)\""
        return 0
    fi
    /bin/zsh -c "$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)"
    local rc=$?
    if [[ $rc -ne 0 ]] || ! find_brew; then
        printr "❌ Homebrew 安装失败，请手动安装："
        echo "  /bin/zsh -c \"\$(curl -fsSL https://gitee.com/cunkai/HomebrewCN/raw/master/Homebrew.sh)\""
        exit 1
    fi
    printg "✅ Homebrew 安装完成"
}

# 追加一行到 zshrc（幂等）
append_zshrc() {
    if ! grep -qF "$1" "$ZSHRC" 2>/dev/null; then
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "[演练] 追加到 ~/.zshrc: $1"
        else
            echo "$1" >> "$ZSHRC"
        fi
    fi
}

# [4/7] 镜像配置（zshrc 幂等 + brew remote 切换）
set_mirrors() {
    if [[ -n "${HOMEBREW_BOTTLE_DOMAIN:-}" && "$HOMEBREW_BOTTLE_DOMAIN" != "$BOTTLE_URL" ]]; then
        printy "检测到已配置 HOMEBREW_BOTTLE_DOMAIN=${HOMEBREW_BOTTLE_DOMAIN}，跳过镜像覆盖"
        return 0
    fi
    append_zshrc "export HOMEBREW_API_DOMAIN=$API_URL"
    append_zshrc "export HOMEBREW_BOTTLE_DOMAIN=$BOTTLE_URL"
    append_zshrc "export HOMEBREW_NO_AUTO_UPDATE=1"
    if find_brew; then
        run git -C "$("$BREW" --prefix)/Homebrew" remote set-url origin "$BREW_URL"
        if [[ -d "$("$BREW" --prefix)/Library/Taps/homebrew/homebrew-core/.git" ]]; then
            run git -C "$("$BREW" --prefix)/Library/Taps/homebrew/homebrew-core" remote set-url origin "$CORE_URL"
        fi
    fi
    export HOMEBREW_API_DOMAIN="$API_URL"
    export HOMEBREW_BOTTLE_DOMAIN="$BOTTLE_URL"
    export HOMEBREW_NO_AUTO_UPDATE=1
    printg "✅ 镜像配置完成（${MIRROR_NAME}）"
}

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
    local current
    if [[ -n "${PIP_INDEX_URL_USER:-}" && "$PIP_INDEX_URL_USER" != "$PIP_INDEX_URL" ]]; then
        printy "检测到已配置 pip 源=${PIP_INDEX_URL_USER}，跳过覆盖"
        return 0
    fi
    current=$(pip3 config get global.index-url 2>/dev/null)
    if [[ -n "$current" && "$current" != "$PIP_INDEX_URL" ]]; then
        printy "检测到已配置 pip 源=${current}，跳过覆盖"
        return 0
    fi
    if [[ "$current" == "$PIP_INDEX_URL" ]]; then
        printg "✅ pip3 已使用清华源"
    else
        run pip3 config set global.index-url "$PIP_INDEX_URL"
        printg "✅ pip3 清华源配置完成"
    fi
}

# [7/7] 依赖安装（已装跳过，单个失败不中断）
install_deps() {
    local dep failed=0
    if ! find_brew; then
        printr "未检测到 Homebrew，跳过依赖安装"
        return 1
    fi
    for dep in "${DEPS[@]}"; do
        if "$BREW" list "$dep" >/dev/null 2>&1; then
            printg "✅ ${dep} 已安装"
            continue
        fi
        printy "正在安装 ${dep} ..."
        if run "$BREW" install "$dep"; then
            printg "✅ ${dep} 安装完成"
        else
            printr "❌ ${dep} 安装失败（可稍后重试：brew install ${dep}）"
            failed=1
        fi
    done
    return $failed
}

# 摘要
print_summary() {
    echo ""
    echo "=== 安装摘要 ==="
    if [[ $DRY_RUN -eq 1 ]]; then
        printy "（演练模式，未执行任何实际操作）"
        return 0
    fi
    if ! find_brew; then
        printr "Homebrew 未就绪"
        return 1
    fi
    local dep all_ok=1
    for dep in "${DEPS[@]}"; do
        if "$BREW" list "$dep" >/dev/null 2>&1; then
            printg "✅ ${dep}"
        else
            printr "❌ ${dep}（未安装）"
            all_ok=0
        fi
    done
    echo ""
    if [[ $all_ok -eq 1 ]]; then
        printg "全部依赖就绪！现在可以运行 ./surrealra1n.sh"
        return 0
    fi
    printr "存在未安装的依赖，请根据上面的提示重试。"
    return 1
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mirror)
                if [[ $# -lt 2 ]]; then
                    printr "缺少参数: --mirror <tuna|ustc>"
                    usage
                    exit 1
                fi
                MIRROR="$2"
                shift 2 ;;
            --proxy)
                if [[ $# -lt 2 ]]; then
                    printr "缺少参数: --proxy <前缀>"
                    usage
                    exit 1
                fi
                GH_PROXY="$2"
                shift 2 ;;
            --no-proxy) NO_PROXY=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) printr "未知参数: $1"; usage; exit 1 ;;
        esac
    done
    set_mirror_vars
    echo "=== surrealra1n 依赖安装（${MIRROR_NAME} 镜像）==="
    check_os
    ensure_xcode_clt
    install_homebrew
    set_mirrors
    set_github_proxy
    set_pip_mirror
    install_deps
    print_summary
}

main "$@"
