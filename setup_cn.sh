#!/bin/bash
# setup_cn.sh - 国内镜像一键安装 surrealra1n 依赖（仅 macOS + Homebrew）
# 用法:
#   ./setup_cn.sh               默认清华 TUNA 镜像
#   ./setup_cn.sh --mirror ustc 切换中科大 USTC
#   ./setup_cn.sh --dry-run     只打印将执行的操作（演练）
#   ./setup_cn.sh --help        帮助
#
# 环境变量（测试/高级用）:
#   SETUP_CN_ZSHRC   ~/.zshrc 路径覆盖
#   SETUP_CN_FAST=1  跳过等待循环的 sleep

set -u

MIRROR="tuna"
DRY_RUN=0
DEPS=(libimobiledevice libirecovery libusb binutils jq aria2)
ZSHRC="${SETUP_CN_ZSHRC:-$HOME/.zshrc}"
BREW=""

MIRROR_NAME="" BREW_URL="" CORE_URL="" INSTALL_URL="" API_URL="" BOTTLE_URL=""

trap 'echo ""; echo "已取消"; exit 130' INT

printg() { printf "\e[32m%s\e[m\n" "$1"; }
printy() { printf "\e[33;1m%s\e[m\n" "$1"; }
printr() { printf "\e[31;1m%s\e[m\n" "$1"; }

usage() {
    echo "用法: ./setup_cn.sh [--mirror tuna|ustc] [--dry-run] [--help]"
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
            INSTALL_URL="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/install.sh"
            API_URL="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
            BOTTLE_URL="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            ;;
        ustc)
            MIRROR_NAME="中科大 USTC"
            BREW_URL="https://mirrors.ustc.edu.cn/brew.git"
            CORE_URL="https://mirrors.ustc.edu.cn/homebrew-core.git"
            INSTALL_URL="https://mirrors.ustc.edu.cn/brew/install.sh"
            API_URL="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            BOTTLE_URL="https://mirrors.ustc.edu.cn/homebrew-bottles"
            ;;
        *)
            printr "未知镜像: ${MIRROR}（可选 tuna/ustc）"
            exit 1
            ;;
    esac
}

# [1/5] 系统检测
check_os() {
    if [[ "$(uname)" != "Darwin" ]]; then
        printr "仅支持 macOS"
        exit 1
    fi
    printg "✅ 系统检测通过（macOS）"
}

# [2/5] Xcode 命令行工具
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

# [3/5] Homebrew 安装（镜像脚本 + 预置镜像变量）
install_homebrew() {
    if find_brew; then
        printg "✅ Homebrew 已安装"
        return 0
    fi
    printy "正在安装 Homebrew（${MIRROR_NAME} 镜像）..."
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[演练] curl -fsSL ${INSTALL_URL} | NONINTERACTIVE=1 bash"
        echo "[演练] 安装完成后自动配置镜像源"
        return 0
    fi
    export HOMEBREW_API_DOMAIN="$API_URL"
    export HOMEBREW_BOTTLE_DOMAIN="$BOTTLE_URL"
    export HOMEBREW_BREW_GIT_REMOTE="$BREW_URL"
    export HOMEBREW_CORE_GIT_REMOTE="$CORE_URL"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$INSTALL_URL")"
    local rc=$?
    if [[ $rc -ne 0 ]] || ! find_brew; then
        printr "❌ Homebrew 安装失败，请手动安装："
        echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
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

# [4/5] 镜像配置（zshrc 幂等 + brew remote 切换）
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

# [5/5] 依赖安装（已装跳过，单个失败不中断）
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
    install_deps
    print_summary
}

main "$@"
