#!/bin/bash
CURRENT_VERSION="v2.1 beta"

# GitHub download acceleration: when GITHUB_PROXY is non-empty, any download URL
# that points at https://github.com/ is prefixed with it (e.g. https://ghfast.top/).
GITHUB_PROXY="${GITHUB_PROXY:-}"

# Skip the startup update check. Offline-first: defaults to 1 (skip, no GitHub
# contact, never prompted). Set to 0 to enable the check:
#   SKIP_UPDATE_CHECK=0 ./surrealra1n.sh
SKIP_UPDATE_CHECK="${SKIP_UPDATE_CHECK:-1}"

if [ "$EUID" -eq 0 ]; then
  echo "错误：请勿使用 sudo 或以 root 身份运行此脚本。"
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

clear

IPSW_PATH=""
IPSW_PATH_LATEST=""
SHSH_PATH=""
dfu_instructions=""
restorefiles_remake=""
VERSION=""
BUILD=""
VERSION_LATEST=""
outdated=""

set -euo pipefail

error_handler() {
    local exit_code=$?
    local failed_command="${BASH_COMMAND:-unknown}"
    local line_number="${BASH_LINENO[0]:-unknown}"
    local script_file="${BASH_SOURCE[1]:-$0}"
    # Strip escape sequences from failed command to prevent terminal corruption
    failed_command=$(printf '%s' "$failed_command" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\r' | head -c 512)

    {
        echo "[!] surrealra1n 因出现问题而崩溃"
        echo "[!] 退出码：$exit_code"
        echo "[!] 脚本：$script_file"
        echo "[!] 行号：$line_number"
        echo "[!] 失败的命令：$failed_command"
        echo
        echo "[!] 建议在此处报告此问题："
        echo "https://github.com/pwnerblu/surrealra1n/issues"
        echo "以下是推荐的报告方式："
        echo "标题应为你要报告的问题的简明清晰的摘要"
        echo "问题描述应尽可能提及所有相关细节，并附上完整的终端日志。"
        echo "[!] 那些不包含正当日志、细节或任何相关信息的 issue 将被关闭并视为无效。"
        echo 
        echo "[!] 要将此日志附加到你的 issue，请执行以下操作："
        if [[ "${dist:-0}" == 3 || "${dist:-0}" == 4 ]]; then
            echo "Cmd + A -> Cmd + C，然后将整个日志粘贴到你打开的 issue 中"
        else
            echo "Ctrl + Shift + A -> Ctrl + Shift + C，然后将整个日志粘贴到你打开的 issue 中"
        fi
    } 2>/dev/null || true

    exit "$exit_code"
}

trap 'error_handler $LINENO' ERR
# 退出时恢复被暂停的 macOS 设备识别代理，否则 Finder/iTunes 将无法识别任何 iOS 设备
trap 'killall -CONT AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater 2>/dev/null || true' EXIT

# Download a file with retry and validate it's not an HTML error page
# Usage: download_with_retry <url> <output_path> [min_size_bytes]
# If GITHUB_PROXY is set and the URL points at github.com, the proxy prefix is prepended.
download_with_retry() {
    local url="$1"
    local output="$2"
    local min_size="${3:-1024}"
    local max_attempts=3
    local attempt=1
    if [[ -n "${GITHUB_PROXY:-}" && "$url" == https://github.com/* ]]; then
        url="${GITHUB_PROXY}${url}"
    fi
    local part="${output}.part"
    while [[ $attempt -le $max_attempts ]]; do
        set +e
        curl -L -f -C - -o "$part" "$url" 2>/dev/null
        local curl_exit=$?
        set -e
        if [[ $curl_exit -eq 0 ]] && [[ -f "$part" ]]; then
            local file_size
            file_size=$(wc -c < "$part" | tr -d ' ')
            if [[ $file_size -ge $min_size ]]; then
                # Check if file is HTML (GitHub error page)
                if file "$part" 2>/dev/null | grep -qi "text\|html\|ascii"; then
                    local head_bytes
                    head_bytes=$(head -c 64 "$part" 2>/dev/null)
                    if echo "$head_bytes" | grep -qi "<!doctype\|<html\|<head"; then
                        echo "[!] 警告：$output 似乎是一个 HTML 页面，正在重试...（第 $attempt/$max_attempts 次）"
                        rm -f "$part"
                        attempt=$((attempt + 1))
                        sleep 2
                        continue
                    fi
                fi
                mv -f "$part" "$output"
                return 0
            else
                echo "[!] 警告：$output 太小（${file_size} 字节，最小 ${min_size}），正在重试...（第 $attempt/$max_attempts 次）"
                rm -f "$part"
            fi
        else
            echo "[!] 警告：下载 $output 失败（curl 退出码 ${curl_exit}），正在重试...（第 $attempt/$max_attempts 次）"
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    rm -f "$part"
    echo "[!] 错误：$max_attempts 次尝试后仍无法下载 $output"
    return 0
}

echo "你的 surrealra1n 版本：$CURRENT_VERSION"
# Request sudo password upfront
echo "在提示时输入你的用户密码"
sudo -v || exit 1

sudo rm -rf "tmp"
sudo rm -rf "tmp1"
sudo rm -rf "tmp2"
sudo rm -rf "work"
sudo rm -rf "tarwork"

dist=0

JAILBREAK=0

DISTRO="Unsupported"
ARCH="$(uname -m)"

# macOS detection
if [[ "$(uname)" == "Darwin" ]]; then
    DISTRO="macOS"
    if [[ "$ARCH" == "arm64" ]]; then
        echo "你正在 Apple Silicon Mac 上运行 surrealra1n。"
        dist=3
        echo
    elif [[ "$ARCH" == "x86_64" ]]; then
        echo "你正在 Intel macOS 上运行 surrealra1n。"
        dist=4
        echo
    fi
# Linux detection
elif [[ -r /etc/os-release ]]; then
    . /etc/os-release

    if [[ "$ID" == "arch" || "${ID_LIKE:-}" == *arch* ]]; then
        DISTRO="Arch"
        dist=2
    elif [[ "$ID" == "debian" || "${ID_LIKE:-}" == *debian* ]]; then
        DISTRO="Debian"
        dist=1
        read -n 1 -s -r -p "按任意键继续"
    elif [[ "$ID" == "fedora" || "${ID_LIKE:-}" == *fedora* || "${ID_LIKE:-}" == *rhel* ]]; then
        DISTRO="Fedora"
        dist=5
        read -n 1 -s -r -p "按任意键继续"
    # generic Linux fallback
    elif command -v apt-get &>/dev/null; then
        DISTRO="Debian"
        dist=1
        echo "无法识别的发行版；按基于 Debian 处理（检测到 apt-get）。"
        read -n 1 -s -r -p "按任意键继续"
    elif command -v pacman &>/dev/null; then
        DISTRO="Arch"
        dist=2
        echo "无法识别的发行版；按基于 Arch 处理（检测到 pacman）。"
    elif command -v dnf &>/dev/null; then
        DISTRO="Fedora"
        dist=5
        echo "无法识别的发行版；按基于 Fedora 处理（检测到 dnf）。"
        read -n 1 -s -r -p "按任意键继续"
    elif command -v zypper &>/dev/null; then
        DISTRO="Fedora"
        dist=5
        echo "无法识别的发行版；按 Fedora 系处理（检测到 zypper，使用 dnf 流程）。"
        read -n 1 -s -r -p "按任意键继续"
    fi
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    # prevent finder from annoying you
    killall -STOP AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater 2>/dev/null || true
fi

# Run macOS version check only if you're on macOS, should fix Linux
if [[ $dist == 3 || $dist == 4 ]]; then
    macmodel=$(sysctl -n hw.model) 

    # Outdated macOS ver check
    macos_ver=$(sw_vers -productVersion) 
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    if [[ "$(printf '%s\n' "11.0" "$macos_ver" | sort -V | head -n1)" == "11.0" ]]; then
        echo "你的 macOS 版本 $macos_ver 受支持。"
    else
        echo "surrealra1n 仅支持 macOS 11 及更高版本。"
        exit 1
    fi
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    # Check for Xcode Command Line Tools
    if ! xcode-select -p &>/dev/null; then
        echo "未安装 Xcode 命令行工具。正在安装..."
        xcode-select --install
        echo "安装完成后请重新运行 surrealra1n。"
        exit 1
    else
        echo "已安装 Xcode 命令行工具。"
    fi

    # Check for Homebrew
    if ! command -v brew &>/dev/null; then
        echo "[!] 未安装 Homebrew。你需要从 https://brew.sh 安装 Homebrew"
        exit 1
    else
        echo "已安装 Homebrew。"
    fi

    # Check for missing brew dependencies
    BREW_DEPS=("libimobiledevice" "libirecovery" "binutils" "libusb" "jq" "aria2")
    for dep in "${BREW_DEPS[@]}"; do
        if ! brew list "$dep" &>/dev/null; then
            echo "[$dep] 未安装。正在安装..."
            brew install "$dep"
        else
            echo "[$dep] 已安装。"
        fi
    done
fi

# Check for Rosetta 2 (Apple Silicon only)
if [[ $dist == 3 ]]; then
    if ! /usr/bin/pgrep -q oahd; then
        echo "未安装 Rosetta 2。正在安装..."
        softwareupdate --install-rosetta --agree-to-license
    else
        echo "已安装 Rosetta 2。"
    fi
fi

# Unsupported check
if [[ "$DISTRO" == "Unsupported" ]]; then
    echo "不支持的 Linux 发行版。"
    echo "无法检测到兼容的包管理器（apt-get、pacman、dnf 或 zypper）。"
    echo "此脚本仅支持基于 Debian、Arch、Fedora 的系统以及 macOS。"
    exit 1
fi

echo "检测到系统发行版：$DISTRO"

if [[ $dist == 3 || $dist == 4 ]]; then
    zenity="./bin/zenity"
else
    zenity="zenity"
fi

pick_file() {
    local p
    p=$($zenity --file-selection --title="$1" 2>/tmp/zenity_err.txt) || true
    while true; do
        if [[ -z "$p" ]]; then
            if [[ -s /tmp/zenity_err.txt ]]; then
                echo "    [提示] 文件选择窗口未能打开：$(head -n 1 /tmp/zenity_err.txt)"
            fi
            read -e -r -p "$1 - 请输入固件完整路径（把文件拖进本窗口可自动填入，留空取消）：" p </dev/tty
        fi
        [[ -z "$p" ]] && break
        if [[ -f "$p" ]]; then
            break
        fi
        echo "    文件不存在：$p —— 请粘贴 .ipsw 文件的完整路径（可拖文件进窗口），留空取消"
        p=""
    done
    echo "$p"
}

# 离线替补方案：获取 blobs 时 tsschecker 需联网下载 firmwares.json，国内用户普遍无法访问 api.ipsw.me。
# 若检测到离线文件（脚本目录或桌面），等待 5 秒后直接替换 /tmp/firmwares.json，tsschecker 将直接读取该缓存，不再联网。
ensure_firmwares_json(){
    local offline_json=""
    local p
    for p in "$SCRIPT_DIR/firmwares.json" "$HOME/Desktop/firmwares.json"; do
        if [[ -s "$p" ]] && [[ "$(wc -c < "$p" | tr -d ' ')" -gt 100000 ]]; then
            offline_json="$p"
            break
        fi
    done
    if [[ -n "$offline_json" ]]; then
        echo "检测到离线 firmwares.json：$offline_json"
        echo "5 秒后用它替换 /tmp/firmwares.json（跳过联网下载）"
        sleep 5
        sudo cp -f "$offline_json" /tmp/firmwares.json
        echo "已替换，tsschecker 将直接使用本地缓存"
    fi
}


# Dependency check
echo "正在检查所需依赖..."

if [[ $dist == 1 ]]; then
    DEPENDENCIES=(libusb-1.0-0-dev libusbmuxd-tools libimobiledevice-utils usbmuxd zenity git curl make gcc python3-pip python3-usb jq bc aria2)
    MISSING_PACKAGES=()

    for pkg in "${DEPENDENCIES[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        echo "检测到缺少软件包：${MISSING_PACKAGES[*]}"
        echo "正在安装缺失的依赖..."
        sudo apt update || true # issue workarounds
        sudo apt install -y "${MISSING_PACKAGES[@]}" || true # issue workarounds
    else
        echo "所有依赖均已安装。" 
    fi
elif [[ $dist == 2 ]]; then
    DEPENDENCIES=(libusb libusbmuxd libimobiledevice usbmuxd zenity git curl make gcc base-devel python-pip jq bc aria2)
    MISSING_PACKAGES=()


    for pkg in "${DEPENDENCIES[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        echo "检测到缺少软件包：${MISSING_PACKAGES[*]}"
        echo "正在安装缺失的依赖..."
        sudo pacman -Syu --needed "${MISSING_PACKAGES[@]}"
    else
        echo "所有依赖均已安装。"
    fi
elif [[ $dist == 5 ]]; then
    DEPENDENCIES=(libusb1-devel usbmuxd libimobiledevice-utils zenity git curl make gcc python3-pip python3-pyusb jq bc aria2)
    MISSING_PACKAGES=()

    for pkg in "${DEPENDENCIES[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        echo "检测到缺少软件包：${MISSING_PACKAGES[*]}"
        echo "正在安装缺失的依赖..."
        sudo dnf install -y "${MISSING_PACKAGES[@]}"
    else
        echo "所有依赖均已安装。"
    fi
elif [[ "$DISTRO" == "unknown" ]]; then
    echo "不支持的 Linux 发行版。"
    echo "此脚本仅支持基于 Debian、Arch、Fedora 的系统以及 macOS。"
    exit 1
fi

#
stat_size() {
    if stat -c %s "$1" >/dev/null 2>&1; then
        stat -c %s "$1"     # Linux (GNU)
    else
        stat -f %z "$1"     # macOS / BSD
    fi
}

find_dmg() {
    dir="$1"          # directory to search
    mode="$2"         # smallest | largest
    max_size="${3:-}"     # optional (bytes)

    find "$dir" -type f -name '*.dmg' ! -name '._*' -print |
    while IFS= read -r f; do
        size=$(stat_size "$f") || continue
        if [[ -n "$max_size" && "$size" -ge "$max_size" ]]; then
            continue
        fi
        printf '%s %s\n' "$size" "$f"
    done |
    if [[ "$mode" == "smallest" ]]; then
        sort -n
    else
        sort -nr
    fi |
    head -n 1 |
    cut -d' ' -f2-
}

find_dmg_arm64e() {
    dir="$1"          # directory to search
    mode="$2"         # smallest | largest
    max_size="${3:-}"     # optional (bytes)

    find "$dir" -type f -name '*.dmg*' ! -name '._*' -print |
    while IFS= read -r f; do
        size=$(stat_size "$f") || continue
        if [[ -n "$max_size" && "$size" -ge "$max_size" ]]; then
            continue
        fi
        printf '%s %s\n' "$size" "$f"
    done |
    if [[ "$mode" == "smallest" ]]; then
        sort -n
    else
        sort -nr
    fi |
    head -n 1 |
    cut -d' ' -f2-
}

# boot file error handling improvements

require_file() {
    if [[ ! -f "$1" ]]; then
        echo "[!] 缺少所需文件：$1"
        exit 1
    fi
}

require_dir() {
    if [[ ! -d "$1" ]]; then
        echo "[!] 缺少所需目录：$1"
        exit 1
    fi
}

# 计算文件哈希：优先 GNU 工具，回退 macOS 自带工具（都不可用时输出为空）
hash_file() {
    local algo="$1" file="$2"
    case "$algo" in
        md5)
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$file" | awk '{print $1}'
            elif command -v md5 >/dev/null 2>&1; then
                md5 -q "$file"
            fi
            ;;
        sha1)
            if command -v sha1sum >/dev/null 2>&1; then
                sha1sum "$file" | awk '{print $1}'
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 1 "$file" | awk '{print $1}'
            fi
            ;;
    esac
}

verify_checksum() {
    local file_path=$1
    local md5_expected=$2
    local sha1_expected=$3
    local local_hash

    if [ -n "$md5_expected" ] && [ "$md5_expected" != "null" ]; then
        local_hash=$(hash_file md5 "$file_path") || true
        if [ -n "$local_hash" ]; then
            echo "正在验证 MD5 校验和..."
            if [ "$local_hash" = "$md5_expected" ]; then
                echo "MD5 校验和验证成功！"
                return 0
            fi
            echo "错误：MD5 校验和不匹配！" >&2
            echo "期望值：$md5_expected" >&2
            echo "实际值：$local_hash" >&2
            return 1
        fi
        echo "未找到 MD5 工具（md5sum/md5），尝试 SHA1..." >&2
    fi

    if [ -n "$sha1_expected" ] && [ "$sha1_expected" != "null" ]; then
        local_hash=$(hash_file sha1 "$file_path") || true
        if [ -n "$local_hash" ]; then
            echo "正在验证 SHA1 校验和..."
            if [ "$local_hash" = "$sha1_expected" ]; then
                echo "SHA1 校验和验证成功！"
                return 0
            fi
            echo "错误：SHA1 校验和不匹配！" >&2
            echo "期望值：$sha1_expected" >&2
            echo "实际值：$local_hash" >&2
            return 1
        fi
        echo "未找到 SHA1 工具（sha1sum/shasum），跳过校验" >&2
    fi

    echo "警告：没有可用于验证的有效校验和" >&2
    return 0
}

# 下载文件：优先 aria2c（显式指定系统 CA，规避 openssl CA 缺失），失败回退 curl 断点续传
download_file() {
    local url="$1" out="$2"
    local aria2_ca=""
    if [[ -f /etc/ssl/cert.pem ]]; then
        aria2_ca="--ca-certificate=/etc/ssl/cert.pem"
    fi
    if command -v aria2c >/dev/null 2>&1; then
        echo "使用 aria2c 以 16 个连接加速下载..."
        if aria2c -x 16 -s 16 $aria2_ca -o "$out" "$url"; then
            return 0
        fi
        echo "aria2c 下载失败，改用 curl 断点续传..." >&2
    else
        echo "未找到 aria2c，改用 curl..."
    fi
    if curl -L -C - -o "$out" "$url"; then
        return 0
    fi
    echo "错误：下载失败（aria2c 与 curl 均失败）" >&2
    return 1
}

fetch_firmware() {
    if [[ $1 == "18A5342e" ]] && [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* || $IDENTIFIER == iPhone10* ]]; then
        local json_url="https://remedgit.github.io/files/14b4.json"
        local json
        local url
        json=$(curl -s -H 'Accept: application/json' "$json_url") || {
            echo "错误：从 $json_url 获取数据失败" >&2
            return 1
        }
        if ! echo "$json" | jq empty 2>/dev/null; then
            echo "错误：无效的 JSON 数据" >&2
            return 1
        fi
        url=$(echo "$json" | jq -r --arg dev "$IDENTIFIER" '.[] | select(.devices | index($dev)) | .url' | head -1)
        if [ -z "$url" ] || [ "$url" = "null" ]; then
            echo "错误：未找到设备 '$IDENTIFIER' 的固件" >&2
            return 1
        fi

        mkdir -p firmware_downloads/$IDENTIFIER
        IPSW_PATH="firmware_downloads/$IDENTIFIER/18A5342e.ipsw"
        FETCHED_IPSW_FILE="$IPSW_PATH"

        if [ -f "$IPSW_PATH" ]; then
            echo "IPSW 文件已存在于 $IPSW_PATH"
            echo "跳过下载..."
            rm -rf work/BuildManifest.plist
            unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
            BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
            VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
            return 0
        fi

        echo "正在下载固件..."
        echo "来源：$url"
        echo "正在下载到 $IPSW_PATH"

        download_file "$url" "$IPSW_PATH" || {
            echo "错误：下载失败" >&2
            return 1
        }

        echo "下载完成。"
        rm -rf work/BuildManifest.plist
        unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
        BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
        VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
        return 0
    fi
    
    local version_request="$1"
    local api_url="https://api.ipsw.me/v4/ipsw/device/$IDENTIFIER"
    local json
    local filter
    local url md5 identifier2 version2 buildid filesize sha256 sha1 is_signed
    json=$(curl -s -H 'accept: application/json' "$api_url")
    if [ -z "$json" ]; then
        echo "错误：API 返回了空内容" >&2
        return 1
    fi
    if ! echo "$json" | jq empty 2>/dev/null; then
        echo "错误：API 返回了无效的 JSON，内容：" >&2
        echo "$json" | head -n 10 >&2
        return 1
    fi
    filter='first(.firmwares[] | select(.version == $v or .buildid == $v))'
    url=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .url")
    md5=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .md5sum")
    identifier2=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .identifier")
    version2=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .version")
    buildid=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .buildid")
    filesize=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .filesize")
    sha256=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .sha256sum")
    sha1=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .sha1sum")
    is_signed=$(echo "$json" | jq -r --arg v "$version_request" "$filter | .signed")

    if [ -z "$version2" ]; then
        echo "错误：未找到固件（标识符：${IDENTIFIER}，输入：${version_request}）。请填版本号（如 14.3）或 build ID（如 18C66）" >&2
        return 1
    fi

    # b to gb（filesize 为空/非数字时不要喂给 bc，bc 报错会因 set -e 中断整个脚本）
    if [[ "$filesize" =~ ^[0-9]+$ ]]; then
        filesize=$(echo "scale=2; $filesize / 1024 / 1024 / 1024" | bc)
    else
        filesize="未知"
    fi

    if [ -z "$url" ] || [ "$url" = "null" ]; then
        echo "错误：未找到固件（标识符：${IDENTIFIER}，输入：${version_request}）" >&2
        return 1
    fi
    
    mkdir -p firmware_downloads/$IDENTIFIER
    local ipsw_file="firmware_downloads/$IDENTIFIER/${version2}.ipsw"
    FETCHED_IPSW_FILE="$ipsw_file"

    # Check if file already exists
    if [ -f "$ipsw_file" ]; then
        echo "IPSW 文件已存在于 $ipsw_file"
        echo "正在验证完整性..."
        if verify_checksum "$ipsw_file" "$md5" "$sha1"; then
            echo "文件完整性验证通过。跳过下载。"
            return 0
        else
            echo "文件完整性检查失败。正在重新下载..."
            rm -f "$ipsw_file"
        fi
    fi
    #if [[ $version2 == $LATEST_VERSION ]]; then
    #    echo "IPSW is latest, redirecting path"
    #    IPSW_PATH_LATEST="firmware_downloads/$IDENTIFIER/$LATEST_VERSION.ipsw"
    #fi

    echo
    echo "信息："
    echo "标识符：$identifier2"
    echo "版本：$version2"
    echo "BuildID：$buildid"
    echo "sha1sum：$sha1"
    echo "md5sum：$md5"
    echo "sha256sum：$sha256"
    echo "文件大小：$filesize GB"
    echo "是否签名：$is_signed"
    echo "URL：$url"

    echo
    read -p "固件详细信息已列在上方。按回车继续下载。"

    echo "正在下载固件..."
    echo "来源：$url"
    echo "正在下载到 $ipsw_file"

    download_file "$url" "$ipsw_file" || {
        echo "错误：下载失败" >&2
        return 1
    }

    echo "下载完成。"
    
    if ! verify_checksum "$ipsw_file" "$md5" "$sha1"; then
        rm -f "$ipsw_file"
        return 1
    fi

    echo "文件已保存到：$ipsw_file"
    return 0
}

ipsw_selector(){
    echo "请选择获取 $1 IPSW 的方式。"
    echo "1. 选择一个 IPSW 文件"
    echo "2. 在线下载 IPSW 文件"
    echo "3. 退出"
    read -p "请输入选项（1-3）：" fw_select_opts
    fw_select_opts="${fw_select_opts//[$'\r']/}"
    if [[ $fw_select_opts == 1 ]]; then
        if [[ $1 == "target" ]]; then
            IPSW_PATH=$(pick_file "选择一个 IPSW 文件")
            if [[ -z "$IPSW_PATH" ]]; then
                echo "未选择 IPSW。中止。"
                exit 1
            fi
            rm -rf work/BuildManifest.plist
            unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
            BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
            VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
        elif [[ $1 == "base" ]]; then
            IPSW_PATH_LATEST=$(pick_file "选择适用于 iOS $LATEST_VERSION 的 IPSW 文件")
            if [[ -z "$IPSW_PATH_LATEST" ]]; then
                echo "未选择 IPSW。中止。"
                exit 1
            fi
            rm -rf work/BuildManifest.plist
            unzip -j "$IPSW_PATH_LATEST" "BuildManifest.plist" -d work
            VERSION_LATEST=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
            if [[ $VERSION_LATEST != $LATEST_VERSION ]]; then
                echo "IPSW 无效。你必须选择适用于 iOS $LATEST_VERSION 的 IPSW，而不是 iOS $VERSION_LATEST"
                exit 1
            fi
        fi
    elif [[ $fw_select_opts == 2 ]]; then
        if [[ $1 == "target" ]]; then
            if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* || $IDENTIFIER == iPhone10* ]]; then
                echo "如果你想下载 iOS14.0 测试版 4（18A5342e）的 IPSW，请在下方输入 18A5342e"
            fi
            read -p "你想下载哪个版本：" download_version
            fetch_firmware $download_version
            IPSW_PATH="$FETCHED_IPSW_FILE"
            rm -rf work/BuildManifest.plist
            unzip -j "$IPSW_PATH" "BuildManifest.plist" -d work
            BUILD=$(grep -A1 "ProductBuildVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
            VERSION=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
        elif [[ $1 == "base" ]]; then
            fetch_firmware $LATEST_VERSION
            IPSW_PATH_LATEST="$FETCHED_IPSW_FILE"
            rm -rf work/BuildManifest.plist
            unzip -j "$IPSW_PATH_LATEST" "BuildManifest.plist" -d work
            VERSION_LATEST=$(grep -A1 "ProductVersion" work/BuildManifest.plist | grep -o '<string>[^<]*</string>' | head -1 | sed 's/<[^>]*>//g')
        fi
    elif [[ $fw_select_opts == 3 ]]; then
        exit 0
    fi
}

#

if [[ $SKIP_UPDATE_CHECK != 1 ]]; then
    echo "正在检查更新..."
    LATEST_VERSION=""
    RELEASE_NOTES=""
    # 离线优先：下载失败时回退到本地已有的 update/latest.txt（若有）
    local_update_file="update/latest.txt.local"
    if [[ -f update/latest.txt ]]; then
        cp -f update/latest.txt "$local_update_file" 2>/dev/null || true
    fi
    rm -rf update/latest.txt
    if download_with_retry "https://github.com/pwnerblu/surrealra1n/raw/refs/heads/development/update/latest.txt" "update/latest.txt" 128 && [[ -s update/latest.txt ]]; then
        LATEST_VERSION=$(head -n 1 "update/latest.txt" | tr -d '\r\n')
        RELEASE_NOTES=$(awk '/^RELEASE NOTES:/{flag=1; next} flag' "update/latest.txt")
    elif [[ -s "$local_update_file" ]]; then
        echo "[!] 无法联网检查更新，使用本地缓存的更新信息。"
        cp -f "$local_update_file" update/latest.txt 2>/dev/null || true
        LATEST_VERSION=$(head -n 1 "$local_update_file" | tr -d '\r\n')
        RELEASE_NOTES=$(awk '/^RELEASE NOTES:/{flag=1; next} flag' "$local_update_file")
    else
        echo "[!] 无法检查更新（离线或网络问题），已跳过。"
    fi
    rm -f "$local_update_file"

    if [[ -z "$LATEST_VERSION" ]]; then
        echo "surrealra1n 已跳过更新检查。"
        sleep 1
    elif [[ $LATEST_VERSION == $CURRENT_VERSION ]]; then
        echo "surrealra1n 是最新版本。"
        sleep 1
    else
        echo "surrealra1n 有新版本可用：$LATEST_VERSION"
        echo "发布说明："
        echo "$RELEASE_NOTES"
        echo ""
        echo "是否更新？（y/n）："
        read -p "你现在要更新吗？（y/n）：" update
        update="${update//[$'\r']/}"
        if [[ $update == y || $update == Y ]]; then
            rm -rf "updatefiles"
            mkdir updatefiles
            rm -rf "updatefiles/repo"
            git clone --branch development https://github.com/pwnerblu/surrealra1n updatefiles/repo --recursive
            if [[ ! -d updatefiles/repo ]]; then
                echo "克隆仓库失败。"
                exit 1
            fi
            rm -rf "surrealra1n.old"
            mkdir -p surrealra1n.old # make folder to back up old surrealra1n installation
            echo "$CURRENT_VERSION" > surrealra1n.old/oldversion.txt
            echo "正在备份你当前的 surrealra1n 安装..."
            mv -v bin surrealra1n.old/
            mv -v futurerestore surrealra1n.old/
            mv -v keys surrealra1n.old/
            mv -v surrealra1n.sh surrealra1n.old/
            rm -rf "bin"
            rm -rf "futurerestore"
            rm -rf "keys"
            echo "正在复制新文件..."
            cp -av updatefiles/repo/. ./
            chmod +x surrealra1n.sh

            rm -rf "updatefiles"
            echo "surrealra1n 已更新！请重新运行脚本"
            exit 0
        else
            echo "你已拒绝更新，继续使用当前版本。"
        fi
    fi
else
    echo "已跳过更新检查（SKIP_UPDATE_CHECK=1）。"
fi

echo "正在检查现有二进制文件..."

#!/bin/bash

# Check if all required binaries exist
if [[ -f "./bin/img4" && \
      -f "./bin/img4tool" && \
      -f "./bin/irecovery" && \
      -f "./bin/kairos" && \
      -f "./bin/kerneldiff" && \
      -f "./bin/KPlooshFinder" && \
      -f "./bin/gaster" && \
      -f "./bin/Kernel64Patcher" && \
      -f "./bin/Kernel64Patcher2" && \
      -f "./bin/dmg" && \
      -f "./bin/pzb" && \
      -f "./bin/iBoot64Patcher" && \
      -f "./bin/asr64_patcher" && \
      -f "./bin/ipx_restored_patcher" && \
      -f "./bin/restored_external64_patcher" && \
      -f "./bin/restoredpatcher" && \
      -f "./bin/hfsplus" && \
      -f "./bin/tsschecker" && \
      -f "./bin/ipatcher" && \
      -f "./bin/iproxy" && \
      -f "./bin/dtree_patcher" && \
      -f "./bin/sshpass" && \
      -f "./bin/dsc64patcher" && \
      -f "./bin/idevicerestore" && \
      -f "./bin/ldid" && \
      -f "./activate.sh" && \
      -f "./backup.sh" && \
      -f "./futurerestore/futurerestore" ]]; then
    echo "已找到所需二进制文件。"
elif [[ $dist == 3 ]]; then
    echo "二进制文件不存在"
    echo "正在下载二进制文件..."

    mkdir -p bin futurerestore

    curl -L -o bin/img4 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4
    curl -L -o bin/img4tool https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4tool
    curl -L -o bin/pzb https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/pzb
    curl -L -o bin/KPlooshFinder https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/KPlooshFinder
    curl -L -o bin/dsc64patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dsc64patcher
    curl -L -o bin/kerneldiff https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kerneldiff
    curl -L -o bin/dtree_patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dtree_patcher
    curl -L -o bin/irecovery https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/irecovery
    curl -L -o bin/iBoot64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/iBoot64Patcher
    curl -L -o bin/Kernel64Patcher2 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/Kernel64Patcher
    curl -L -o bin/hfsplus https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/hfsplus
    curl -L -o bin/zenity https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/zenity
    # iboot patcher oops
    curl -L -o ibootpatch.c https://gist.githubusercontent.com/pwnerblu/c759c0060b5167a411b3b3adfcd07572/raw/05cd068ca7ec03d20e85103c1a3778634c8cf346/patch.c
    gcc ibootpatch.c -o bin/iBootPatch
    rm -rf ibootpatch.c
    # from spironolactone oops
    curl -L -o bin/trustcache https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/trustcache
    curl -L -o bin/iBoot64Patcher2 https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/iBoot64Patcher_cryptic
    # sshpass
    curl -L -o bin/sshpass https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/sshpass
    curl -L -o bin/iproxy https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iproxy
    curl -L -o bin/dmg https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dmg
    curl -L -o bin/ipatcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iPatcher
    # install additional restored_external patcher (iPhone X only)
    curl -L -o bin/ipx_restored_patcher https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/arm64/ipx_restored_patcher
    # restored patcher for seprmvr64 A8+ restores, my fork of mineek's restored patcher but repurposed
    curl -L -o main.c https://gist.githubusercontent.com/pwnerblu/d2adc5adee74a679704577ddd64508bf/raw/d7b2626fdbf53ef0a2d5bbbbb50c40719315161b/main.c
    gcc main.c -o bin/restoredpatcher
    rm -rf main.c
    # install asr patcher for tethered restores
    git clone https://github.com/iSuns9/asr64_patcher --recursive
    cd asr64_patcher
    make
    mv asr64_patcher ../bin/asr64_patcher
    cd ..
    rm -rf "asr64_patcher"
    # install restored_external patcher for tethered restores to iOS 14+
    git clone https://github.com/iSuns9/restored_external64patcher --recursive
    cd restored_external64patcher
    make
    mv restored_external64_patcher ../bin/restored_external64_patcher
    cd ..
    rm -rf "restored_external64patcher"
    # install libimg4 patcher for tethered restores to iOS 14/15, primarily convert to localboot
    git clone https://github.com/iSuns9/libimg4_patcher --recursive
    cd libimg4_patcher
    make
    mv libimg4_patcher ../bin/libimg4_patcher
    cd ..
    rm -rf "libimg4_patcher"
    # install Kernel64Patcher for tether booting iOS 13+
    curl -L -o bin/Kernel64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/Kernel64Patcher
    # fetch pwnerblu fork of Kernel64Patcher and iBootpatch2 for tether booting iOS 14.x on A12 device.
    if [[ $macos_ver == 12.* || $macos_ver == 13.* || $macos_ver == 14.* || $macos_ver == 15.* || $macos_ver == 26.* || $macos_ver == 27.* ]]; then
        git clone https://github.com/pwnerblu/Kernel64Patcher --recursive -b dev
        cd Kernel64Patcher
        make
        cp Kernel64Patcher ../bin/Kernel64Patcher3
        cd ..
        rm -rf "Kernel64Patcher"
        git clone https://github.com/pwnerblu/iBootpatch2 -b ipad6
        cd iBootpatch2
        make
        cp iBootpatch2 ../bin/iBootpatch2
        cd ..
        rm -rf "iBootpatch2"
        git clone https://github.com/pwnerblu/iBootpatch2 -b funny
        cd iBootpatch2
        make
        cp iBootpatch2 ../bin/iBootpatch3
        cd ..
        rm -rf "iBootpatch2"
    fi
    # done!
    curl -L -o bin/gaster https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/gaster
    curl -L -o bin/tsschecker https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/tsschecker
    curl -L -o bin/ldid https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_arm64
    curl -L -o bin/kairos https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kairos
    # download activate.sh and backup.sh from hiylx's eclipsera1n, for backing up and restoring iOS 16+ activation files on 14.0-15.7(.2)
    curl -L -o activate.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/activate.sh
    curl -L -o backup.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/backup.sh
    curl -L -o futurerestore/futurerestore.zip https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-macOS-RELEASE-main.zip
    # fetch idevicerestore for 7.0-9.3.5 restores 
    curl -L -o bin/idevicerestore https://github.com/NyanSatan/SundanceInH2A/raw/refs/heads/master/executables/Darwin/idevicerestore
    # libs
    chmod +x bin/*
    chmod +x *.sh

    cd futurerestore || exit
    unzip -o futurerestore.zip
    tar -xf futurerestore-macOS-v2.0.0-Build_329-RELEASE.tar.xz
    cp futurerestore-macOS-v2.0.0-Build_329-RELEASE/* . || true
    chmod +x futurerestore
    rm -rf *.tar.xz
    rm -rf *.sh
    rm -rf *.zip
    rm -rf "futurerestore-macOS-v2.0.0-Build_329-RELEASE" 
    cd ..
    xattr -c bin/*
    xattr -c futurerestore/futurerestore
elif [[ $dist == 4 ]]; then
    echo "二进制文件不存在"
    echo "正在下载二进制文件..."

    mkdir -p bin futurerestore

    curl -L -o bin/img4 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4
    curl -L -o bin/img4tool https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/img4tool
    curl -L -o bin/pzb https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/pzb
    curl -L -o bin/KPlooshFinder https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/KPlooshFinder
    curl -L -o bin/dsc64patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dsc64patcher
    curl -L -o bin/kerneldiff https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kerneldiff
    curl -L -o bin/dtree_patcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dtree_patcher
    curl -L -o bin/irecovery https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/irecovery
    curl -L -o bin/iBoot64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/iBoot64Patcher
    curl -L -o bin/Kernel64Patcher2 https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/Kernel64Patcher
    curl -L -o bin/hfsplus https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/hfsplus
    curl -L -o bin/zenity https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/zenity
    # iboot patcher oops
    curl -L -o ibootpatch.c https://gist.githubusercontent.com/pwnerblu/c759c0060b5167a411b3b3adfcd07572/raw/05cd068ca7ec03d20e85103c1a3778634c8cf346/patch.c
    gcc ibootpatch.c -o bin/iBootPatch
    rm -rf ibootpatch.c
    # from spironolactone oops
    curl -L -o bin/trustcache https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/trustcache
    curl -L -o bin/iBoot64Patcher2 https://github.com/Orangera1n/spironolactone/raw/refs/heads/main/Darwin/iBoot64Patcher_cryptic
    # sshpass
    curl -L -o bin/sshpass https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/sshpass
    curl -L -o bin/iproxy https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iproxy
    curl -L -o bin/dmg https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/dmg
    curl -L -o bin/ipatcher https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/iPatcher
    # install additional restored_external patcher (iPhone X only)
    curl -L -o bin/ipx_restored_patcher https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/ipx_restored_patcher
    # restored patcher for seprmvr64 A8+ restores, my fork of mineek's restored patcher but repurposed
    curl -L -o main.c https://gist.githubusercontent.com/pwnerblu/d2adc5adee74a679704577ddd64508bf/raw/d7b2626fdbf53ef0a2d5bbbbb50c40719315161b/main.c
    gcc main.c -o bin/restoredpatcher
    rm -rf main.c
    # install asr patcher for tethered restores
    git clone https://github.com/iSuns9/asr64_patcher --recursive
    cd asr64_patcher
    make
    mv asr64_patcher ../bin/asr64_patcher
    cd ..
    rm -rf "asr64_patcher"
    # install restored_external patcher for tethered restores to iOS 14+
    git clone https://github.com/iSuns9/restored_external64patcher --recursive
    cd restored_external64patcher
    make
    mv restored_external64_patcher ../bin/restored_external64_patcher
    cd ..
    rm -rf "restored_external64patcher"
    # install libimg4 patcher for tethered restores to iOS 14/15, primarily convert to localboot
    git clone https://github.com/iSuns9/libimg4_patcher --recursive
    cd libimg4_patcher
    make
    mv libimg4_patcher ../bin/libimg4_patcher
    cd ..
    rm -rf "libimg4_patcher"
    # install Kernel64Patcher for tether booting iOS 13+
    curl -L -o bin/Kernel64Patcher https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Darwin/Kernel64Patcher
    # fetch pwnerblu fork of Kernel64Patcher and iBootpatch2 for tether booting iOS 14.x on A12 device.
    if [[ $macos_ver == 12.* || $macos_ver == 13.* || $macos_ver == 14.* || $macos_ver == 15.* || $macos_ver == 26.* || $macos_ver == 27.* ]]; then
        git clone https://github.com/pwnerblu/Kernel64Patcher --recursive -b dev
        cd Kernel64Patcher
        make
        cp Kernel64Patcher ../bin/Kernel64Patcher3
        cd ..
        rm -rf "Kernel64Patcher"
        git clone https://github.com/pwnerblu/iBootpatch2 -b ipad6
        cd iBootpatch2
        make
        cp iBootpatch2 ../bin/iBootpatch2
        cd ..
        rm -rf "iBootpatch2"
        git clone https://github.com/pwnerblu/iBootpatch2 -b funny
        cd iBootpatch2
        make
        cp iBootpatch2 ../bin/iBootpatch3
        cd ..
        rm -rf "iBootpatch2"
    fi
    # done!
    curl -L -o bin/gaster https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/gaster
    curl -L -o bin/tsschecker https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/macos/tsschecker
    curl -L -o bin/ldid https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_macosx_x86_64
    curl -L -o bin/kairos https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Darwin/kairos
    # download activate.sh and backup.sh from hiylx's eclipsera1n, for backing up and restoring iOS 16+ activation files on 14.0-15.7(.2)
    curl -L -o activate.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/activate.sh
    curl -L -o backup.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/backup.sh
    curl -L -o futurerestore/futurerestore.zip https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-macOS-RELEASE-main.zip
    # fetch idevicerestore for 7.0-9.3.5 restores 
    curl -L -o bin/idevicerestore https://github.com/NyanSatan/SundanceInH2A/raw/refs/heads/master/executables/Darwin/idevicerestore
    # libs
    chmod +x bin/*
    chmod +x *.sh

    cd futurerestore || exit
    unzip -o futurerestore.zip
    tar -xf futurerestore-macOS-v2.0.0-Build_329-RELEASE.tar.xz
    cp futurerestore-macOS-v2.0.0-Build_329-RELEASE/* . || true
    chmod +x futurerestore
    rm -rf *.tar.xz
    rm -rf *.sh
    rm -rf *.zip
    rm -rf "futurerestore-macOS-v2.0.0-Build_329-RELEASE" 
    cd ..
    xattr -c bin/*
    xattr -c futurerestore/futurerestore
else
    echo "二进制文件不存在"
    echo "正在下载二进制文件..."

    mkdir -p bin futurerestore

    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/img4" "bin/img4" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/img4tool" "bin/img4tool" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/KPlooshFinder" "bin/KPlooshFinder" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/pzb" "bin/pzb" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/dsc64patcher" "bin/dsc64patcher" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/kerneldiff" "bin/kerneldiff" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/dtree_patcher" "bin/dtree_patcher" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/irecovery" "bin/irecovery" 1024
    download_with_retry "https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Linux/iBoot64Patcher" "bin/iBoot64Patcher" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/Kernel64Patcher" "bin/Kernel64Patcher2" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/hfsplus" "bin/hfsplus" 1024
    # sshpass
    # iboot patcher oops
    curl -L -o ibootpatch.c https://gist.githubusercontent.com/pwnerblu/c759c0060b5167a411b3b3adfcd07572/raw/05cd068ca7ec03d20e85103c1a3778634c8cf346/patch.c
    gcc ibootpatch.c -o bin/iBootPatch
    rm -rf ibootpatch.c
    download_with_retry "https://github.com/CRKatri/trustcache/releases/download/v2.0/trustcache_linux_x86_64" "bin/trustcache" 1024
    # fetch pwnerblu fork of Kernel64Patcher and iBootpatch2 for tether booting iOS 14.x on A12 device.
    git clone https://github.com/pwnerblu/Kernel64Patcher --recursive -b dev
    cd Kernel64Patcher
    make
    cp Kernel64Patcher ../bin/Kernel64Patcher3
    cd ..
    rm -rf "Kernel64Patcher"
    git clone https://github.com/pwnerblu/iBootpatch2 -b ipad6
    cd iBootpatch2
    make
    cp iBootpatch2 ../bin/iBootpatch2
    cd ..
    rm -rf "iBootpatch2"
    download_with_retry "https://github.com/appleiPodTouch4/spironolactone/raw/refs/heads/main/Linux/x86_64/iBoot64patcher_cryptic" "bin/iBoot64Patcher2" 1024
    download_with_retry "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/sshpass" "bin/sshpass" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/iproxy" "bin/iproxy" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/dmg" "bin/dmg" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/ipatcher" "bin/ipatcher" 1024
    # install additional restored_external patcher (iPhone X only)
    download_with_retry "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/ipx_restored_patcher" "bin/ipx_restored_patcher" 1024
    # restored patcher for seprmvr64 A8+ restores, my fork of mineek's restored patcher but repurposed
    curl -L -o main.c https://gist.githubusercontent.com/pwnerblu/d2adc5adee74a679704577ddd64508bf/raw/d7b2626fdbf53ef0a2d5bbbbb50c40719315161b/main.c
    gcc main.c -o bin/restoredpatcher
    rm -rf main.c
    # install asr patcher for tethered restores
    git clone https://github.com/iSuns9/asr64_patcher --recursive
    cd asr64_patcher
    make
    mv asr64_patcher ../bin/asr64_patcher
    cd ..
    rm -rf "asr64_patcher"
    # install restored_external patcher for tethered restores to iOS 14+
    git clone https://github.com/iSuns9/restored_external64patcher --recursive
    cd restored_external64patcher
    make
    mv restored_external64_patcher ../bin/restored_external64_patcher
    cd ..
    rm -rf "restored_external64patcher"
    # install libimg4 patcher for tethered restores to iOS 14/15, primarily convert to localboot
    git clone https://github.com/iSuns9/libimg4_patcher --recursive
    cd libimg4_patcher
    make
    mv libimg4_patcher ../bin/libimg4_patcher
    cd ..
    rm -rf "libimg4_patcher"
    # install Kernel64Patcher for tether booting iOS 13+
    download_with_retry "https://github.com/edwin170/downr1n/raw/refs/heads/main/binaries/Linux/Kernel64Patcher" "bin/Kernel64Patcher" 1024
    download_with_retry "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/gaster" "bin/gaster" 1024
    download_with_retry "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/tsschecker" "bin/tsschecker" 1024
    download_with_retry "https://github.com/ProcursusTeam/ldid/releases/download/v2.1.5-procursus7/ldid_linux_x86_64" "bin/ldid" 1024
    download_with_retry "https://github.com/LukeZGD/Semaphorin/raw/refs/heads/main/Linux/kairos" "bin/kairos" 1024
    # download activate.sh and backup.sh from hiylx's eclipsera1n, for backing up and restoring iOS 16+ activation files on 14.0-15.7(.2)
    curl -L -o activate.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/activate.sh
    curl -L -o backup.sh https://github.com/hiylx/eclipsera1n/raw/refs/heads/main/backup.sh
    download_with_retry "https://github.com/LukeeGD/futurerestore/releases/download/latest/futurerestore-Linux-x86_64-RELEASE-main.zip" "futurerestore/futurerestore.zip" 1024
    # fetch idevicerestore for 7.0-9.3.5 restores 
    download_with_retry "https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/idevicerestore2" "bin/idevicerestore" 1024
    # libs
    rm -rf "lib"
    mkdir lib
    curl -L -o lib/libcrypto.so.35 https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/lib/libcrypto.so.35
    curl -L -o lib/libssl.so.35 https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/bin/linux/x86_64/lib/libssl.so.35
    chmod +x bin/*
    chmod +x *.sh

    cd futurerestore || exit
    unzip -o futurerestore.zip
    tar -xf futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE.tar.xz
    cp futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE/* . || true
    chmod +x linux_fix.sh || true
    sudo ./linux_fix.sh || true
    rm -rf linux_fix.sh || true
    chmod +x futurerestore
    rm -rf *.tar.xz || true
    rm -rf *.sh || true
    rm -rf *.zip || true
    rm -rf "futurerestore-Linux-x86_64-v2.0.0-Build_329-RELEASE" 
    cd ..
fi

echo "正在检查 usbliter8ctl 所需的依赖，假设你的系统已安装 Python3"
# Check required packages
PACKAGES=("pyusb" "usb")
for pkg in "${PACKAGES[@]}"; do
    if pip3 show "$pkg" &>/dev/null; then
        version=$(pip3 show "$pkg" | grep Version | awk '{print $2}')
        echo "${pkg}：$version"
    else
        echo "$pkg 未安装"
        echo "运行：pip3 install $pkg"
        if pip3 install "$pkg" 2>&1 | grep -q "externally-managed"; then
            echo "检测到外部管理环境，使用 --break-system-packages 重试"
            pip3 install "$pkg" --break-system-packages
        fi
    fi
done

IDEVICE_INFO=$(ideviceinfo 2>&1) || true
IDEVICE_STATUS=$?
if [[ $IDEVICE_STATUS -eq 0 && "$IDEVICE_INFO" != *"No device found!"* && "$IDEVICE_INFO" != *"ERROR:"* ]]; then
    IDENTIFIER=$(echo "$IDEVICE_INFO" | grep "^ProductType:" | cut -d ':' -f2 | xargs)
    ECID=$(echo "$IDEVICE_INFO" | grep "^UniqueChipID:" | cut -d ':' -f2 | xargs)
    SERIAL=$(echo "$IDEVICE_INFO" | grep "^SerialNumber:" | cut -d ':' -f2 | xargs)
    DEVICE_VERSION=$(echo "$IDEVICE_INFO" | grep "^ProductVersion:" | cut -d ':' -f2 | xargs)
    MODE="Normal"
elif [[ $IDEVICE_STATUS -ne 0 && "$IDEVICE_INFO" != *"No device found!"* ]] || [[ "$IDEVICE_INFO" == *"ERROR:"* && "$IDEVICE_INFO" != *"No device found!"* ]]; then
    # ideviceinfo ran but failed for another reason, try -s
    IDEVICE_INFO=$(ideviceinfo -s 2>&1) || true
    IDEVICE_STATUS=$?
    if [[ $IDEVICE_STATUS -eq 0 && "$IDEVICE_INFO" != *"No device found!"* ]]; then
        IDENTIFIER=$(echo "$IDEVICE_INFO" | grep "^ProductType:" | cut -d ':' -f2 | xargs)
        ECID=$(echo "$IDEVICE_INFO" | grep "^UniqueChipID:" | cut -d ':' -f2 | xargs)
        DEVICE_VERSION=$(echo "$IDEVICE_INFO" | grep "^ProductVersion:" | cut -d ':' -f2 | xargs)
        SERIAL="none"
        MODE="Normal"
    else
        echo "ideviceinfo 尝试两次后仍失败。"
        exit 1
    fi
else
    echo "[*] 设备不在正常模式。正在尝试恢复/DFU 模式..."
    # Try irecovery
    IRECOVERY_INFO=$(./bin/irecovery -q 2>/dev/null) || true
    if [[ -n "$IRECOVERY_INFO" ]]; then
        echo "[*] 设备处于恢复或 DFU 模式。"
        IDENTIFIER=$(echo "$IRECOVERY_INFO" | grep "^PRODUCT:" | cut -d ':' -f2 | xargs)
        ECID=$(echo "$IRECOVERY_INFO" | grep "^ECID:" | cut -d ':' -f2 | xargs)
        MODE=$(echo "$IRECOVERY_INFO" | grep "^MODE:" | cut -d ':' -f2 | xargs)
        echo "[+] 设备标识符：$IDENTIFIER"
        echo "[+] ECID：$ECID"
    else
        echo "[!] 未在正常或恢复模式下检测到设备。"
        IDENTIFIER="NONE"
        MODE="None"
        ECID="None"
        REFER2=""
        BOARDID2=""
        REFER=""
        BOARDID=""
        NAME="No device"
    fi
fi

if [[ -d "seprmvr64boot" ]]; then
    mkdir -p boot
    mv -v seprmvr64boot/* boot/
    rm -rf "seprmvr64boot"
fi

if [[ $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 ]]; then
    echo "iPad mini 3 尚不受支持"
    exit 1
fi

KEY_FILE="keys/$IDENTIFIER.txt"

# BB update determine check

if [[ $IDENTIFIER == iPhone* || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,5 || $IDENTIFIER == iPad4,6 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPad5,4 || $IDENTIFIER == iPad11,2 || $IDENTIFIER == iPad11,4 ]]; then
    updatebb_flag="--latest-baseband"
elif [[ $IDENTIFIER == iPod* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad11,1 || $IDENTIFIER == iPad11,3 ]]; then
    updatebb_flag="--no-baseband"
fi

# changes to device detection stuff

if [[ $IDENTIFIER == iPhone12* ]]; then
    PMP="t8030pmp.im4p"
fi

if [[ $IDENTIFIER == iPhone6* ]]; then
    REFER="iphone6"
    REFER2="iphone6"
elif [[ $IDENTIFIER == NONE ]]; then
    updatebb_flag="lol"
elif [[ $IDENTIFIER == iPhone7* ]]; then
    REFER="iphone7"
elif [[ $IDENTIFIER == iPod7* ]]; then
    REFER="n102"
    REFER2="n102"
    BOARDID="n102ap"
    BOARDID2="n102"
    NAME="iPod touch 6 ($BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone11,8 ]]; then
    REFER="iphone11b"
    REFER2="n841"
    BOARDID="n841ap"
    BOARDID2="n841"
    NAME="iPhone XR ($BOARDID)"
    AOP14="aopfw-iphone11baop.im4p"
    AOP="aopfw-iphone11baop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-n84.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="N841_CallanFirmware.im4p"
    HAPTICASSET="N841_HapticAssets.im4p"
    MTFW="N841_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11b.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPad11,1 ]]; then
    REFER="ipad11"
    REFER2="j210"
    BOARDID="j210ap"
    BOARDID2="j210"
    NAME="iPad mini (5th generation, Wi-Fi only) ($BOARDID)"
    AOP14="aopfw-ipad11aop.im4p"
    AOP="aopfw-ipad11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-j2x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    MTFW="J210_Multitouch.im4p"
    # ipad wifi version doesn't have callan firmware
    # ipad doesn't hav haptic firmware
    # ipad wifi version doesn't have wirelesspower firmware
    KERNEL2="kernelcache.release.ipad11x"
elif [[ $IDENTIFIER == iPad11,2 ]]; then
    REFER="ipad11"
    REFER2="j210"
    BOARDID="j211ap"
    BOARDID2="j210"
    NAME="iPad mini (5th generation, Cellular) ($BOARDID)"
    AOP14="aopfw-ipad11aop.im4p"
    AOP="aopfw-ipad11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-j2x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    MTFW="J211_Multitouch.im4p"
    # ipad wifi version doesn't have callan firmware
    # ipad doesn't hav haptic firmware
    # ipad wifi version doesn't have wirelesspower firmware
    KERNEL2="kernelcache.release.ipad11x"
elif [[ $IDENTIFIER == iPad11,3 ]]; then
    REFER="ipad11"
    REFER2="j217"
    BOARDID="j217ap"
    BOARDID2="j217"
    NAME="iPad Air (3rd generation, Wi-Fi only) ($BOARDID)"
    AOP14="aopfw-ipad11aop.im4p"
    AOP="aopfw-ipad11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-j2x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    MTFW="J217_Multitouch.im4p"
    # ipad wifi version doesn't have callan firmware
    # ipad doesn't hav haptic firmware
    # ipad wifi version doesn't have wirelesspower firmware
    KERNEL2="kernelcache.release.ipad11x"
elif [[ $IDENTIFIER == iPad11,4 ]]; then
    REFER="ipad11"
    REFER2="j217"
    BOARDID="j218ap"
    BOARDID2="j217"
    NAME="iPad Air (3rd generation, Cellular) ($BOARDID)"
    AOP14="aopfw-ipad11aop.im4p"
    AOP="aopfw-ipad11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-j2x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    MTFW="J218_Multitouch.im4p"
    # ipad wifi version doesn't have callan firmware
    # ipad doesn't hav haptic firmware
    # ipad wifi version doesn't have wirelesspower firmware
    KERNEL2="kernelcache.release.ipad11x"
elif [[ $IDENTIFIER == iPhone11,2 ]]; then
    REFER="iphone11"
    REFER2="d321"
    BOARDID="d321ap"
    BOARDID2="d321"
    NAME="iPhone XS ($BOARDID)"
    AOP14="aopfw-iphone11aop.im4p"
    AOP="aopfw-iphone11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-d3x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="D321_CallanFirmware.im4p"
    HAPTICASSET="D321_HapticAssets.im4p"
    MTFW="D321_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPhone11,4 ]]; then
    REFER="iphone11"
    REFER2="d331"
    BOARDID="d331ap"
    BOARDID2="d331"
    NAME="iPhone XS Max ($BOARDID)"
    AOP14="aopfw-iphone11aop.im4p"
    AOP="aopfw-iphone11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-d3x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="D331_CallanFirmware.im4p"
    HAPTICASSET="D331_HapticAssets.im4p"
    MTFW="D331_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPhone11,6 ]]; then
    REFER="iphone11"
    REFER2="d331p"
    BOARDID="d331pap"
    BOARDID2="d331p"
    NAME="iPhone XS Max ($BOARDID)"
    AOP14="aopfw-iphone11aop.im4p"
    AOP="aopfw-iphone11aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    GFX="armfw_g11p.im4p"
    ISP="adc-petra-d3x.im4p"
    ANE="h11_ane_fw_quin.im4p"
    AVE="AppleAVE2FW_H11.im4p"
    CALLAN="D331p_CallanFirmware.im4p"
    HAPTICASSET="D331p_HapticAssets.im4p"
    MTFW="D331p_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone11.im4p"
    KERNEL2="kernelcache.release.iphone11x"
elif [[ $IDENTIFIER == iPhone12,1 ]]; then
    REFER="iphone12b"
    REFER2="n104"
    BOARDID="n104ap"
    BOARDID2="n104"
    NAME="iPhone 11 ($BOARDID)"
    AOP14="aopfw-iphone12baop.im4p"
    AOP="aopfw-iphone12baop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    IOFW13="SmartIOFirmwareT8030.im4p"
    AVE13="AppleAVE2FW.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-n104.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    CALLAN="N104_AudioCodecFirmware.im4p"
    HAPTICASSET="N104_HapticAssets.im4p"
    MTFW="N104_Multitouch.im4p"
    LEAPHAPTIC="N104_LeapHapticsFirmware.im4p"
    WIRELESS="WirelessPower.iphone12b.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone12,3 ]]; then
    REFER="iphone12"
    REFER2="d421"
    BOARDID="d421ap"
    BOARDID2="d421"
    NAME="iPhone 11 Pro ($BOARDID)"
    AOP14="aopfw-iphone12aop.im4p"
    AOP="aopfw-iphone12aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    IOFW13="SmartIOFirmwareT8030.im4p"
    AVE13="AppleAVE2FW.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-d4x.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    CALLAN="D421_AudioCodecFirmware.im4p"
    HAPTICASSET="D421_HapticAssets.im4p"
    MTFW="D421_Multitouch.im4p"
    LEAPHAPTIC="D421_LeapHapticsFirmware.im4p"
    WIRELESS="WirelessPower.iphone12.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone12,5 ]]; then
    REFER="iphone12"
    REFER2="d431"
    BOARDID="d431ap"
    BOARDID2="d431"
    NAME="iPhone 11 Pro Max ($BOARDID)"
    AOP14="aopfw-iphone12aop.im4p"
    AOP="aopfw-iphone12aop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    IOFW13="SmartIOFirmwareT8030.im4p"
    AVE13="AppleAVE2FW.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-d4x.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    CALLAN="D431_AudioCodecFirmware.im4p"
    HAPTICASSET="D431_HapticAssets.im4p"
    MTFW="D431_Multitouch.im4p"
    LEAPHAPTIC="D431_LeapHapticsFirmware.im4p"
    WIRELESS="WirelessPower.iphone12.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone12,8 ]]; then
    REFER="iphone12c"
    REFER2="d79"
    BOARDID="d79ap"
    BOARDID2="d79"
    NAME="iPhone SE 2nd generation ($BOARDID)"
    AOP14="aopfw-iphone12caop.im4p"
    AOP="aopfw-iphone12caop.RELEASE.im4p"
    IOFW="SmartIOFirmware_ASCv2.im4p"
    IOFW13="SmartIOFirmwareT8030.im4p"
    GFX="armfw_g12p.im4p"
    ISP="adc-zelus-d79.im4p"
    ANE="h12_ane_fw_metis.im4p"
    AVE="AppleAVE2FW_H12.im4p"
    AVE13="AppleAVE2FW.im4p"
    CALLAN="D79_AudioCodecFirmware.im4p"
    MTFW="D79_Multitouch.im4p"
    WIRELESS="WirelessPower.iphone12c.im4p"
    KERNEL2="kernelcache.release.iphone12x"
elif [[ $IDENTIFIER == iPhone10,1 || $IDENTIFIER == iPhone10,4 || $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    REFER="iphone10"
elif [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    REFER="iphone10b"
elif [[ $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 ]]; then
    REFER="ipad4"
    REFER2="ipad4"
elif [[ $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 || $IDENTIFIER == iPad4,6 ]]; then
    REFER="ipad4b"
    REFER2="ipad4b"
elif [[ $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 ]]; then
    REFER="ipad4bm"
    REFER2="ipad4bm"
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]]; then
    REFER="ipad5"
    REFER2="ipad5"
elif [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]]; then
    REFER="ipad5b"
    REFER2="ipad5b"
else
    echo "不支持的设备"
    exit 1
fi

if [[ $IDENTIFIER == iPhone6,1 ]]; then
    BOARDID="n51ap"
    BOARDID2="n51"
    NAME="iPhone 5S (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone6,2 ]]; then
    BOARDID="n53ap"
    BOARDID2="n53"
    NAME="iPhone 5S (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone7,2 ]]; then
    BOARDID="n61ap"
    BOARDID2="n61"
    REFER2="$BOARDID2"
    NAME="iPhone 6 ($BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone7,1 ]]; then
    BOARDID="n56ap"
    BOARDID2="n56"
    REFER2="$BOARDID2"
    NAME="iPhone 6 Plus ($BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,1 ]]; then
    BOARDID="d20ap"
    BOARDID2="d20"
    REFER2="$BOARDID2"
    NAME="iPhone 8 (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,4 ]]; then
    BOARDID="d201ap"
    BOARDID2="d20"
    REFER2="$BOARDID2"
    NAME="iPhone 8 (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,2 ]]; then
    BOARDID="d21ap"
    BOARDID2="d21"
    REFER2="$BOARDID2"
    NAME="iPhone 8 Plus (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,5 ]]; then
    BOARDID="d211ap"
    BOARDID2="d21"
    REFER2="$BOARDID2"
    NAME="iPhone 8 Plus (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,3 ]]; then
    BOARDID="d22ap"
    BOARDID2="d22"
    REFER2="$BOARDID2"
    NAME="iPhone X (Global, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPhone10,6 ]]; then
    BOARDID="d221ap"
    BOARDID2="d22"
    REFER2="$BOARDID2"
    NAME="iPhone X (GSM, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,1 ]]; then
    BOARDID="j71ap"
    BOARDID2="j71"
    NAME="iPad Air (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,2 ]]; then
    BOARDID="j72ap"
    BOARDID2="j72"
    NAME="iPad Air (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,3 ]]; then
    BOARDID="j73ap"
    BOARDID2="j73"
    NAME="iPad Air (China, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,4 ]]; then
    BOARDID="j85ap"
    BOARDID2="j85"
    NAME="iPad mini 2 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,5 ]]; then
    BOARDID="j86ap"
    BOARDID2="j86"
    NAME="iPad mini 2 (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,6 ]]; then
    BOARDID="j87ap"
    BOARDID2="j87"
    NAME="iPad mini 2 (China, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,7 ]]; then
    BOARDID="j85map"
    BOARDID2="j85m"
    NAME="iPad mini 3 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,8 ]]; then
    BOARDID="j86map"
    BOARDID2="j86m"
    NAME="iPad mini 3 (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad4,9 ]]; then
    BOARDID="j87map"
    BOARDID2="j87m"
    NAME="iPad mini 3 (China, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,1 ]]; then
    BOARDID="j96ap"
    BOARDID2="j96"
    NAME="iPad mini 4 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,2 ]]; then
    BOARDID="j97ap"
    BOARDID2="j97"
    NAME="iPad mini 4 (Cellular, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,3 ]]; then
    BOARDID="j81ap"
    BOARDID2="j81"
    NAME="iPad Air 2 (Wi-Fi only, $BOARDID) - $IDENTIFIER"
elif [[ $IDENTIFIER == iPad5,4 ]]; then
    BOARDID="j82ap"
    BOARDID2="j82"
    NAME="iPad Air 2 (Cellular, $BOARDID) - $IDENTIFIER"
fi

if [[ $IDENTIFIER == iPad5* ]]; then
    LATEST_VERSION="15.8.8"
elif [[ $IDENTIFIER == iPhone10* ]]; then
    LATEST_VERSION="16.7.16"
elif [[ $IDENTIFIER == iPhone11* ]]; then
    LATEST_VERSION="18.7.10"
elif [[ $IDENTIFIER == iPhone12* ]]; then
    LATEST_VERSION="27.0"
elif [[ $IDENTIFIER == iPad11* ]]; then
    LATEST_VERSION="26.7"
else
    LATEST_VERSION="12.5.8"
fi

IBSS="iBSS.$REFER2.RELEASE.im4p"
IBEC="iBEC.$REFER2.RELEASE.im4p"
LLB="LLB.$REFER2.RELEASE.im4p"
IBOOT="iBoot.$REFER2.RELEASE.im4p"
LLB10="LLB.$BOARDID2.RELEASE.im4p"
IBOOT10="iBoot.$BOARDID2.RELEASE.im4p"
DEVICETREE="DeviceTree.$BOARDID.im4p"
ALLFLASH="all_flash.$BOARDID.production"
KERNEL="kernelcache.release.$REFER"
IBSS10="iBSS.$BOARDID2.RELEASE.im4p"
IBEC10="iBEC.$BOARDID2.RELEASE.im4p"
IBSS7="iBSS.$BOARDID.RELEASE.im4p"
IBEC7="iBEC.$BOARDID.RELEASE.im4p"
KERNEL10="kernelcache.release.$BOARDID2"

INFO_TEXT="surrealra1n - $CURRENT_VERSION
Tether Downgrader for some checkm8 64bit devices, iOS 7.0 - 17.6.1

Uses latest SHSH blobs (for tethered downgrades)
iSuns9 fork of asr64_patcher is used for patching ASR
Huge thanks to bodyc1m for iPod touch 6 support, including the Arch Linux/Fedora port they did.
Huge thanks to Mineek for seprmvr64.

Device: $NAME
ECID: $ECID

Device is in $MODE mode."

save_activation_records(){

if [[ $MODE == Normal ]]; then
    echo "请确保你的设备已越狱，并且已安装 openSSH！"
    sleep 5
else
    echo "当设备处于恢复模式或 DFU 模式时，无法保存激活记录。"
    echo "要保存激活记录，你的设备必须处于正常模式并已越狱。"
    exit 1
fi

if [[ $DEVICE_VERSION == 15.* ]]; then
    CONNECT_AS="mobile"
else
    CONNECT_AS="root"
fi
echo "SSH 将以 $CONNECT_AS 身份连接"
echo "请确保你的电脑和设备连接到同一个 Wi-Fi 网络。"
read -p "输入你设备的 IP 地址，前往 设置/无线局域网/已连接的 Wi-Fi/信息/IP 地址：" ip_address
read -p "输入你设备的 SSH 密码：" sshpwd
mkdir -p activation_records/$ECID
sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/containers/Data/System/*/Library/activation_records/activation_record.plist activation_records/$ECID/activation_record.plist
if [[ ! -f "activation_records/$ECID/activation_record.plist" ]]; then
    echo "activation_record.plist 未能正确保存。无法继续。"
    exit 1
fi
sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/mobile/Library/FairPlay/iTunes_Control/iTunes/IC-Info.sisv activation_records/$ECID/IC-Info.sisv
if [[ ! -f "activation_records/$ECID/IC-Info.sisv" ]]; then
    echo "IC-Info.sisv 未能正确保存。无法继续。"
    exit 1
fi
if [[ $DEVICE_VERSION == 15.* ]]; then
    # re-set permissions for com.apple.commcenter.device_specific_nobackup.plist and move to different dir, so you can download it when connected via mobile
    sudo ./bin/sshpass -p "$sshpwd" ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address" "echo "$sshpwd" | sudo -S cp /private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist /private/var/containers/Data/System/"
    sudo ./bin/sshpass -p "$sshpwd" ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address" "echo "$sshpwd" | sudo -S chown mobile:mobile /private/var/containers/Data/System/com.apple.commcenter.device_specific_nobackup.plist"
    sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/containers/Data/System/com.apple.commcenter.device_specific_nobackup.plist activation_records/$ECID/com.apple.commcenter.device_specific_nobackup.plist
else
    sudo ./bin/sshpass -p "$sshpwd" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $CONNECT_AS@"$ip_address":/private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist activation_records/$ECID/com.apple.commcenter.device_specific_nobackup.plist
fi
if [[ ! -f "activation_records/$ECID/com.apple.commcenter.device_specific_nobackup.plist" ]]; then 
    echo "com.apple.commcenter.device_specific_nobackup.plist 未能正确保存。无法继续。"
    sudo rm -rf activation_records/$ECID
    exit 1
fi
echo "激活记录现已保存"
sleep 4

}

activation_records_check(){

if [[ "$ECID" == 0x* || "$ECID" == 0X* ]]; then
    ECID_CLEAN="${ECID#0x}"
    ECID_CLEAN="${ECID_CLEAN#0X}"
    ECID_DEC=$(printf '%d' "0x$ECID_CLEAN")
else
    ECID_CLEAN="$ECID"
    ECID_DEC="$ECID"
fi

if [[ ! -f "activation_records/$ECID_DEC/activation_record.plist" || ! -f "activation_records/$ECID_DEC/IC-Info.sisv" ]]; then
    save_activation_records
fi

}

misc_utils(){

clear
echo "$INFO_TEXT"
echo ""
echo "选项："
echo ""
echo "1. 重新安装 surrealra1n"
echo "2. 清除所有已创建的启动文件和恢复文件"
if [[ -d "surrealra1n.old" ]]; then
    echo "3. 回到 surrealra1n 的上一个版本"
    echo "4. 返回"
else
    echo "3. 返回"
fi
if [[ -d "surrealra1n.old" ]]; then
    read -p "请输入选项（1-4）：" misc_utils_options
else
    read -p "请输入选项（1-3）：" misc_utils_options
 fi
 misc_utils_options="${misc_utils_options//[$'\r']/}"
 if [[ $misc_utils_options == 1 ]]; then
    echo "警告：你的所有启动文件和其余内容都将被删除（surrealra1n 目录中的任何文件都会被清除），并将全新安装 surrealra1n。"
    read -p "你确定要重新安装 surrealra1n 吗？（y/N）：" surrealra1n_reinstall
    surrealra1n_reinstall="${surrealra1n_reinstall//[$'\r']/}"
    if [[ $surrealra1n_reinstall == Y || $surrealra1n_reinstall == y ]]; then
        sudo rm -rf ./*
        git clone --branch development https://github.com/pwnerblu/surrealra1n repo --recursive
        if [[ ! -d repo ]]; then
            echo "克隆仓库失败。你需要从 GitHub 的 releases 页面获取 surrealra1n"
            exit 1
        fi
        echo "正在复制新文件..."
        cp -av repo/. ./
        chmod +x surrealra1n.sh

        rm -rf "repo"
        echo "surrealra1n 已重新安装！请重新运行脚本"
        exit 0
    else
        echo "surrealra1n 重新安装已取消。"
        misc_utils
    fi
elif [[ $misc_utils_options == 2 ]]; then
    echo "警告：你的所有启动文件和恢复文件都将被删除。如果继续，之后你需要重新生成它们。"
    echo "如果你想要更多磁盘空间，这可能会很有用。"
    read -p "你确定要清除这些文件吗？（y/N）：" clear_files    
    clear_files="${clear_files//[$'\r']/}"
    if [[ $clear_files == y || $clear_files == Y ]]; then
        sudo rm -rf "boot"
        sudo rm -rf "restorefiles"
        sudo rm -rf "noseprestore"
    else
        echo "清除启动文件/恢复文件已取消"
        misc_utils
    fi
elif [[ $misc_utils_options == 3 ]] && [[ -d "surrealra1n.old" ]]; then
    old_version=$(cat surrealra1n.old/oldversion.txt)
    if [[ "$old_version" == *beta* ]]; then
        echo "如果你从测试版更新而来，则不支持回滚功能。"
        rm -rf "surrealra1n.old"
        sleep 4
        misc_utils
        return
    fi
    echo "警告：这将把 surrealra1n 恢复到备份在 surrealra1n.old 中的上一个版本。"
    echo "此 surrealra1n 版本中的任何新功能在上一个版本中可能都不存在"
    read -p "你确定要回到上一个版本吗？（y/N）：" rollback_confirm
    rollback_confirm="${rollback_confirm//[$'\r']/}"
    if [[ $rollback_confirm == Y || $rollback_confirm == y ]]; then
        rm -rf "bin"
        rm -rf "futurerestore"
        rm -rf "keys"
        rm -rf surrealra1n.sh
        cp -av surrealra1n.old/. ./
        chmod +x surrealra1n.sh
        rm -rf "surrealra1n.old"
        echo "surrealra1n 已恢复到上一个版本！请重新运行脚本。"
        echo "如果你之后想回到最新版本，可以随时升级。"
        exit 0
    else
        echo "回滚已取消。"
        misc_utils
    fi
elif [[ $misc_utils_options == 3 ]] || [[ $misc_utils_options == 4 ]]; then
    main_menu
else
    echo "无效选项。退出。"
    exit 1
fi

}

pwn_device(){

if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4* ]] && [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
    echo "A7 设备在 Linux 上破解可能会出现问题"
    echo "如果你有 MacBook，请改用它在上面运行 surrealra1n"
    echo "你可以选择继续尝试在 Linux 上破解"
    read -p "按回车继续"
fi

echo "正在检查此设备是否已处于破解 DFU 状态"
irecovery_output=$(./bin/irecovery -q 2>/dev/null) || true
if echo "$irecovery_output" | grep -q "PWND"; then
    echo "设备已破解！"
    if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
        echo "跳过 gaster 重置"
    else
        ./bin/gaster reset
    fi
    return
elif [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
    echo "请继续执行以下操作："
    echo "A12/A13 有线降级仅供高级用户使用。如果你不清楚自己在做什么，请勿继续"
    echo "从电脑上断开你的设备，然后将其连接到你的 Pi Pico"
    echo "请确保你的 Pi Pico 已刷入使用 usbliter8 破解设备所需的定制固件。"
    read -p "设备成功破解并且重新连接到电脑后，按回车继续"
else
    echo "设备尚未破解，正在尝试破解"
    ./bin/gaster pwn 
    ./bin/gaster reset
    if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
        ./bin/irecovery -f surrealra1n.sh
        ./bin/gaster reset
    fi
fi

echo "正在检查此设备是否已成功破解"
irecovery_output=$(./bin/irecovery -q 2>/dev/null) || true
if echo "$irecovery_output" | grep -q "PWND"; then
    echo "设备已破解！"
else
    echo "设备未能成功破解"
    exit 1
fi

}

dfu_helper(){

if [[ $MODE == Normal || $MODE == Recovery ]]; then
    echo "你需要将你的设备置于 DFU 模式。"
    read -p "你需要关于如何操作的方法说明吗？（y/n）：" dfu_instructions
    dfu_instructions="${dfu_instructions//[$'\r']/}"
    if [[ $dfu_instructions == y || $dfu_instructions == Y ]]; then
        echo "说明将在以下时间开始："
        echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "按住电源键和主屏幕按钮。" 
        echo "10" && sleep 1 && echo "9" && sleep 1 && echo "8" && sleep 1 && echo "7" && sleep 1 && echo "6" && sleep 1 && echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "现在松开电源键，但继续按住主屏幕按钮。"
        echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
    else
        echo "现在将你的设备置于 DFU 模式"
    fi
fi

echo "正在检查 DFU 设备"
if [[ $dfu_instructions == Y || $dfu_instructions == y ]]; then
    MODE=$(./bin/irecovery -q | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
    if [[ $MODE == DFU ]]; then
        echo "设备已成功进入 DFU 模式！"
    else
        echo "设备未能成功进入 DFU 模式"
        exit 1
    fi
else
    while true; do
      MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
      if [ "$MODE" = "DFU" ]; then
        echo "设备现在处于 DFU 模式！"
        break
      fi

      sleep 1
    done
fi

}

switch_to_development(){

echo "正在获取最新开发版本信息..."
download_with_retry "https://github.com/pwnerblu/surrealra1n/raw/refs/heads/development/update/latest.txt" "update/latest_dev.txt" 128
DEV_VERSION=$(head -n 1 "update/latest_dev.txt" | tr -d '\r\n')
echo "当前版本：$CURRENT_VERSION"
echo "最新开发版本：$DEV_VERSION"
echo ""
echo "警告：你即将切换到开发分支。"
echo "开发版本不稳定，可能包含 bug 或不兼容变更。"
echo ""
read -p "你确定要切换到开发版吗？（y/N）：" switch_confirm
switch_confirm="${switch_confirm//[$'\r']/}"
if [[ $switch_confirm == Y || $switch_confirm == y ]]; then
    echo "正在备份你当前的 surrealra1n 安装..."
    rm -rf "surrealra1n.old"
    mkdir -p surrealra1n.old
    echo "$CURRENT_VERSION" > surrealra1n.old/oldversion.txt
    mv -v bin surrealra1n.old/
    mv -v futurerestore surrealra1n.old/
    mv -v keys surrealra1n.old/
    mv -v surrealra1n.sh surrealra1n.old/
    git clone --branch development https://github.com/pwnerblu/surrealra1n repo --recursive
    if [[ ! -d repo ]]; then
        echo "克隆仓库失败。"
        exit 1
    fi
    echo "正在复制新文件..."
    cp -av repo/. ./
    chmod +x surrealra1n.sh
    rm -rf "repo"
    echo "surrealra1n 已切换到开发版 ${DEV_VERSION}！请重新运行脚本。"
    exit 0
else
    echo "切换到开发版已取消。"
    main_menu
fi

}

switch_to_main(){

echo "正在获取最新稳定版本信息..."
download_with_retry "https://github.com/pwnerblu/surrealra1n/raw/refs/heads/main/update/latest.txt" "update/latest_main.txt" 128
MAIN_VERSION=$(head -n 1 "update/latest_main.txt" | tr -d '\r\n')

CURRENT_CLEAN=$(echo "$CURRENT_VERSION" | sed 's/ beta//g' | sed 's/ .*//g' | tr -d 'v')
MAIN_CLEAN=$(echo "$MAIN_VERSION" | sed 's/ beta//g' | sed 's/ .*//g' | tr -d 'v')

CURRENT_MAJOR=$(echo "$CURRENT_CLEAN" | cut -d'.' -f1)
CURRENT_MINOR=$(echo "$CURRENT_CLEAN" | cut -d'.' -f2)
CURRENT_PATCH=$(echo "$CURRENT_CLEAN" | cut -d'.' -f3)
CURRENT_PATCH=${CURRENT_PATCH:-0}

MAIN_MAJOR=$(echo "$MAIN_CLEAN" | cut -d'.' -f1)
MAIN_MINOR=$(echo "$MAIN_CLEAN" | cut -d'.' -f2)
MAIN_PATCH=$(echo "$MAIN_CLEAN" | cut -d'.' -f3)
MAIN_PATCH=${MAIN_PATCH:-0}

echo "当前版本：$CURRENT_VERSION"
echo "最新稳定版：$MAIN_VERSION"
echo ""

if [[ "$CURRENT_MAJOR" == "$MAIN_MAJOR" && "$CURRENT_MINOR" == "$MAIN_MINOR" && "$CURRENT_PATCH" == "$MAIN_PATCH" ]]; then
    echo "你当前已经处于对应版本 $MAIN_VERSION 的稳定版。"
    echo "无需操作。"
    read -p "按回车返回"
    main_menu
    return
fi

if [[ "$CURRENT_MAJOR" -gt "$MAIN_MAJOR" ]] || \
   [[ "$CURRENT_MAJOR" -eq "$MAIN_MAJOR" && "$CURRENT_MINOR" -gt "$MAIN_MINOR" ]]; then
    echo "警告：你当前处于 ${CURRENT_VERSION}（开发分支）。"
    echo "最新稳定版是 ${MAIN_VERSION}（main 分支）。"
    echo "由于你的开发版本比稳定版更新，切换将需要一次全新安装。"
    echo "这意味着所有启动文件、恢复文件和二进制文件都将被删除。"
    echo ""
    read -p "你确定要切换到稳定版吗？（y/N）：" switch_confirm
    switch_confirm="${switch_confirm//[$'\r']/}"
    if [[ $switch_confirm == Y || $switch_confirm == y ]]; then
        sudo rm -rf ./*
        git clone --branch main https://github.com/pwnerblu/surrealra1n repo --recursive
        if [[ ! -d repo ]]; then
            echo "克隆仓库失败。"
            exit 1
        fi
        echo "正在复制新文件..."
        cp -av repo/. ./
        chmod +x surrealra1n.sh
        rm -rf "repo"
        echo "surrealra1n 已切换到稳定版 ${MAIN_VERSION}！请重新运行脚本。"
        exit 0
    else
        echo "切换到稳定版已取消。"
        main_menu
    fi
else
    echo "你处于 ${CURRENT_VERSION}（开发分支）。"
    echo "最新稳定版是 ${MAIN_VERSION}（main 分支）。"
    echo "这将把你升级到稳定版，而不会清除你的启动/恢复文件。"
    echo ""
    read -p "你是否想切换到稳定版？（Y/n）：" switch_confirm
    switch_confirm="${switch_confirm//[$'\r']/}"
    if [[ $switch_confirm == Y || $switch_confirm == y ]]; then
        rm -rf "surrealra1n.old"
        mkdir -p surrealra1n.old
        echo "正在备份你当前的 surrealra1n 安装..."
        echo "$CURRENT_VERSION" > surrealra1n.old/oldversion.txt
        mv -v bin surrealra1n.old/
        mv -v futurerestore surrealra1n.old/
        mv -v keys surrealra1n.old/
        mv -v surrealra1n.sh surrealra1n.old/
        git clone --branch main https://github.com/pwnerblu/surrealra1n repo --recursive
        if [[ ! -d repo ]]; then
            echo "克隆仓库失败。"
            exit 1
        fi
        echo "正在复制新文件..."
        cp -av repo/. ./
        chmod +x surrealra1n.sh
        rm -rf "repo"
        echo "surrealra1n 已切换到稳定版 ${MAIN_VERSION}！请重新运行脚本。"
        exit 0
    else
        echo "切换到稳定版已取消。"
        main_menu
    fi
fi

}

dfu_helper_a11(){

if [[ $MODE == Normal || $MODE == Recovery ]]; then
    echo "你需要将你的设备置于 DFU 模式。"
    read -p "你需要关于如何操作的方法说明吗？（y/n）：" dfu_instructions
    dfu_instructions="${dfu_instructions//[$'\r']/}"
    if [[ $dfu_instructions == y || $dfu_instructions == Y ]] && [[ $MODE == Recovery ]]; then
        echo "说明将在以下时间开始："
        echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "按住音量减键和电源键。" 
        echo "4" && sleep 1 && echo "3" && sleep 1 && ./bin/irecovery -n && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "现在松开电源键，但继续按住音量减键。"
        echo "8" && sleep 1 && echo "7" && sleep 1 && echo "6" && sleep 1 && echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
    elif [[ $dfu_instructions == y || $dfu_instructions == Y ]] && [[ $MODE == Normal ]]; then
        echo "将你的设备置于恢复模式，然后继续"
        read -p "设备进入恢复模式后按回车继续"
        echo "说明将在以下时间开始："
        echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "按住音量减键和电源键。" 
        echo "4" && sleep 1 && echo "3" && sleep 1 && ./bin/irecovery -n && echo "2" && sleep 1 && echo "1" && sleep 1
        echo "现在松开电源键，但继续按住音量减键。"
        echo "8" && sleep 1 && echo "7" && sleep 1 && echo "6" && sleep 1 && echo "5" && sleep 1 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 && echo "1" && sleep 1
    else
        echo "现在将你的设备置于 DFU 模式"
    fi
fi

echo "正在检查 DFU 设备"
if [[ $dfu_instructions == Y || $dfu_instructions == y ]]; then
    MODE=$(./bin/irecovery -q | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
    if [[ $MODE == DFU ]]; then
        echo "设备已成功进入 DFU 模式！"
    else
        echo "设备未能成功进入 DFU 模式"
        exit 1
    fi
else
    while true; do
      MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
      if [ "$MODE" = "DFU" ]; then
        echo "设备现在处于 DFU 模式！"
        break
      fi

      sleep 1
    done
fi

}

reset_restore_vars() {
    IPSW_PATH=""
    IPSW_PATH_LATEST=""
    SHSH_PATH=""
    VERSION=""
    BUILD=""
    VERSION_LATEST=""
}

sep_checker(){

if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPod7* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 ]] && [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.0* || $VERSION == 11.0* || $VERSION == 11.1* || $VERSION == 11.2* ]]; then
    echo "SEP 不兼容。恢复无法继续"
    exit 1
fi
if [[ $IDENTIFIER == iPhone6* ]] && [[ $VERSION == 10.1* ]]; then
    echo "SEP 兼容，但 Touch ID 将失效"
    read -p "按回车继续"
fi
if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]] && [[ $VERSION == 10.1* || $VERSION == 10.2* || $VERSION == 10.3* ]]; then
    echo "SEP 兼容，但 Touch ID 将失效，设备启动可能需要 3-5 分钟，并且可能在设置过程中卡住"
    read -p "按回车继续"
fi
if [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 13.* ]]; then
    echo "SEP 兼容，但 Touch ID 将失效，设备启动可能需要 3-5 分钟，并且在设置中进入 Touch ID 环节时可能会卡住 30 秒。也很可能出现深度睡眠问题。"
fi
if [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]] && [[ $VERSION == 11.3* || $VERSION == 11.4* || $VERSION == 12.* ]]; then
    echo "SEP 兼容，但 Touch ID 将失效"
    read -p "按回车继续"
fi
if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.* || $VERSION == 11.* || $VERSION == 12.* ]]; then
    echo "SEP 不兼容。恢复无法继续"
    exit 1
fi
if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.3* || $VERSION == 14.4* || $VERSION == 14.5* || $VERSION == 14.6* || $VERSION == 14.7* || $VERSION == 14.8* || $VERSION == 15.* ]]; then
    echo "SEP 部分不兼容"
    echo "恢复后设备将无法激活。"
    echo "以及其他可能损坏的功能"
    read -p "按回车继续"
fi
if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 11.* || $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.0* || $VERSION == 14.1* || $VERSION == 14.2* ]]; then
    echo "SEP 不兼容。恢复无法继续"
    exit 1
fi

}

download_tvos_sep(){

mkdir -p tmp
sep_path="tmp/sep-firmware.j42d.RELEASE.im4p"
manifest_path="tmp/BuildManifest-SEP.plist"
sep_ipsw="https://secure-appldnld.apple.com/tvos10.2.2/091-23452-20170720-5D53229C-6A56-11E7-8577-8B2C4A4DD6D5/AppleTV5,3_10.2.2_14W756_Restore.ipsw"
curl -L -o tmp/BuildManifest-SEP.plist https://github.com/pwnerblu/cursed-sep-resources/raw/refs/heads/main/BuildManifest-$IDENTIFIER.plist
sudo ./bin/pzb -g Firmware/all_flash/sep-firmware.j42d.RELEASE.im4p $sep_ipsw
sudo mv -v sep-firmware.j42d.RELEASE.im4p $sep_path

}

download_iphone6_sep(){

mkdir -p tmp
sep_path="tmp/sep-firmware.n61.RELEASE.im4p"
manifest_path="tmp/BuildManifest-SEP.plist"
sep_ipsw="https://updates.cdn-apple.com/2026WinterFCS/fullrestores/047-28352/B80B4A86-C206-4C4F-8D35-65579694AEE9/iPhone_4.7_12.5.8_16H88_Restore.ipsw"
curl -L -o tmp/BuildManifest-SEP.plist https://github.com/pwnerblu/cursed-sep-resources/raw/refs/heads/main/BuildManifest-$IDENTIFIER-12.5.8.plist
sudo ./bin/pzb -g Firmware/all_flash/sep-firmware.n61.RELEASE.im4p $sep_ipsw
sudo mv -v sep-firmware.n61.RELEASE.im4p $sep_path

}

download_1033_ota_sep(){

mkdir -p tmp
sep_path="tmp/sep-firmware.$BOARDID2.RELEASE.im4p"
sep_name="sep-firmware.$BOARDID2.RELEASE.im4p"
manifest_path="tmp/BuildManifest-SEP.plist"
if [[ $IDENTIFIER == iPhone6* ]]; then
    sep_ipsw="http://appldnld.apple.com/ios10.3.3/091-23133-20170719-CA8E78E6-6977-11E7-968B-2B9100BA0AE3/iPhone_4.0_64bit_10.3.3_14G60_Restore.ipsw"
elif [[ $IDENTIFIER == iPad4* ]]; then
    sep_ipsw="http://appldnld.apple.com/ios10.3.3/091-23378-20170719-CA983C78-6977-11E7-8922-3D9100BA0AE3/iPad_64bit_10.3.3_14G60_Restore.ipsw"
fi
curl -L -o tmp/BuildManifest-SEP.plist https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/manifest/BuildManifest_${IDENTIFIER}_10.3.3.plist
sudo ./bin/pzb -g Firmware/all_flash/$sep_name $sep_ipsw
sudo mv -v $sep_name $sep_path

}

prepatch_ibssibec_fr(){

sudo mkdir -p /tmp/futurerestore
mkdir -p work
./bin/img4tool -s "$SHSH_PATH" -e -m "$IDENTIFIER-im4m"
im4m="$IDENTIFIER-im4m"
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
if [[ $IDENTIFIER == iPhone10,1 || $IDENTIFIER == iPhone10,4 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87486/23310DA1-A434-4192-87BC-31429FD2D625/iPhone_4.7_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87451/EE6AEB4B-1BF7-4FBF-9D29-A8C7B970B495/iPhone_5.5_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87865/458334F5-D8E1-498A-A9FD-08BBD20FE007/iPhone10,3,iPhone10,6_14.3_18C66_Restore.ipsw"
fi
if [[ $VERSION == 10.3* || $VERSION == 11.* || $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.* || $VERSION == 16.* ]]; then
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS" -d work
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC" -d work
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.0 ]]; then # just for 14.0 beta 4 restore
        ( cd work && sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url && sudo ../bin/pzb -g Firmware/dfu/$IBEC $ipsw_url )
    fi
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC -o work/iBEC.raw -k $IBEC_KEY
    ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patched
    if [[ $IDENTIFIER == iPhone10* ]]; then
        ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patched -n
    fi
    ./bin/iBoot64Patcher work/iBEC.raw work/iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" -n
    sudo ./bin/img4 -i work/iBSS.patched -o /tmp/futurerestore/ibss.$BOARDID.$BUILD.patched.img4 -A -T ibss -M $im4m
    sudo ./bin/img4 -i work/iBEC.patched -o /tmp/futurerestore/ibec.$BOARDID.$BUILD.patched.img4 -A -T ibec -M $im4m
else
    # 10.3 iBSS/iBEC workaround
    IBSS_KEY=$(grep "ibss-10.3:" "$KEY_FILE" | cut -d':' -f2 | xargs)
    IBEC_KEY=$(grep "ibec-10.3:" "$KEY_FILE" | cut -d':' -f2 | xargs)
    if [[ $IDENTIFIER == iPhone6* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02949-20170327-7584B286-0D86-11E7-A4FA-7ECE122AC769/iPhone_4.0_64bit_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone7,2 ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02962-20170327-7584E8B4-0D86-11E7-B580-8CCE122AC769/iPhone_4.7_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone7,1 ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02950-20170327-75843ACC-0D86-11E7-ACCC-80CE122AC769/iPhone_5.5_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad4* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02965-20170327-758BACE4-0D86-11E7-9129-8ECE122AC769/iPad_64bit_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad5* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02967-20170327-758827FE-0D86-11E7-9B30-90CE122AC769/iPad_64bit_TouchID_10.3_14E277_Restore.ipsw"
    elif [[ $IDENTIFIER == iPod7* ]]; then
        ipsw_url="http://appldnld.apple.com/ios10.3/091-02958-20170327-75869E66-0D86-11E7-BF4D-88CE122AC769/iPodtouch_10.3_14E277_Restore.ipsw"
    fi
    sudo ./bin/pzb -g Firmware/dfu/$IBSS $ipsw_url
    sudo ./bin/pzb -g Firmware/dfu/$IBEC $ipsw_url
    sudo mv -v $IBSS work/
    sudo mv -v $IBEC work/
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC -o work/iBEC.raw -k $IBEC_KEY
    ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patched
    ./bin/iBoot64Patcher work/iBEC.raw work/iBEC.patched -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1" -n
    sudo ./bin/img4 -i work/iBSS.patched -o /tmp/futurerestore/ibss.$BOARDID.$BUILD.patched.img4 -A -T ibss -M $im4m
    sudo ./bin/img4 -i work/iBEC.patched -o /tmp/futurerestore/ibec.$BOARDID.$BUILD.patched.img4 -A -T ibec -M $im4m
fi

}

det_rsep_flag(){

if [[ $VERSION == 16.* || $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 || $IDENTIFIER == iPhone12* ]]; then
    rsep_flag=""
else
    rsep_flag="--no-rsep"
fi

}

restore_with_blobs(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "未选择 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW 不存在：$IPSW_PATH"
    exit 1
fi
if [[ -z "$SHSH_PATH" ]]; then
    echo "未选择 SHSH blob。中止。"
    exit 1
fi
if [[ ! -f "$SHSH_PATH" ]]; then
    echo "SHSH blob 不存在：$SHSH_PATH"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    echo "iPhone X 尚不受支持。"
    echo "不过 Legacy iOS Kit *确实*支持使用 blob 恢复 iPhone X"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi

if [[ $skip_blob_set == 1 ]]; then
    use_skip_blob="--skip-blob"
else
    use_skip_blob=""
fi

pwn_device
det_rsep_flag

sleep 5

if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5* || $IDENTIFIER == iPod7* ]] && [[ $VERSION == 10.* ]]; then
    download_tvos_sep
    if [[ $IDENTIFIER == iPad5* || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.3* ]]; then
        unzip -j "$IPSW_PATH" "$KERNEL" -d work
        ./bin/img4 -i work/$KERNEL -o work/kernel.raw
        ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 11 --skip-sks --skip-acm --skip-amfi
        ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
        ./bin/img4 -i work/$KERNEL -o work/kernel.im4p -T rkrn -P work/kernel.diff -J || true
        prepatch_ibssibec_fr
        while true; do
            set +e
            sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
                ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
                --sep $sep_path --sep-manifest $manifest_path \
                --custom-latest $LATEST_VERSION $use_skip_blob \
                $updatebb_flag $rsep_flag --rkrn work/kernel.im4p $IPSW_PATH
            EXIT_CODE=$?
            set -e
            if [[ $EXIT_CODE -eq 139 ]]; then
                echo "futurerestore 段错误（退出码 139），正在重试..."
                sleep 2
            else
                break
            fi
        done
        if [[ $EXIT_CODE -eq 0 ]]; then
            echo "恢复已完成！如有任何错误，请查看上方输出"
            exit 0
        else
            echo "futurerestore 失败，退出码 $EXIT_CODE"
            exit 1
        fi
    fi
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path \
            --custom-latest $LATEST_VERSION $use_skip_blob \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad4* || $IDENTIFIER == iPhone6* ]] && [[ $VERSION == 10.* ]]; then
    download_1033_ota_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path \
            --custom-latest $LATEST_VERSION $use_skip_blob \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]] && [[ $VERSION == 11.* || $VERSION == 12.* ]]; then
    download_iphone6_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path \
            --custom-latest $LATEST_VERSION $use_skip_blob \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
else
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --latest-sep \
            --custom-latest $LATEST_VERSION $use_skip_blob \
            $updatebb_flag --no-rsep $IPSW_PATH
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
fi

echo "恢复已完成！如有任何错误，请查看上方输出"
exit 0

}

restore_untethered_opts(){

clear 
echo "$INFO_TEXT"
echo ""
echo "选项："
echo ""
echo "1. 选择目标 IPSW"
echo "2. 选择 SHSH"
echo "3. 开始恢复"
echo "4. 返回"
read -p "请输入选项（1-4）：" untether_options
untether_options="${untether_options//[$'\r']/}"
if [[ $untether_options == 1 ]]; then
    ipsw_selector target
    restore_untethered_opts
elif [[ $untether_options == 2 ]]; then
    SHSH_PATH=$(pick_file "选择一个 SHSH2 文件")
    if [[ -z "$SHSH_PATH" ]]; then
        echo "未选择 SHSH blob。中止。"
        exit 1
    fi
    echo "已选择一个 SHSH blob。请确保此 blob 对 iOS $VERSION 有效，否则恢复很可能会失败"
    read -p "按回车继续"
    restore_untethered_opts
elif [[ $untether_options == 3 ]]; then
    sep_checker
    read -p "你是否要为此恢复启用 skip-blob？（y/n）：" skip_blob_det
    skip_blob_det="${skip_blob_det//[$'\r']/}"
    if [[ $skip_blob_det == y || $skip_blob_det == Y ]]; then
        echo "为此恢复启用 --skip-blob 选项。"
        echo "警告：这会跳过 blob 验证，请确保你的 SHSH 有效！"
        sleep 5
        skip_blob_set=1
    else
        skip_blob_set=0
    fi
    restore_with_blobs
elif [[ $untether_options == 4 ]]; then
    reset_restore_vars
    restore_utils
else
    echo "无效选项。退出。"
    exit 1
fi

}

make_custom_ipsw_ios16(){

mkdir -p restorefiles/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
find tmp1/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec rm -f {} +
find tmp2/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec cp {} tmp1/Firmware/all_flash/ \;
# because no AOP validation patch for iOS 16, fallback to latest AOP
if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    mv tmp2/Firmware/AOP/aopfw-iphone10baop.im4p tmp1/Firmware/AOP/aopfw-iphone10baop.im4p
else
    mv tmp2/Firmware/AOP/aopfw-iphone10aop.im4p tmp1/Firmware/AOP/aopfw-iphone10aop.im4p
fi
./bin/img4 -i tmp1/$KERNEL -o work/kernelboot.raw
./bin/Kernel64Patcher work/kernelboot.raw work/kernelboot.patch -e -o -h
./bin/img4 -i work/kernelboot.patch -o tmp1/$KERNEL -A -T krnl -J || true
cd tmp1
zip -0 -r ../custom.ipsw *
cd ..
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
mkdir -p work
if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    url_ios16="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65861/0A0400A0-2174-4D49-91B7-43FC9DE24272/iPhone10,3,iPhone10,6_16.0_20A362_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    url_ios16="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65568/0851247C-1B06-4CD4-B3C2-5A94026970B7/iPhone_5.5_P3_16.0_20A362_Restore.ipsw"
else
    url_ios16="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65931/BD2515B7-7802-4EB4-9377-98E3238EA5A8/iPhone_4.7_P3_16.0_20A362_Restore.ipsw"
fi
( cd work && sudo ../bin/pzb -g 098-08863-001.dmg "$url_ios16" && sudo ../bin/pzb -g $KERNEL "$url_ios16" )
restore_ramdisk_dmg=$(find_dmg work smallest)
./bin/img4 -i work/$KERNEL -o work/kernel.raw
./bin/KPlooshFinder work/kernel.raw work/kernel.patched
./bin/kerneldiff work/kernel.raw work/kernel.patched work/kernel.diff
./bin/img4 -i work/$KERNEL -o $restoredir/kernel.im4p -T rkrn -P work/kernel.diff -J || true
# rdsk prep
./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
./bin/asr64_patcher work/asr work/asr_patched
./bin/ldid -e work/asr > work/ents.plist
./bin/ldid -Swork/ents.plist work/asr_patched
./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr 
./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
./bin/ldid -Swork/ents.plist work/libimg4.patch
./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
# pack rdsk into im4p
./bin/img4 -i work/ramdisk.raw -o $restoredir/ramdisk.im4p -A -T rdsk
# Wrap up
rm -rf "tmp1"
rm -rf "work"

}

make_custom_ipsw(){

mkdir -p restorefiles/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
if [[ $VERSION == 10.1* || $VERSION == 10.2* ]]; then
    cp tmp2/Firmware/all_flash/$LLB tmp1/Firmware/all_flash/$ALLFLASH/$LLB10
    cp tmp2/Firmware/all_flash/$IBOOT tmp1/Firmware/all_flash/$ALLFLASH/$IBOOT10
elif [[ $VERSION == 10.3* ]]; then
    cp tmp2/Firmware/all_flash/$LLB tmp1/Firmware/all_flash/$LLB
    cp tmp2/Firmware/all_flash/$IBOOT tmp1/Firmware/all_flash/$IBOOT
else
    find tmp1/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec rm -f {} +
    find tmp2/Firmware/all_flash/ -type f ! -name '*DeviceTree*' -exec cp {} tmp1/Firmware/all_flash/ \;
fi
if [[ ( $VERSION == 12.* && ( $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ) ) ||
      $VERSION == 13.1* ||
      $VERSION == 13.2* ||
      $VERSION == 13.3* ]]; then
    mkdir -p work
    ramdisk_ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/041-42831/7341A77D-6526-4C64-8753-D886106F97CD/iPad_64bit_TouchID_13.4_17E255_Restore.ipsw"
    ramdisk_dmg="048-64389-366.dmg"
    ( cd work && sudo ../bin/pzb -g $ramdisk_dmg $ramdisk_ipsw_url )
    ( cd work && sudo ../bin/pzb -g $KERNEL $ramdisk_ipsw_url )
    ( cd work && sudo ../bin/pzb -g Firmware/all_flash/$DEVICETREE $ramdisk_ipsw_url )
    mv -v work/$KERNEL tmp1/$KERNEL
    mv -v work/$DEVICETREE tmp1/Firmware/all_flash/$DEVICETREE
    restore_ramdisk_dmg="work/048-64389-366.dmg"
else
    restore_ramdisk_dmg=$(find_dmg tmp1 smallest)
fi
if [[ $VERSION == 14.* ]] && [[ $IDENTIFIER == iPhone10* ]]; then
    ./bin/img4 -i tmp1/$KERNEL -o work/kernelboot.raw
    ./bin/Kernel64Patcher work/kernelboot.raw work/kernelboot.patch -b
    ./bin/img4 -i work/kernelboot.patch -o tmp1/$KERNEL -A -T krnl -J || true
elif [[ $VERSION == 15.* ]] && [[ $IDENTIFIER == iPhone10* ]]; then
    ./bin/img4 -i tmp1/$KERNEL -o work/kernelboot.raw
    ./bin/Kernel64Patcher work/kernelboot.raw work/kernelboot.patch -e -o -r -b15
    ./bin/img4 -i work/kernelboot.patch -o tmp1/$KERNEL -A -T krnl -J || true
fi
cd tmp1
zip -0 -r ../custom.ipsw *
cd ..
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
mkdir -p work
update_ramdisk_dmg=$(find_dmg tmp1 largest 1073741824)
if [[ $VERSION == 10.2* || $VERSION == 10.1* ]]; then
    cp -v tmp1/$KERNEL10 work/kernel.im4p
else
    cp -v tmp1/$KERNEL work/kernel.im4p
fi
./bin/img4 -i work/kernel.im4p -o work/kernel.raw
./bin/KPlooshFinder work/kernel.raw work/kernel.patched
if [[ $IDENTIFIER == iPad5* || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.* ]]; then
    mv -v work/kernel.patched work/kernel.patch
    ./bin/Kernel64Patcher2 work/kernel.patch work/kernel.patched -u 11 --skip-sks --skip-acm --skip-amfi
fi
./bin/kerneldiff work/kernel.raw work/kernel.patched work/kernel.diff
./bin/img4 -i work/kernel.im4p -o $restoredir/kernel.im4p -T rkrn -P work/kernel.diff -J || true
# rdsk prep
./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
if [[ $VERSION == 10.* ]]; then
    ./bin/hfsplus work/ramdisk.raw grow 60000000
fi
./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
./bin/asr64_patcher work/asr work/asr_patched
./bin/ldid -e work/asr > work/ents.plist
./bin/ldid -Swork/ents.plist work/asr_patched
./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr 
./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
    ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
    ./bin/ldid -Swork/ents.plist work/libimg4.patch
    ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
    ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
fi
if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then # do some ipx patching
    ./bin/hfsplus work/ramdisk.raw extract usr/local/bin/restored_external work/restored_external
    ./bin/ipx_restored_patcher work/restored_external work/restored_patch # use restored patcher by Mineek
    ./bin/ldid -e work/restored_external > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/restored_patch
    ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/restored_external
    ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/restored_external
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/restored_external
fi
# pack rdsk into im4p
./bin/img4 -i work/ramdisk.raw -o $restoredir/ramdisk.im4p -A -T rdsk
if [[ $IDENTIFIER == iPhone10* ]]; then
    # do update ramdisk stuff so 14.0b4 to 14.3-15.6.1 update install is possible
    ./bin/img4 -i $update_ramdisk_dmg -o work/ramdisk.raw
    ./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
    ./bin/asr64_patcher work/asr work/asr_patched
    ./bin/ldid -e work/asr > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/asr_patched
    ./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr 
    ./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
    ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
    ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
    ./bin/ldid -Swork/ents.plist work/libimg4.patch
    ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
    ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
    if [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then # do some ipx patching
        ./bin/hfsplus work/ramdisk.raw extract usr/local/bin/restored_update work/restored_external
        ./bin/ipx_restored_patcher work/restored_external work/restored_patch # use restored patcher by Mineek
        ./bin/ldid -e work/restored_external > work/ents.plist
        ./bin/ldid -Swork/ents.plist work/restored_patch
        ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/restored_update
        ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/restored_update
        ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/restored_update
    fi
    # pack rdsk into im4p
    ./bin/img4 -i work/ramdisk.raw -o $restoredir/updateramdisk.im4p -A -T rdsk
fi
# Wrap up
rm -rf "tmp1"
rm -rf "work"

}

# ---- Linux APFS helpers (EXPERIMENTAL) ----
# iOS 16.1+ restore ramdisks are raw APFS containers, which the Linux hfsplus
# CLI cannot open (it only handles the HFS+ ramdisks used up to iOS 16.0.x).
# On Linux these ramdisks are patched by mounting them through the
# linux-apfs-rw kernel module (https://github.com/linux-apfs/linux-apfs-rw),
# mirroring the hdiutil attach flow used on macOS. Everything in this block is
# Linux-only; macOS keeps using hdiutil.

APFS_TRACK_FILE="apfs/active_mounts"

# detect_fs_type <image> - print "HFS", "APFS" or "UNKNOWN" for a raw
# filesystem image (as produced by `img4 -i` from a restore ramdisk).
detect_fs_type() {
    local img="$1" sig
    if [[ ! -f "$img" ]]; then
        echo "UNKNOWN"
        return
    fi
    # HFS+ / HFSX volumes: signature "H+" / "HX" at offset 1024.
    # (tr strips null bytes so bash does not warn on binary input.)
    sig=$(dd if="$img" bs=1 skip=1024 count=2 2>/dev/null | tr -d '\000')
    if [[ $sig == "H+" || $sig == "HX" ]]; then
        echo "HFS"
        return
    fi
    # APFS container superblocks: magic "NXSB" at offset 32
    sig=$(dd if="$img" bs=1 skip=32 count=4 2>/dev/null | tr -d '\000')
    if [[ $sig == "NXSB" ]]; then
        echo "APFS"
        return
    fi
    echo "UNKNOWN"
}

# cleanup_apfs - unmount and detach every APFS loop mount we created, so a
# failed or interrupted run never leaves stale mounts or loop devices behind.
# Only entries recorded by apfs_mount in $APFS_TRACK_FILE are touched, so
# unrelated host loop devices/filesystems are never affected.
cleanup_apfs() {
    if [[ ! -f "$APFS_TRACK_FILE" ]]; then
        return
    fi
    local loopdev mnt
    while read -r loopdev mnt; do
        [[ -z "$loopdev" || -z "$mnt" ]] && continue
        sudo umount "$mnt" 2>/dev/null || true
        sudo losetup -d "$loopdev" 2>/dev/null || true
    done < "$APFS_TRACK_FILE"
    rm -f "$APFS_TRACK_FILE"
}

# setup_apfs_module - make sure the linux-apfs-rw kernel module is built for
# the running kernel and loaded. Building requires the matching kernel headers;
# loading requires root and may be blocked by Secure Boot.
setup_apfs_module() {
    if [[ $dist == 3 || $dist == 4 ]]; then
        return
    fi
    mkdir -p apfs
    if [[ -f apfs/apfs.ko && -f apfs/apfs.kernel ]] && [[ "$(cat apfs/apfs.kernel 2>/dev/null)" == "$(uname -r)" ]]; then
        echo "已找到为内核 $(uname -r) 构建的 APFS 内核模块。"
    else
        echo "正在为内核 $(uname -r) 构建 APFS 内核模块..."
        if [[ ! -d "/lib/modules/$(uname -r)/build" ]]; then
            echo "缺少适用于 $(uname -r) 的内核头文件，正在安装..."
            if [[ $dist == 1 ]]; then
                sudo apt-get install -y "linux-headers-$(uname -r)" || true
            elif [[ $dist == 2 ]]; then
                sudo pacman -S --needed linux-headers || true
            elif [[ $dist == 5 ]]; then
                sudo dnf install -y kernel-devel || true
            fi
        fi
        if [[ ! -d "/lib/modules/$(uname -r)/build" ]]; then
            echo "[!] 无法找到或安装适用于 $(uname -r) 的内核头文件。"
            echo "请手动安装它们（Debian/Ubuntu：linux-headers-$(uname -r)，Arch：linux-headers，Fedora：kernel-devel），然后重新运行。"
            exit 1
        fi
        rm -rf apfs/linux-apfs-rw
        if ! git clone --depth 1 https://github.com/linux-apfs/linux-apfs-rw apfs/linux-apfs-rw; then
            echo "[!] 克隆 linux-apfs-rw 失败（网络问题？）。"
            echo "检查你的网络连接并重新运行。"
            exit 1
        fi
        if ! ( cd apfs/linux-apfs-rw && make ); then
            echo "[!] 构建 APFS 内核模块（linux-apfs-rw）失败。"
            echo "请参见上面的构建输出；该模块需要与 $(uname -r) 匹配的内核头文件。"
            exit 1
        fi
        cp apfs/linux-apfs-rw/apfs.ko apfs/apfs.ko
        rm -rf apfs/linux-apfs-rw
        echo "$(uname -r)" > apfs/apfs.kernel
    fi
    if ! lsmod 2>/dev/null | grep -q "^apfs "; then
        if command -v mokutil &>/dev/null && [[ "$(mokutil --sb-state 2>/dev/null)" == *enabled* ]]; then
            echo "警告：已启用 Secure Boot。加载未签名内核模块可能会被阻止。"
            echo "如果下方加载失败，请注册模块签名或禁用 Secure Boot。"
        fi
        echo "正在加载 APFS 内核模块..."
        sudo modprobe libcrc32c 2>/dev/null || true
        if ! sudo insmod apfs/apfs.ko; then
            echo "[!] 加载 APFS 内核模块失败。"
            echo "检查 'dmesg | grep -i apfs'。如果已启用 Secure Boot，请注册模块"
            echo "使用 mokutil 注册签名或禁用 Secure Boot，然后重新运行。"
            exit 1
        fi
    fi
    # Clean up any mounts left behind by a previously interrupted run, then
    # make sure they are also cleaned up if this run gets interrupted.
    cleanup_apfs
    trap cleanup_apfs EXIT
}

# apfs_mount <image> <mountpoint> <ro|rw> - mount an APFS raw image through a
# loop device using the apfs kernel module. The loop device and mountpoint are
# recorded in $APFS_TRACK_FILE so cleanup_apfs can undo them.
apfs_mount() {
    local img="$1" mnt="$2" mode="${3:-ro}"
    local opts="ro"
    if [[ $mode == "rw" ]]; then
        # The mount is done with sudo (root-owned), but the ramdisk files are
        # patched as the non-root user, mirroring the macOS hdiutil flow. The
        # uid/gid overrides make the mount appear user-owned so plain cp/rm/chmod
        # work, and new files get the same user ownership macOS produces.
        opts="readwrite,uid=$(id -u),gid=$(id -g)"
    fi
    local loopdev
    loopdev=$(sudo losetup -f --show "$img" 2>/dev/null) || loopdev=""
    if [[ -z "$loopdev" ]]; then
        echo "[!] 无法为 $img 获取空闲 loop 设备"
        echo "请确保 loop 设备可用（例如 'modprobe loop'），然后重试。"
        exit 1
    fi
    echo "$loopdev $mnt" >> "$APFS_TRACK_FILE"
    if ! sudo mount -t apfs -o "$opts" "$loopdev" "$mnt"; then
        echo "[!] 无法将 ${img}（${loopdev}）作为 APFS $mode 挂载。"
        echo "检查 'dmesg | grep -i apfs' 以获取详细信息。"
        cleanup_apfs
        exit 1
    fi
}

# apfs_umount <mountpoint> - unmount and detach the loop device for a mount
# previously created by apfs_mount.
apfs_umount() {
    local mnt="$1" loopdev
    loopdev=$(awk -v m="$mnt" '$2 == m {print $1; exit}' "$APFS_TRACK_FILE" 2>/dev/null)
    sudo umount "$mnt" 2>/dev/null || true
    if [[ -n "$loopdev" ]]; then
        sudo losetup -d "$loopdev" 2>/dev/null || true
    fi
    if [[ -f "$APFS_TRACK_FILE" ]]; then
        # Only rewrite the track file if awk succeeded, so a failure can never
        # wipe the recorded mounts that cleanup_apfs relies on.
        if awk -v m="$mnt" '$2 != m' "$APFS_TRACK_FILE" > "$APFS_TRACK_FILE.tmp" 2>/dev/null; then
            mv "$APFS_TRACK_FILE.tmp" "$APFS_TRACK_FILE" 2>/dev/null || true
        else
            rm -f "$APFS_TRACK_FILE.tmp"
        fi
    fi
}

make_custom_ipsw_a12_ios16(){

# iOS 16.0.x is supported on both macOS and Linux (the restore ramdisk is HFS+)
# iOS 16.1+ restore ramdisks use APFS, which the Linux hfsplus CLI cannot handle.
# On Linux we patch APFS ramdisks through the experimental linux-apfs-rw kernel
# module, so iOS 16.1+ restores on Linux are EXTREMELY EXPERIMENTAL.
if [[ $dist == 3 || $dist == 4 ]]; then
    echo ""
elif [[ $VERSION == 16.0* ]]; then
    echo "Linux 上 iOS 16.0.x 的 A12/A13 降级"
else
    echo ""
    echo "警告：Linux 上 iOS 16.1+ 的恢复是实验性的，请谨慎操作。"
    echo ""
    echo "此功能是全新的，尚未经过与现有实现同等程度的测试"
    echo "macOS 实现。它通过构建并加载实验性的 linux-apfs-rw 内核模块来修补 APFS 恢复 ramdisk，"
    echo "其写入支持可能损坏 ramdisk。失败或中断的恢复可能使你的设备需要恢复"
    echo "ramdisk。失败或中断的恢复可能使你的设备需要恢复"
    echo "或进行完整恢复，而且这种实验性的 Linux 支持在可靠性方面并不等同"
    echo "相较于成熟的 macOS 实现。"
    echo ""
    read -p "输入 YES 继续，输入其他任何内容则中止：" apfs_consent
    if [[ $apfs_consent != YES ]]; then
        echo "中止。"
        exit 1
    fi
fi

if [[ $VERSION == 17.* ]] && [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
    echo "目前 Linux 上不支持 iOS 17 降级。"
    exit 1
fi

IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
mkdir -p restorefiles/$IDENTIFIER/$VERSION
mkdir -p boot/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
mkdir -p work
./bin/img4 -i tmp1/Firmware/dfu/$IBSS -o work/iBSS.raw -k $IBSS_KEY
./bin/iBootPatch work/iBSS.raw boot/$IDENTIFIER/iBSS.patch
./bin/iBootPatch -v -b "-v" work/iBSS.raw work/iBSS.patchboot 
./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
#
if [[ $VERSION == 16.4* || $VERSION == 16.5* ]]; then
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 116000000)
elif [[ $VERSION == 16.6* ]]; then
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 118000000)
elif [[ $VERSION == 17.0* || $VERSION == 17.1* || $VERSION == 17.2* ]]; then
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 131000000)
elif [[ $VERSION == 17.4* ]]; then
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 137000000)
elif [[ $VERSION == 17.5* || $VERSION == 17.6* ]]; then
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 202000000)
elif [[ $VERSION == 17.3.1 ]]; then
    restore_ramdisk_dmg="tmp1/087-41420-059.dmg"
elif [[ $VERSION == 17.3 ]]; then
    restore_ramdisk_dmg="tmp1/087-41420-057.dmg"
elif [[ $VERSION == 16.3* || $VERSION == 16.2* ]]; then
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 114000000)
elif [[ $VERSION == 16.1.2 ]]; then
    restore_ramdisk_dmg="tmp1/078-65071-114.dmg"
elif [[ $VERSION == 16.1.1 ]]; then
    restore_ramdisk_dmg="tmp1/078-65071-113.dmg"
elif [[ $VERSION == 16.1 ]]; then
    restore_ramdisk_dmg="tmp1/078-65071-107.dmg"
else
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 148000000)
fi
cryptex_os=$(find_dmg tmp1 largest 3800000000)
cryptex_os_18=$(find_dmg_arm64e tmp2 largest 2100000000)
cryptex_app=$(find_dmg tmp1 smallest)
cryptex_app_18=$(find_dmg tmp2 smallest)
restored="restored_external"
if [[ $LATEST_VERSION == 18.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 179000000)
elif [[ $LATEST_VERSION == 27.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 244000000)
elif [[ $LATEST_VERSION == 26.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 232784000)
fi
fs_dmg_18=$(find_dmg_arm64e tmp2 largest)
fs_dmg=$(find_dmg tmp1 largest)
fs_dmg_name=${fs_dmg##*/}
fs_dmg_18_name=${fs_dmg_18##*/}
ramdisk_dmg_name_18=${restore_ramdisk_dmg_18##*/}
ramdisk_dmg_name=${restore_ramdisk_dmg##*/}
cryptex_os_name=${cryptex_os##*/}
cryptex_app_name=${cryptex_app##*/}
cryptex_os_name_18=${cryptex_os_18##*/}
cryptex_app_name_18=${cryptex_app_18##*/}
if [[ $IDENTIFIER == iPhone12,8 || $IDENTIFIER == iPhone12,1 || $IDENTIFIER == iPhone11,8 || $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPad11,1 ]]; then
    IDENTITY="0"
elif [[ $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone12,5 || $IDENTIFIER == iPad11,2 ]]; then
    IDENTITY="1"
elif [[ $IDENTIFIER == iPhone11,6 || $IDENTIFIER == iPad11,3 ]]; then
    IDENTITY="2"
elif [[ $IDENTIFIER == iPad11,4 ]]; then
    IDENTITY="3"
fi
sudo KERNEL2="$KERNEL2" IDENTITY="$IDENTITY" python3 <<'PY'
import os
import plistlib

with open("tmp2/BuildManifest.plist", "rb") as f:
    plist = plistlib.load(f)

identity = int(os.environ["IDENTITY"])

plist["BuildIdentities"][identity]["Manifest"]["KernelCache"]["Info"]["Path"] = os.environ["KERNEL2"]

with open("tmp2/BuildManifest.plist", "wb") as f:
    plistlib.dump(plist, f)
PY
if [[ $VERSION == 17.* ]]; then
    sudo plutil -replace BuildIdentities.$IDENTITY.Manifest.RestoreDeviceTree.Info.Path -string "Firmware/all_flash/DeviceTree.im4p" tmp2/BuildManifest.plist
fi
if [[ $VERSION == 16.* || $VERSION == 17.0* || $VERSION == 17.1* || $VERSION == 17.2* || $VERSION == 17.3* || $VERSION == 17.4* ]]; then
    cp -v tmp1/Firmware/AOP/$AOP14 tmp2/Firmware/AOP/$AOP
else
    cp -v tmp1/Firmware/AOP/$AOP tmp2/Firmware/AOP/$AOP
fi
cp -v tmp1/Firmware/agx/$GFX tmp2/Firmware/agx/$GFX
cp -v tmp1/Firmware/ane/$ANE tmp2/Firmware/ane/$ANE
cp -v tmp1/Firmware/isp_bni/$ISP tmp2/Firmware/isp_bni/$ISP
if [[ $IDENTIFIER == iPhone* ]]; then
    cp -v tmp1/Firmware/$CALLAN tmp2/Firmware/$CALLAN
    cp -v tmp1/Firmware/WirelessPower/$WIRELESS tmp2/Firmware/WirelessPower/$WIRELESS
fi
if [[ ($IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12*) &&
      $IDENTIFIER != iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$HAPTICASSET tmp2/Firmware/$HAPTICASSET
fi
cp -v tmp1/Firmware/all_flash/$DEVICETREE tmp2/Firmware/all_flash/$DEVICETREE
cp -v tmp1/Firmware/$IOFW tmp2/Firmware/$IOFW
cp -v tmp1/Firmware/ave/$AVE tmp2/Firmware/ave/$AVE
cp -v tmp1/Firmware/$fs_dmg_name.root_hash tmp2/Firmware/$fs_dmg_18_name.root_hash 
cp -v tmp1/Firmware/$fs_dmg_name.mtree tmp2/Firmware/$fs_dmg_18_name.mtree 
if [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPhone12* ]]; then
    echo "使用最新的 MTFW"
elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
    echo "使用最新的 MTFW"
else
    cp -v tmp1/Firmware/$MTFW tmp2/Firmware/$MTFW # copy MTFW for target iOS
fi
if [[ ($IDENTIFIER == iPhone12*) &&
      $IDENTIFIER != iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$LEAPHAPTIC tmp2/Firmware/$LEAPHAPTIC
    cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
fi
if [[ $IDENTIFIER == iPhone12* ]]; then
    cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
fi
cp -v $fs_dmg $fs_dmg_18 # replace rootfs in the IPSW
cp -v tmp1/Firmware/$fs_dmg_name.trustcache tmp2/Firmware/$fs_dmg_18_name.trustcache 
cp -v tmp1/Firmware/$ramdisk_dmg_name.trustcache tmp2/Firmware/$ramdisk_dmg_name_18.trustcache
# replace cryptex1 components with target cryptex (latest cryptex will not work on iOS 16)
cp -v $cryptex_os $cryptex_os_18
cp -v $cryptex_app $cryptex_app_18
cp -v tmp1/Firmware/$cryptex_os_name.trustcache tmp2/Firmware/$cryptex_os_name_18.trustcache
cp -v tmp1/Firmware/$cryptex_os_name.root_hash tmp2/Firmware/$cryptex_os_name_18.root_hash
cp -v tmp1/Firmware/$cryptex_app_name.trustcache tmp2/Firmware/$cryptex_app_name_18.trustcache
cp -v tmp1/Firmware/$cryptex_app_name.root_hash tmp2/Firmware/$cryptex_app_name_18.root_hash
#
./bin/img4tool -e tmp1/$KERNEL -o work/kernel.raw
if [[ $VERSION == 16.* ]]; then
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -we -d # patch cryptex1 validations
else
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -we -i -ue -d # patch cryptex1 validations
fi
rm -rf tmp2/$KERNEL
./bin/img4 -i work/kernelboot.patch -o tmp2/$KERNEL2 -A -T krnl -J || true
if [[ $VERSION == 16.* ]]; then
    cp -v tmp1/$KERNEL tmp2/$KERNEL
else
    # do patch the other Way
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernel.patch -ue
    ./bin/img4 -i work/kernel.patch -o tmp2/$KERNEL -A -T krnl -J || true
    # now patch the devicetree
    curl -L -o bin/dtpatch.py https://github.com/pwnerblu/usbliter8-fun/raw/refs/heads/main/work-27.0b4-n104/patch_dt2.py
    ./bin/img4 -i tmp1/Firmware/all_flash/$DEVICETREE -o tmp1/DeviceTree.raw
    python3 bin/dtpatch.py tmp1/DeviceTree.raw -o tmp1/DeviceTree.patch
    ./bin/img4 -i tmp1/DeviceTree.patch -o tmp2/Firmware/all_flash/$DEVICETREE -A -T dtre
    perl -pi -e 's/content-protect/content-protecV/g' tmp1/DeviceTree.raw
    ./bin/img4 -i tmp1/DeviceTree.raw -o tmp2/Firmware/all_flash/DeviceTree.im4p -A -T rdtr
fi
# ramdisk patching: use hdiutil on macOS, hfsplus on Linux
if [[ $dist == 3 || $dist == 4 ]]; then
    # macOS: use hdiutil to mount/modify the ramdisk DMG
    ./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.dmg
    hdiutil attach work/ramdisk.dmg -mountpoint rdwork
    cp -v rdwork/usr/sbin/asr work/asr
    ./bin/asr64_patcher work/asr work/asr_patched
    ./bin/ldid -e work/asr > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/asr_patched
    rm -rf rdwork/usr/sbin/asr 
    cp -v work/asr_patched rdwork/usr/sbin/asr
    chmod 755 rdwork/usr/sbin/asr
    #
    cp -v rdwork/usr/lib/libimg4.dylib work/libimg4.dylib
    if [[ $VERSION == 16.* || $VERSION == 17.0* || $VERSION == 17.1* || $VERSION == 17.2* || $VERSION == 17.3* ]]; then
        ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
    else
        ./bin/Kernel64Patcher3 work/libimg4.dylib work/libimg4.patch -li
    fi
    ./bin/ldid -Swork/ents.plist work/libimg4.patch
    if [[ $VERSION == 16.* || $VERSION == 17.0* || $VERSION == 17.1* || $VERSION == 17.2* || $VERSION == 17.3* ]]; then
        rm -rf rdwork/usr/lib/libimg4.dylib 
        cp -v work/libimg4.patch rdwork/usr/lib/libimg4.dylib
        chmod 755 rdwork/usr/lib/libimg4.dylib
    else
        rm -rf rdwork/usr/lib/libimage4.dylib 
        cp -v work/libimg4.patch rdwork/usr/lib/libimage4.dylib
        chmod 755 rdwork/usr/lib/libimage4.dylib
    fi
    # restored patch start
    if [[ $VERSION == 16.4* || $VERSION == 16.5* || $VERSION == 16.6* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2023SpringFCS/fullrestores/032-68311/B777E36E-32B8-4DEF-91CE-9909B04FD22D/iPhone10,3,iPhone10,6_16.4_20E247_Restore.ipsw"
        ramdisk_dmg="078-23800-379.dmg"
    elif [[ $VERSION == 17.0* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-49474/5DF24914-F32D-4940-830F-3D8C8860A75B/iPad_64bit_TouchID_ASTC_17.0_21A329_Restore.ipsw"
        ramdisk_dmg="097-83622-002.dmg"
    elif [[ $VERSION == 17.1* || $VERSION == 17.2* || $VERSION == 17.3* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-07636/DBDB5860-91CF-4757-B7BD-6402D4445AF2/iPad_64bit_TouchID_ASTC_17.1_21B74_Restore.ipsw"
        ramdisk_dmg="097-22998-092.dmg"
    elif [[ $VERSION == 17.4* || $VERSION == 17.5* || $VERSION == 17.6* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2024WinterFCS/fullrestores/052-61449/211A56A4-2B9B-4054-A190-73227405F1C7/iPad_64bit_TouchID_ASTC_17.4_21E219_Restore.ipsw"
        ramdisk_dmg="096-18092-354.dmg"
    elif [[ $VERSION == 16.1* || $VERSION == 16.2* || $VERSION == 16.3* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-92982/6DF106AB-8868-433F-8C3F-05D50785E81E/iPhone10,3,iPhone10,6_16.1_20B82_Restore.ipsw"
        ramdisk_dmg="078-64668-109.dmg"
    else
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65861/0A0400A0-2174-4D49-91B7-43FC9DE24272/iPhone10,3,iPhone10,6_16.0_20A362_Restore.ipsw"
        ramdisk_dmg="098-08863-001.dmg"
    fi
    ( cd work && sudo ../bin/pzb -g $ramdisk_dmg $ramdisk_ipsw_url )
    ./bin/img4 -i work/$ramdisk_dmg -o work/ramdisk2.dmg
    hdiutil attach work/ramdisk2.dmg -mountpoint rdwork2
    cp -v rdwork2/usr/local/bin/restored_external work/restored_external
    hdiutil detach rdwork2
    ./bin/restoredpatcher work/restored_external work/restored_patch -c # patch cryptex1 install validation
    ./bin/ldid -e work/restored_external > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/restored_patch
    rm -rf rdwork/usr/local/bin/restored_external
    cp -v work/restored_patch rdwork/usr/local/bin/restored_external
    chmod 755 rdwork/usr/local/bin/restored_external
    hdiutil detach rdwork
    # restored end
    ./bin/img4 -i tmp1/Firmware/$ramdisk_dmg_name.trustcache -o work/trustcache.raw
    ./bin/trustcache append work/trustcache.raw work/restored_patch
    ./bin/trustcache append work/trustcache.raw work/asr_patched
    ./bin/trustcache append work/trustcache.raw work/libimg4.patch
    ./bin/img4 -i work/trustcache.raw -o tmp2/Firmware/$ramdisk_dmg_name_18.trustcache -A -T rtsc
    # pack rdsk into im4p
    ./bin/img4 -i work/ramdisk.dmg -o $restore_ramdisk_dmg_18 -A -T rdsk
else
    # Linux: use the hfsplus CLI for HFS+ ramdisks (iOS 16.0.x), or mount APFS
    # ramdisks (iOS 16.1+) through the linux-apfs-rw kernel module, mirroring the
    # hdiutil attach flow used on macOS. The filesystem type is detected
    # automatically from the ramdisk contents.
    ./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
    ramdisk_fs=$(detect_fs_type work/ramdisk.raw)
    if [[ $ramdisk_fs == "HFS" ]]; then
        ./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
        ./bin/asr64_patcher work/asr work/asr_patched
        ./bin/ldid -e work/asr > work/ents.plist
        ./bin/ldid -Swork/ents.plist work/asr_patched
        ./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr
        ./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
        ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
        #
        ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
        ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
        ./bin/ldid -Swork/ents.plist work/libimg4.patch
        ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib
        ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
        ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
    elif [[ $ramdisk_fs == "APFS" ]]; then
        setup_apfs_module
        mkdir -p work/rdmnt
        apfs_mount work/ramdisk.raw work/rdmnt rw
        cp -v work/rdmnt/usr/sbin/asr work/asr
        ./bin/asr64_patcher work/asr work/asr_patched
        ./bin/ldid -e work/asr > work/ents.plist
        ./bin/ldid -Swork/ents.plist work/asr_patched
        rm -rf work/rdmnt/usr/sbin/asr
        cp -v work/asr_patched work/rdmnt/usr/sbin/asr
        chmod 755 work/rdmnt/usr/sbin/asr
        #
        cp -v work/rdmnt/usr/lib/libimg4.dylib work/libimg4.dylib
        ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
        ./bin/ldid -Swork/ents.plist work/libimg4.patch
        rm -rf work/rdmnt/usr/lib/libimg4.dylib
        cp -v work/libimg4.patch work/rdmnt/usr/lib/libimg4.dylib
        chmod 755 work/rdmnt/usr/lib/libimg4.dylib
    else
        echo "[!] 恢复 ramdisk 中的文件系统无法识别（${restore_ramdisk_dmg}）。"
        echo "预期的是 HFS+（iOS 16.0.x）或 APFS（iOS 16.1+）文件系统。为安全起见中止。"
        exit 1
    fi
    # restored patch start: the restored_external binary must come from a ramdisk
    # of the matching iOS version (like macOS); the 16.0 ramdisk only works for 16.0.x
    if [[ $VERSION == 16.4* || $VERSION == 16.5* || $VERSION == 16.6* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2023SpringFCS/fullrestores/032-68311/B777E36E-32B8-4DEF-91CE-9909B04FD22D/iPhone10,3,iPhone10,6_16.4_20E247_Restore.ipsw"
        ramdisk_dmg="078-23800-379.dmg"
    elif [[ $VERSION == 16.1* || $VERSION == 16.2* || $VERSION == 16.3* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-92982/6DF106AB-8868-433F-8C3F-05D50785E81E/iPhone10,3,iPhone10,6_16.1_20B82_Restore.ipsw"
        ramdisk_dmg="078-64668-109.dmg"
    elif [[ $VERSION == 17.0* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-49474/5DF24914-F32D-4940-830F-3D8C8860A75B/iPad_64bit_TouchID_ASTC_17.0_21A329_Restore.ipsw"
        ramdisk_dmg="097-83622-002.dmg"
    elif [[ $VERSION == 17.1* || $VERSION == 17.2* || $VERSION == 17.3* ]]; then
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-07636/DBDB5860-91CF-4757-B7BD-6402D4445AF2/iPad_64bit_TouchID_ASTC_17.1_21B74_Restore.ipsw"
        ramdisk_dmg="097-22998-092.dmg"
    else
        ramdisk_ipsw_url="https://updates.cdn-apple.com/2022FallFCS/fullrestores/012-65861/0A0400A0-2174-4D49-91B7-43FC9DE24272/iPhone10,3,iPhone10,6_16.0_20A362_Restore.ipsw"
        ramdisk_dmg="098-08863-001.dmg"
    fi
    ( cd work && sudo ../bin/pzb -g $ramdisk_dmg $ramdisk_ipsw_url )
    ./bin/img4 -i work/$ramdisk_dmg -o work/ramdisk2.raw
    ramdisk2_fs=$(detect_fs_type work/ramdisk2.raw)
    if [[ $ramdisk2_fs == "APFS" ]]; then
        mkdir -p work/rdmnt2
        apfs_mount work/ramdisk2.raw work/rdmnt2 ro
        cp -v work/rdmnt2/usr/local/bin/restored_external work/restored_external
        apfs_umount work/rdmnt2
    elif [[ $ramdisk2_fs == "HFS" ]]; then
        ./bin/hfsplus work/ramdisk2.raw extract usr/local/bin/restored_external work/restored_external
    else
        echo "[!] restored_external ramdisk 中的文件系统无法识别（work/${ramdisk_dmg}）。"
        echo "预期的是 HFS+ 或 APFS 文件系统。为安全起见中止。"
        exit 1
    fi
    ./bin/restoredpatcher work/restored_external work/restored_patch -c # patch cryptex1 install validation
    ./bin/ldid -e work/restored_external > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/restored_patch
    if [[ $ramdisk_fs == "APFS" ]]; then
        rm -rf work/rdmnt/usr/local/bin/restored_external
        cp -v work/restored_patch work/rdmnt/usr/local/bin/restored_external
        chmod 755 work/rdmnt/usr/local/bin/restored_external
        apfs_umount work/rdmnt
        # linux-apfs-rw write support is experimental and can silently corrupt a
        # container, so verify the patched files are readable and byte-identical
        # before packing the ramdisk; abort with an actionable error if not.
        mkdir -p work/rdmnt3
        apfs_mount work/ramdisk.raw work/rdmnt3 ro
        cp -v work/rdmnt3/usr/sbin/asr work/asr_verify
        cp -v work/rdmnt3/usr/lib/libimg4.dylib work/libimg4_verify
        cp -v work/rdmnt3/usr/local/bin/restored_external work/restored_verify
        apfs_umount work/rdmnt3
        if ! cmp -s work/asr_verify work/asr_patched || \
           ! cmp -s work/libimg4_verify work/libimg4.patch || \
           ! cmp -s work/restored_verify work/restored_patch; then
            echo "[!] 写入后 APFS ramdisk 校验失败。"
            echo "linux-apfs-rw 的写入可能已损坏该容器。"
            echo "ramdisk 尚未打包；请检查 'dmesg | grep -i apfs' 并重新运行。"
            exit 1
        fi
        echo "APFS ramdisk 写入校验通过。"
    else
        ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/restored_external
        ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/restored_external
        ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/restored_external
    fi
    # restored end
    ./bin/img4 -i tmp1/Firmware/$ramdisk_dmg_name.trustcache -o work/trustcache.raw
    ./bin/trustcache append work/trustcache.raw work/restored_patch
    ./bin/trustcache append work/trustcache.raw work/asr_patched
    ./bin/trustcache append work/trustcache.raw work/libimg4.patch
    ./bin/img4 -i work/trustcache.raw -o tmp2/Firmware/$ramdisk_dmg_name_18.trustcache -A -T rtsc
    # pack rdsk into im4p
    ./bin/img4 -i work/ramdisk.raw -o $restore_ramdisk_dmg_18 -A -T rdsk
fi
cd tmp2
zip -0 -r ../custom.ipsw *
cd ..
rm -rf "tmp1"
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
rm -rf "work"
if [[ $dist == 1 || $dist == 2 || $dist == 5 ]] && [[ $VERSION != 16.0* ]]; then
    # only needed on linux
    sudo rmmod apfs
fi

}

make_custom_ipsw_a12_ios14(){

IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
mkdir -p restorefiles/$IDENTIFIER/$VERSION
mkdir -p boot/$IDENTIFIER/$VERSION
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
mkdir -p work
# iBSS patching of course because yes
if [[ $VERSION == 14.0 ]] && [[ $BUILD != 18A373 ]] && [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* ]]; then
    if [[ $IDENTIFIER == iPhone11,8 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46828/6A00C15C-8AEB-490E-A468-04E28C68E7C9/iPhone11,8,iPhone12,1_14.0_18A373_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46850/8A4DA7D0-40E1-4079-A159-5B0983102B66/iPhone11,2,iPhone11,4,iPhone11,6,iPhone12,3,iPhone12,5_14.0_18A373_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad11,1 || $IDENTIFIER == iPad11,2 || $IDENTIFIER == iPad11,3 || $IDENTIFIER == iPad11,4 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46551/EFCA25AF-50BE-4712-A9C2-1E760AD99B82/iPad_Spring_2019_14.0_18A373_Restore.ipsw"
    fi
    ( cd work && sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url )
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBoot64Patcher2 work/iBSS.raw boot/$IDENTIFIER/iBSS.patch 
    ./bin/iBoot64Patcher2 work/iBSS.raw work/iBSS.patchboot -b "-v"
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
elif [[ $VERSION == 14.5* || $VERSION == 14.6* || $VERSION == 14.7* || $VERSION == 14.8* ]] && [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* ]]; then
    if [[ $IDENTIFIER == iPhone11,8 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2021WinterFCS/fullrestores/071-22451/5C8BBEE0-8471-4801-8D85-54D33DEDA50D/iPhone11,8,iPhone12,1_14.4.2_18D70_Restore.ipsw"
    elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2021WinterFCS/fullrestores/071-22729/77571761-8A7F-4F67-BB19-12D9BC82405B/iPhone11,2,iPhone11,4,iPhone11,6,iPhone12,3,iPhone12,5_14.4.2_18D70_Restore.ipsw"
    elif [[ $IDENTIFIER == iPad11,1 || $IDENTIFIER == iPad11,2 || $IDENTIFIER == iPad11,3 || $IDENTIFIER == iPad11,4 ]]; then
        ipsw_url="https://updates.cdn-apple.com/2021WinterFCS/fullrestores/071-22329/CF450435-1EDC-4212-A768-D666A1677EC5/iPad_Spring_2019_14.4.2_18D70_Restore.ipsw"
    fi
    ( cd work && sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url )
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBoot64Patcher2 work/iBSS.raw boot/$IDENTIFIER/iBSS.patch 
    ./bin/iBoot64Patcher2 work/iBSS.raw work/iBSS.patchboot -b "-v"
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
elif [[ $VERSION == 15.* ]]; then
    ./bin/img4 -i tmp1/Firmware/dfu/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBootPatch work/iBSS.raw boot/$IDENTIFIER/iBSS.patch
    ./bin/iBootPatch -v -b "-v" work/iBSS.raw work/iBSS.patchboot 
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
elif [[ $VERSION == 14.* ]] && [[ $IDENTIFIER == iPhone12* ]]; then
    # use different patch method for A13 iOS 14. use updated iBootPatch
    ./bin/img4 -i tmp1/Firmware/dfu/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBootPatch work/iBSS.raw boot/$IDENTIFIER/iBSS.patch
    ./bin/iBootPatch -v -b "-v" work/iBSS.raw work/iBSS.patchboot
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
else
    ./bin/img4 -i tmp1/Firmware/dfu/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/iBoot64Patcher2 work/iBSS.raw boot/$IDENTIFIER/iBSS.patch
    ./bin/iBoot64Patcher2 work/iBSS.raw work/iBSS.patchboot -b "-v"
    ./bin/iBootpatch2 work/iBSS.patchboot boot/$IDENTIFIER/$VERSION/iBSS.boot
    ./bin/img4 -i boot/$IDENTIFIER/iBSS.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
fi
#
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* ]] && [[ $BUILD != 18A5342e ]]; then
    # update rd stuff
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 1073741824)
    restored="restored_update"
elif [[ $IDENTIFIER == iPhone12* ]] && [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    # update rd stuff
    restore_ramdisk_dmg=$(find_dmg tmp1 largest 1073741824)
    restored="restored_update"
else
    restore_ramdisk_dmg=$(find_dmg tmp1 smallest)
    restored="restored_external"
fi
if [[ $LATEST_VERSION == 18.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 179000000)
elif [[ $LATEST_VERSION == 27.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 244000000)
elif [[ $LATEST_VERSION == 26.* ]]; then
    restore_ramdisk_dmg_18=$(find_dmg tmp2 largest 232784000)
fi
fs_dmg_18=$(find_dmg_arm64e tmp2 largest)
fs_dmg=$(find_dmg tmp1 largest)
fs_dmg_name=${fs_dmg##*/}
fs_dmg_18_name=${fs_dmg_18##*/}
ramdisk_dmg_name_18=${restore_ramdisk_dmg_18##*/}
ramdisk_dmg_name=${restore_ramdisk_dmg##*/}
if [[ $IDENTIFIER == iPhone12,8 || $IDENTIFIER == iPhone12,1 || $IDENTIFIER == iPhone11,8 || $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPad11,1 ]]; then
    IDENTITY="0"
elif [[ $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone12,5 || $IDENTIFIER == iPad11,2 ]]; then
    IDENTITY="1"
elif [[ $IDENTIFIER == iPhone11,6 || $IDENTIFIER == iPad11,3 ]]; then
    IDENTITY="2"
elif [[ $IDENTIFIER == iPad11,4 ]]; then
    IDENTITY="3"
fi
sudo KERNEL2="$KERNEL2" IDENTITY="$IDENTITY" python3 <<'PY'
import os
import plistlib

with open("tmp2/BuildManifest.plist", "rb") as f:
    plist = plistlib.load(f)

identity = int(os.environ["IDENTITY"])

plist["BuildIdentities"][identity]["Manifest"]["KernelCache"]["Info"]["Path"] = os.environ["KERNEL2"]

with open("tmp2/BuildManifest.plist", "wb") as f:
    plistlib.dump(plist, f)
PY
cp -v tmp1/Firmware/AOP/$AOP14 tmp2/Firmware/AOP/$AOP
cp -v tmp1/Firmware/agx/$GFX tmp2/Firmware/agx/$GFX
cp -v tmp1/Firmware/ane/$ANE tmp2/Firmware/ane/$ANE
cp -v tmp1/Firmware/isp_bni/$ISP tmp2/Firmware/isp_bni/$ISP
if [[ $IDENTIFIER == iPhone* ]]; then
    cp -v tmp1/Firmware/$CALLAN tmp2/Firmware/$CALLAN
    cp -v tmp1/Firmware/WirelessPower/$WIRELESS tmp2/Firmware/WirelessPower/$WIRELESS
fi
if [[ ($IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12*) &&
      $IDENTIFIER != iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$HAPTICASSET tmp2/Firmware/$HAPTICASSET
fi
cp -v tmp1/Firmware/all_flash/$DEVICETREE tmp2/Firmware/all_flash/$DEVICETREE
if [[ $VERSION == 13.* ]]; then
    cp -v tmp1/Firmware/$IOFW13 tmp2/Firmware/$IOFW
    cp -v tmp1/Firmware/ave/$AVE13 tmp2/Firmware/ave/$AVE
else
    cp -v tmp1/Firmware/$IOFW tmp2/Firmware/$IOFW
    cp -v tmp1/Firmware/ave/$AVE tmp2/Firmware/ave/$AVE
    cp -v tmp1/Firmware/$fs_dmg_name.root_hash tmp2/Firmware/$fs_dmg_18_name.root_hash 
    cp -v tmp1/Firmware/$fs_dmg_name.mtree tmp2/Firmware/$fs_dmg_18_name.mtree 
fi
if [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPhone12* ]]; then
    echo "使用最新的 MTFW"
elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
    echo "使用最新的 MTFW"
else
    cp -v tmp1/Firmware/$MTFW tmp2/Firmware/$MTFW # copy MTFW for target iOS
fi
if [[ ($IDENTIFIER == iPhone12*) &&
      $IDENTIFIER != iPhone12,8 ]]; then
    cp -v tmp1/Firmware/$LEAPHAPTIC tmp2/Firmware/$LEAPHAPTIC
    cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
fi
if [[ $IDENTIFIER == iPhone12* ]]; then
    cp -v tmp1/Firmware/pmp/$PMP tmp2/Firmware/pmp/$PMP
fi
cp -v $fs_dmg $fs_dmg_18 # replace rootfs in the IPSW
cp -v tmp1/Firmware/$fs_dmg_name.trustcache tmp2/Firmware/$fs_dmg_18_name.trustcache 
cp -v tmp1/Firmware/$ramdisk_dmg_name.trustcache tmp2/Firmware/$ramdisk_dmg_name_18.trustcache
./bin/img4 -i tmp1/$KERNEL -o work/kernel.raw
if [[ $VERSION == 14.* ]]; then
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -b # use kernel64patcher3, properly patch trust evaluation check on ios 14 arm64e
elif [[ $VERSION == 13.* ]]; then
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -b13 -n # make booting take less time (added -b13 to hopefully fix haptics issue)
else
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernelboot.patch -e -o -r -we
fi
./bin/kerneldiff work/kernel.raw work/kernelboot.patch work/kernelboot.diff
rm -rf tmp2/$KERNEL
./bin/img4 -i tmp1/$KERNEL -o tmp2/$KERNEL2 -T krnl -J -P work/kernelboot.diff || true
./bin/KPlooshFinder work/kernel.raw work/kernel.patch
./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
./bin/img4 -i tmp1/$KERNEL -o tmp2/$KERNEL -T krnl -J -P work/kernel.diff || true
./bin/img4 -i $restore_ramdisk_dmg -o work/ramdisk.raw
./bin/hfsplus work/ramdisk.raw extract usr/sbin/asr work/asr
./bin/asr64_patcher work/asr work/asr_patched
./bin/ldid -e work/asr > work/ents.plist
./bin/ldid -Swork/ents.plist work/asr_patched
./bin/hfsplus work/ramdisk.raw rm usr/sbin/asr 
./bin/hfsplus work/ramdisk.raw add work/asr_patched usr/sbin/asr
./bin/hfsplus work/ramdisk.raw chmod 100755 usr/sbin/asr
if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    ./bin/hfsplus work/ramdisk.raw extract usr/lib/libimg4.dylib work/libimg4.dylib
    ./bin/libimg4_patcher work/libimg4.dylib work/libimg4.patch
    ./bin/ldid -Swork/ents.plist work/libimg4.patch
    ./bin/hfsplus work/ramdisk.raw rm usr/lib/libimg4.dylib 
    ./bin/hfsplus work/ramdisk.raw add work/libimg4.patch usr/lib/libimg4.dylib
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/lib/libimg4.dylib
fi
if [[ $VERSION == 15.* ]]; then
    if [[ $restored == "restored_update" ]]; then
        ramdisk_download_name="018-80166-001.dmg"
    else
        ramdisk_download_name="018-79907-001.dmg"
    fi
    ramdisk_url="https://updates.cdn-apple.com/2021FallFCS/fullrestores/002-02910/AF984499-D03A-43E7-9472-6D16BA756E5E/iPhone10,3,iPhone10,6_15.0_19A346_Restore.ipsw"
elif [[ $VERSION == 13.* ]]; then
    if [[ $restored == "restored_update" ]]; then
        ramdisk_download_name="048-96454-001.dmg"
    else
        ramdisk_download_name="048-96245-001.dmg"
    fi
    ramdisk_url="https://updates.cdn-apple.com/2019FallFCS/fullrestores/061-08721/B905C96C-C875-11E9-8C18-F4CC329DFA63/iPhone10,3,iPhone10,6_13.0_17A577_Restore.ipsw"
else
    if [[ $restored == "restored_update" ]]; then
        ramdisk_download_name="048-58813-634.dmg"
    else
        ramdisk_download_name="048-58904-639.dmg"
    fi
    ramdisk_url="https://updates.cdn-apple.com/2020SummerFCS/fullrestores/001-46617/B62CA88B-EB85-4A5A-9440-7E0B90B02006/iPhone10,3,iPhone10,6_14.0_18A373_Restore.ipsw"
fi
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* ]] && [[ $IDENTIFIER != iPhone12,8 ]]; then
    sudo ./bin/pzb -g $ramdisk_download_name $ramdisk_url
    ./bin/img4 -i $ramdisk_download_name -o work/ramdisk2.raw
    sudo rm -rf $ramdisk_download_name
    ./bin/hfsplus work/ramdisk2.raw extract usr/local/bin/$restored work/restored_external
    ./bin/ipx_restored_patcher work/restored_external work/restored_patch
    ./bin/ldid -e work/restored_external > work/ents.plist
    ./bin/ldid -Swork/ents.plist work/restored_patch
    ./bin/hfsplus work/ramdisk.raw rm usr/local/bin/$restored
    ./bin/hfsplus work/ramdisk.raw add work/restored_patch usr/local/bin/$restored
    ./bin/hfsplus work/ramdisk.raw chmod 100755 usr/local/bin/$restored
fi
if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    ./bin/img4 -i tmp1/Firmware/$ramdisk_dmg_name.trustcache -o work/trustcache.raw
    if [[ $IDENTIFIER != iPhone12,8 ]]; then
        ./bin/trustcache append work/trustcache.raw work/restored_patch
    fi
    ./bin/trustcache append work/trustcache.raw work/asr_patched
    ./bin/trustcache append work/trustcache.raw work/libimg4.patch
    ./bin/img4 -i work/trustcache.raw -o tmp2/Firmware/$ramdisk_dmg_name_18.trustcache -A -T rtsc
fi
# pack rdsk into im4p
./bin/img4 -i work/ramdisk.raw -o $restore_ramdisk_dmg_18 -A -T rdsk
cd tmp2
zip -0 -r ../custom.ipsw *
cd ..
rm -rf "tmp1"
rm -rf "tmp2"
mv -v custom.ipsw $restoredir/custom.ipsw
rm -rf "work"

}

just_boot(){

if [[ ! -f boot/$ECID.txt ]]; then
    read -p "输入你想启动的版本：" VERSION
else
    VERSION=$(cat boot/$ECID.txt) 
fi
bootdir="boot/$IDENTIFIER/$VERSION"
if [[ ! -d $bootdir ]]; then
    echo "请先对 iOS $VERSION 进行有线恢复，然后再次尝试有线启动。"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* || $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi
pwn_device

sleep 5

echo "正在发送 iBSS"
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
    if [[ ! -s bin/liter8ctl ]]; then
        curl -L -o bin/liter8ctl https://github.com/ahmadkamal09999-tech/usbliter8/raw/refs/heads/main/usbliter8ctl || true
    fi
    if [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
        python3 bin/liter8ctl boot $bootdir/iBSS.boot || true
        echo "如果你看到错误：No such device（设备可能已断开连接）"
        echo "只要设备在发送 iBSS 后确实开始启动，这个错误在 Linux 上就是正常的。"
    else
        python3 bin/liter8ctl boot $bootdir/iBSS.boot
    fi
    echo "设备现在应该可以启动"
    exit 0
fi
./bin/irecovery -f $bootdir/iBSS.img4
if [[ $IDENTIFIER == iPhone10* ]]; then
    echo "设备现在应该可以启动"
    exit 0
fi
sleep 5
echo "正在发送 iBEC"
./bin/irecovery -f $bootdir/iBEC.img4
sleep 5
echo "正在发送 DeviceTree"
./bin/irecovery -f $bootdir/DeviceTree.img4
./bin/irecovery -c devicetree
if [[ $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.* ]]; then
    echo "正在发送 trustcache"
    ./bin/irecovery -f $bootdir/Trustcache.img4
    ./bin/irecovery -c firmware
fi
echo "正在发送 Kernelcache"
./bin/irecovery -f $bootdir/Kernelcache.img4
./bin/irecovery -c bootx
echo "设备现在应该可以启动"
exit 0

}

prepare_boot_files(){

rm -rf "work"
if [[ $IDENTIFIER == iPhone10,1 || $IDENTIFIER == iPhone10,4 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87486/23310DA1-A434-4192-87BC-31429FD2D625/iPhone_4.7_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,2 || $IDENTIFIER == iPhone10,5 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87451/EE6AEB4B-1BF7-4FBF-9D29-A8C7B970B495/iPhone_5.5_P3_14.3_18C66_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone10,3 || $IDENTIFIER == iPhone10,6 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2020WinterFCS/fullrestores/001-87865/458334F5-D8E1-498A-A9FD-08BBD20FE007/iPhone10,3,iPhone10,6_14.3_18C66_Restore.ipsw"
fi
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
bootdir="boot/$IDENTIFIER/$VERSION"
if [[ $VERSION == 10.2* || $VERSION == 10.1* ]]; then
    krnl="$KERNEL10"
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS10" -d work
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC10" -d work
    unzip -j "$IPSW_PATH" "Firmware/all_flash/$ALLFLASH/$DEVICETREE" -d work
    ./bin/img4 -i work/$IBSS10 -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC10 -o work/iBEC.raw -k $IBEC_KEY
else
    krnl="$KERNEL"
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS" -d work
    unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC" -d work
    unzip -j "$IPSW_PATH" "Firmware/all_flash/$DEVICETREE" -d work
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.0 ]]; then # just for 14.0 beta 4 restore
        ( cd work && sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url && sudo ../bin/pzb -g Firmware/dfu/$IBEC $ipsw_url )
    fi
    ./bin/img4 -i work/$IBSS -o work/iBSS.raw -k $IBSS_KEY
    ./bin/img4 -i work/$IBEC -o work/iBEC.raw -k $IBEC_KEY
fi
if [[ $VERSION == 10.* || $VERSION == 11.* || $VERSION == 12.* ]]; then
    ibootpatcher="kairos"
else
    ibootpatcher="iBoot64Patcher"
fi
rm -rf "$bootdir"
mkdir -p boot/$IDENTIFIER/$VERSION
if [[ $VERSION == 12.* || $VERSION == 13.* || $VERSION == 14.* || $VERSION == 15.* ]]; then
    unzip -j "$IPSW_PATH" "Firmware/*.dmg.trustcache" -d work
    trustcache_use=$(ls -S work/*.trustcache 2>/dev/null | head -n 1)
    ./bin/img4 -i $trustcache_use -o $bootdir/Trustcache.img4
fi
unzip -j "$IPSW_PATH" "$krnl" -d work
./bin/$ibootpatcher work/iBSS.raw work/iBSS.patch
./bin/$ibootpatcher work/iBEC.raw work/iBEC.patch -b "-v" 
if [[ $IDENTIFIER == iPhone10* ]]; then
    ./bin/iBoot64Patcher work/iBSS.raw work/iBSS.patch -l -b "-v"
fi
./bin/img4 -i work/iBSS.patch -o $bootdir/iBSS.img4 -A -T ibss -M $im4m
./bin/img4 -i work/iBEC.patch -o $bootdir/iBEC.img4 -A -T ibec -M $im4m
./bin/img4 -i work/$DEVICETREE -o $bootdir/DeviceTree.img4 -T rdtr -M $im4m
./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m
if [[ $VERSION == 14.* ]] && [[ $IDENTIFIER == iPad5* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher work/kernel.raw work/kernel.patch -b
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
elif [[ $VERSION == 15.* ]] && [[ $IDENTIFIER == iPad5* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher work/kernel.raw work/kernel.patch -e -o -r -b15
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
elif [[ $VERSION == 13.* ]] && [[ $IDENTIFIER == iPad5* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher work/kernel.raw work/kernel.patch -b13 -n
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
fi
if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 11.* || $VERSION == 12.* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    if [[ $VERSION == 12.* ]]; then
        ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 12 --skip-sks --skip-acm --skip-amfi
    else
        ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 11 --skip-sks --skip-acm --skip-amfi
    fi
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
fi
if [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.* ]]; then
    ./bin/img4 -i work/$krnl -o work/kernel.raw
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 11 --skip-sks --skip-acm --skip-amfi
    ./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
    ./bin/img4 -i work/$krnl -o $bootdir/Kernelcache.img4 -T rkrn -M $im4m -P work/kernel.diff -J || true
fi
echo "启动文件已成功创建！假设恢复已成功，你现在可以启动设备了。"

}

do_tethered_restore(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "未选择 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW 不存在：$IPSW_PATH"
    exit 1
fi
if [[ -z "$IPSW_PATH_LATEST" ]]; then
    echo "未选择最新 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH_LATEST" ]]; then
    echo "最新 IPSW 不存在：$IPSW_PATH_LATEST"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.3* || $VERSION == 14.4* || $VERSION == 14.5* || $VERSION == 14.6* || $VERSION == 14.7* || $VERSION == 14.8* || $VERSION == 15.* ]]; then
    echo "SEP 部分不兼容，请阅读以下内容："
    echo "恢复后设备将无法激活。"
    echo "你需要先有线恢复至 14.0 测试版 4，激活设备，然后有线恢复至目标版本。"
    echo "在 TrollStore 之外侧载可能可用也可能不可用，效果因人而异。"
    echo "以及其他可能损坏的功能"
    echo "由于强制启用了 BPR，你无法设置密码或使用 Touch ID"
    read -p "按回车继续"
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    echo "此恢复后你的设备可能会出现深度睡眠问题"
    read -p "按回车继续"
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 13.* ]]; then
    echo "此恢复后你的设备可能会出现深度睡眠问题"
    echo "Touch ID 将无法工作"
    read -p "按回车继续"
elif [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 12.* || $VERSION == 11.4* || $VERSION == 11.3* ]]; then
    echo "Touch ID 将无法工作"
    if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 12.* ]]; then
        echo "USB 配件将无法使用"
        echo "此恢复后你的设备可能会出现深度睡眠问题"
    fi
    read -p "按回车继续"
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPhone7* ]] && [[ $VERSION == 10.* ]]; then
    echo "Touch ID 将无法工作"
    read -p "按回车继续"
fi

if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.0* || $VERSION == 14.1* || $VERSION == 14.2* ]] && [[ $BUILD != 18A5342e ]]; then
    echo "不支持 14.2 及更低的降级，但 14.0 测试版 4 除外"
    if [[ $VERSION == 13.* || $VERSION == 12.* || $VERSION == 11.* ]]; then
        echo "此外，14.3 iBoot 变通方法在 13.x 及更低版本上无效。SEP 完全不兼容"
    fi
    exit 1
fi
if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4* ]] && [[ $VERSION == 10.3.3 ]] && [[ $BUILD == 14G60 ]]; then
    echo "此设备不支持 10.3.3 有线降级。"
    if [[ $IDENTIFIER == iPad4,6 ]]; then
        echo "10.3.3 对这台设备也已不再 OTA 签名，因此如果没有保存的 blob，你将无法恢复至 10.3.3"
    fi
    exit 1
fi
if [[ $IDENTIFIER == iPad4,6 || $IDENTIFIER == iPad4,7 || $IDENTIFIER == iPad4,8 || $IDENTIFIER == iPad4,9 || $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]] && [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.* || $VERSION == 11.0* || $VERSION == 11.1* || $VERSION == 11.2* ]]; then
    echo "SEP 不兼容"
    exit 1
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPod7* || $IDENTIFIER == iPhone7* || $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 ]] && [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* || $VERSION == 10.0* || $VERSION == 11.0* || $VERSION == 11.1* || $VERSION == 11.2* ]]; then
    echo "SEP 不兼容"
    exit 1
fi

if [[ $IDENTIFIER == iPad5* ]] && [[ $VERSION == 13.1* || $VERSION == 13.2* || $VERSION == 13.3* ]]; then
    echo "不支持 13.4 以下的 13.x 恢复"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION != 16.6* ]] && [[ $BUILD == 20* ]]; then
    echo "不支持 iOS 16.0-16.5.1 的恢复"
    echo "并且不支持 iOS 16.7.x 的恢复"
    exit 1
elif [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 16.6* ]]; then
    echo "你在恢复时会遇到一些问题："
    echo "iMessage/SMS 可能无法使用"
    echo "VPN 可能无法使用，还可能有其他问题。"
    read -p "按回车继续"
fi

if [[ $VERSION == 11.* ]] && [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]]; then
    echo "surrealra1n $CURRENT_VERSION 尚不支持 A8X iOS 11 降级"
    exit 1
fi

if [[ $IDENTIFIER == iPhone10* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi
pwn_device
det_rsep_flag
echo "正在获取 iOS $LATEST_VERSION 的 shsh blob"
rm -rf "shsh"
mkdir -p shsh
mkdir -p boot
ECID=$(./bin/irecovery -q 2>/dev/null | grep "^ECID:" | cut -d ':' -f2 | xargs) || true
echo "$VERSION" > boot/$ECID.txt
ensure_firmwares_json
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh

# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "在 shsh 文件夹中未找到 SHSH 文件。中止"
    exit 1
fi

restoredir="restorefiles/$IDENTIFIER/$VERSION"

if [[ ! -f "$restoredir/custom.ipsw" ]] && [[ ! -f "$restoredir/ramdisk.im4p" ]] && [[ ! -f "$restoredir/kernel.im4p" ]]; then
    echo "恢复文件不存在，正在生成新的"
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 16.* ]]; then
        make_custom_ipsw_ios16
    else
        make_custom_ipsw
    fi
else
    echo "恢复文件已存在"
    read -p "你是否要生成新的？（y/n）：" restorefiles_remake
    restorefiles_remake="${restorefiles_remake//[$'\r']/}"
    if [[ $restorefiles_remake == Y || $restorefiles_remake == y ]]; then
        rm -rf "$restoredir"
        if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 16.* ]]; then
            make_custom_ipsw_ios16
        else
            make_custom_ipsw
        fi
    fi
fi

if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5* || $IDENTIFIER == iPod7* ]] && [[ $VERSION == 10.* ]]; then
    download_tvos_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path --skip-blob --rdsk $restoredir/ramdisk.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad4* || $IDENTIFIER == iPhone6* ]] && [[ $VERSION == 10.* ]]; then
    download_1033_ota_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path --skip-blob --rdsk $restoredir/ramdisk.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
elif [[ $IDENTIFIER == iPad5,1 || $IDENTIFIER == iPad5,2 ]] && [[ $VERSION == 11.* || $VERSION == 12.* ]]; then
    download_iphone6_sep
    prepatch_ibssibec_fr
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
            --sep $sep_path --sep-manifest $manifest_path --skip-blob --rdsk $restoredir/ramdisk.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
else
    prepatch_ibssibec_fr
    if [[ $IDENTIFIER == iPhone10* ]] && [[ $VERSION == 14.* || $VERSION == 15.* ]] && [[ $BUILD != 18A5342e ]]; then
        ramdisk_det="updateramdisk"
    else
        ramdisk_det="ramdisk"
    fi
    while true; do
        set +e
        sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
            ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu --skip-blob --rdsk $restoredir/$ramdisk_det.im4p \
            --custom-latest $LATEST_VERSION \
            --rkrn $restoredir/kernel.im4p --latest-sep \
            $updatebb_flag $rsep_flag $restoredir/custom.ipsw
        EXIT_CODE=$?
        set -e
        if [[ $EXIT_CODE -eq 139 ]]; then
            echo "futurerestore 段错误（退出码 139），正在重试..."
            sleep 2
        else
            break
        fi
    done
fi

echo "恢复已完成！如有任何错误，请查看上方输出"
prepare_boot_files
exit 0

}

fetch_blobs_a12_a13_prep(){
# this function isn't needed but ill keep it
mkdir -p work
if [[ $IDENTIFIER == iPhone12,8 ]]; then
    latest_url="https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-93803/1454C0E0-B7A3-4863-BE7A-6A4E8FF166F0/iPhone12,8_26.6.1_23G83_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone12,5 ]]; then
    latest_url="https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-93806/8CC6D313-C474-41E5-973C-E4DCF7E127FF/iPhone12,3,iPhone12,5_26.6.1_23G83_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone12,1 ]]; then
    latest_url="https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-75024/5CBDD6F3-E1AB-41C5-8DC1-8FB137A75E9E/iPhone12,1_26.6.1_23G83_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone11,8 ]]; then
    latest_url="https://updates.cdn-apple.com/2026WinterFCS/fullrestores/140-97953/5F3051CD-5405-4FEF-889E-C3B78E0F376F/iPhone11,8_18.7.10_22H374_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
    latest_url="https://updates.cdn-apple.com/2026WinterFCS/fullrestores/140-97977/CB8B320D-008B-4FC2-8256-56A1DB86C586/iPhone11,2,iPhone11,4,iPhone11,6_18.7.10_22H374_Restore.ipsw"
elif [[ $IDENTIFIER == iPad11* ]]; then
    latest_url="https://updates.cdn-apple.com/2026SummerFCS/fullrestores/140-75126/51E6CF98-E76E-45CC-A0BF-978D0D210406/iPad_Spring_2019_26.6.1_23G83_Restore.ipsw"
fi
( cd work && sudo ../bin/pzb -g BuildManifest.plist $latest_url )

}

do_tethered_restore_a12_a13(){

# fix issue on Linux
if [[ $dist == 3 || $dist == 4 ]]; then
    if [[ $macos_ver == 12.* || $macos_ver == 13.* || $macos_ver == 14.* || $macos_ver == 15.* || $macos_ver == 26.* || $macos_ver == 27.* ]]; then
        echo ""
    else
        echo "A12/A13 降级仅在 macOS 12 及更高版本受支持。"
        exit 1
    fi
fi

if [[ -z "$IPSW_PATH" ]]; then
    echo "未选择 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW 不存在：$IPSW_PATH"
    exit 1
fi
if [[ -z "$IPSW_PATH_LATEST" ]]; then
    echo "未选择最新 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH_LATEST" ]]; then
    echo "最新 IPSW 不存在：$IPSW_PATH_LATEST"
    exit 1
fi

if [[ $IDENTIFIER == iPhone11,4 ]] && [[ $VERSION == 14.1* ]]; then
    echo "此设备不支持 14.1 降级"
    exit 1
fi

if [[ $VERSION == 14.* || $VERSION == 15.* ]]; then
    echo "SEP 部分不兼容，请阅读以下内容："
    echo "恢复后设备将无法激活。"
    echo "在 TrollStore 之外侧载可能可用也可能不可用，效果因人而异。"
    echo "以及其他可能损坏的功能"
    echo "由于强制启用了 BPR，你无法设置密码或使用 Touch ID"
    if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* ]]; then
        echo "你需要先有线恢复至 14.0 测试版 4，激活设备，然后有线恢复至目标版本。"
    elif [[ $IDENTIFIER == iPhone12* ]]; then
        echo "你需要先有线恢复至 iOS 13.4 - 13.7，激活设备（可能需要通过 Finder/iTunes/Legacy iOS Kit 激活），然后有线恢复至目标版本。"
        echo "如果你更希望使用 iOS 13 而不是 iOS 14/15，也可以保持 iOS 13。"
        echo "触觉主屏幕按钮将无法工作。"
    fi
    read -p "按回车继续"
elif [[ $VERSION == 16.* ]]; then
    echo "触觉主屏幕按钮将无法工作。"
    echo "由于强制启用了 BPR，你无法设置密码或使用 Touch ID"
    echo "由于 iOS 16 应能正常激活，因此无需前往 iOS 13.x 或 iOS 14.0 测试版 4。"
    echo "此恢复还会自动启用开发者模式，你无需手动启用。"
    if [[ $dist != 3 && $dist != 4 ]] && [[ $VERSION != 16.0* ]]; then
        echo ""
        echo "警告：Linux 上 iOS 16.1+ 的恢复是实验性的，请谨慎操作。"
        echo "此构建使用实验性的 linux-apfs-rw 内核修补 APFS 恢复 ramdisk"
        echo "模块。它没有像 macOS 实现那样经过同等程度的测试，而且"
        echo "失败或中断的恢复可能使设备需要恢复或重新恢复。"
        echo ""
        read -p "输入 YES 继续，输入其他任何内容则中止：" apfs_consent
        if [[ $apfs_consent != YES ]]; then
            echo "中止。"
            exit 1
        fi
    fi
    read -p "按回车继续"
elif [[ $VERSION == 17.* ]]; then
    echo "iOS 17.x 的支持确实是实验性的。"
    echo "你可能会遇到大量问题（包括某些设备上基带损坏），因为我们必须修补一些东西才能让设备启动。"
    echo "设备将无法激活。当你的设备无法激活时，请不要在 GitHub 上大量刷 issue。"
    echo "只有当你正在研究或想要为修复问题做出贡献时才应该这样做，这不适合普通用户。"
    read -p "按回车继续"
elif [[ $VERSION == 18.* || $VERSION == 26.* || $VERSION == 27.* ]]; then
    echo "目前不支持 iOS 18-27 的 A12/A13 降级"
    exit 1
elif [[ $VERSION == 13.* || $VERSION == 12.* ]] && [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPad11* ]]; then
    echo "SEP 不兼容"
    exit 1
elif [[ $VERSION == 13.4* || $VERSION == 13.5* || $VERSION == 13.6* || $VERSION == 13.7* ]] && [[ $IDENTIFIER == iPhone12* ]]; then
    echo "SEP 部分不兼容"
    echo "由于强制启用了 BPR，你无法设置密码或使用 Touch ID"
    echo "触觉主屏幕按钮将无法工作，AssistiveTouch 主屏幕按钮也不会出现"
    echo "在 iPhone 11 机型上，除 UWB、Face ID 和密码外基本能完全正常使用"
    read -p "按回车继续"
elif [[ $VERSION == 13.0* || $VERSION == 13.1* || $VERSION == 13.2* || $VERSION == 13.3* ]] && [[ $IDENTIFIER == iPhone12* ]]; then
    echo "SEP 不兼容"
    exit 1
fi

if [[ $IDENTIFIER == iPhone12,1 || $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone12,5 ]]; then
    echo "UWB 可能可用也可能不可用。"
    echo "这意味着：AirTags 等物品的精确查找功能。"
    sleep 6
fi

restoredir="restorefiles/$IDENTIFIER/$VERSION"

if [[ ! -f "$restoredir/custom.ipsw" ]]; then
    echo "恢复文件不存在，正在生成新的"
    if [[ $VERSION == 16.* || $VERSION == 17.* ]]; then
        make_custom_ipsw_a12_ios16
    else
        make_custom_ipsw_a12_ios14
    fi
else
    echo "恢复文件已存在"
    read -p "你是否要生成新的？（y/n）：" restorefiles_remake
    restorefiles_remake="${restorefiles_remake//[$'\r']/}"
    if [[ $restorefiles_remake == Y || $restorefiles_remake == y ]]; then
        rm -rf "$restoredir"
        if [[ $VERSION == 16.* || $VERSION == 17.* ]]; then
            make_custom_ipsw_a12_ios16
        else
            make_custom_ipsw_a12_ios14
        fi
    fi
fi
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi
pwn_device
det_rsep_flag
if [[ ! -s bin/liter8ctl ]]; then
    curl -L -o bin/liter8ctl https://github.com/ahmadkamal09999-tech/usbliter8/raw/refs/heads/main/usbliter8ctl || true
fi
if [[ $dist == 1 || $dist == 2 || $dist == 5 ]]; then
    python3 bin/liter8ctl boot boot/$IDENTIFIER/iBSS.patch || true
    echo "如果你看到错误：No such device（设备可能已断开连接）"
    echo "只要设备进入 iBSS 恢复模式，这个错误在 Linux 上是正常的（屏幕应保持黑屏，但会被识别为恢复模式设备）。"
elif [[ $macos_ver == 27.* || $macos_ver == 26.* || $macos_ver == 15.* || $macos_ver == 14.* || $macos_ver == 13.* || $macos_ver == 12.* ]]; then
    python3 bin/liter8ctl boot boot/$IDENTIFIER/iBSS.patch || true
    echo "usbliter8ctl 可能会出错。"
    echo "只要设备进入 iBSS 恢复模式，这个错误可能也是正常的（屏幕应保持黑屏，但会被识别为恢复模式设备）。"
else
    python3 bin/liter8ctl boot boot/$IDENTIFIER/iBSS.patch 
fi
sleep 6
echo "正在检查设备是否处于恢复模式"
MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
if [[ $MODE == Recovery ]]; then
    echo "已检测到设备处于恢复模式。"
else
    echo "未在恢复模式检测到设备。退出"
    exit 1
fi
APNONCE=$(./bin/irecovery -q 2>/dev/null | grep "^NONC:" | cut -d ':' -f2 | xargs) || true
ECID=$(./bin/irecovery -q 2>/dev/null | grep "^ECID:" | cut -d ':' -f2 | xargs) || true
mkdir -p boot
echo "$VERSION" > boot/$ECID.txt
if [[ $IDENTIFIER == iPhone12,8 ]]; then
    sudo LD_LIBRARY_PATH="lib" ./bin/idevicerestore -ey $restoredir/custom.ipsw
    echo "恢复已结束！如有任何错误，请查看上方输出"
    exit 0
elif [[ $VERSION == 16.* || $VERSION == 17.* ]] && [[ $IDENTIFIER != iPhone12,8 ]]; then
    sudo LD_LIBRARY_PATH="lib" ./bin/idevicerestore -ey $restoredir/custom.ipsw
    echo "恢复已结束！如有任何错误，请查看上方输出"
    exit 0
fi
echo "正在获取 iOS $LATEST_VERSION 的 shsh blob"
rm -rf "shsh"
mkdir -p shsh
ensure_firmwares_json
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh --apnonce $APNONCE
# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "在 shsh 文件夹中未找到 SHSH 文件。中止"
    exit 1
fi
# 离线方案：iPad5,3/5,4 的"最新 SEP"即 15.8.8 的 SEP，直接从 Base IPSW 本地提取，避免 futurerestore 联网查询 api.ipsw.me；
# 基带改用 --no-baseband（不刷基带，保留 15.8.8 基带固件；降级后蜂窝本就不可用）
if [[ $IDENTIFIER == iPad5,3 || $IDENTIFIER == iPad5,4 ]]; then
    mkdir -p tmp/sep_local
    unzip -j -o "$IPSW_PATH_LATEST" "BuildManifest.plist" -d tmp/sep_local >/dev/null
    unzip -j -o "$IPSW_PATH_LATEST" "Firmware/all_flash/sep-firmware.$BOARDID2.RELEASE.im4p" -d tmp/sep_local >/dev/null
    fr_sep_flags="--use-pwndfu --skip-blob --sep tmp/sep_local/sep-firmware.$BOARDID2.RELEASE.im4p --sep-manifest tmp/sep_local/BuildManifest.plist --no-baseband"
else
    fr_sep_flags="--latest-sep $updatebb_flag"
fi
while true; do
    set +e
    sudo ./futurerestore/futurerestore -t $SHSH_PATH $rsep_flag $fr_sep_flags $restoredir/custom.ipsw
    EXIT_CODE=$?
    set -e
    if [[ $EXIT_CODE -eq 139 ]]; then
        echo "futurerestore 段错误（退出码 139），正在重试..."
        sleep 2
    else
        break
    fi
done
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "恢复已完成！如有任何错误，请查看上方输出"
    exit 0
else
    echo "futurerestore 失败，退出码 $EXIT_CODE"
    exit 1
fi

}

prepare_seprmvr64_ipsw_legacy(){

if [[ $VERSION == 7.* ]]; then
    IBSS_2="$IBSS7"
    IBEC_2="$IBEC7"
else
    IBSS_2="$IBSS10"
    IBEC_2="$IBEC10"
fi
if [[ $VERSION == 9.* ]]; then
    ibootpatcher="kairos"
else
    ibootpatcher="ipatcher"
fi
if [[ $VERSION == 7.* ]]; then
    grow_to="2500000000"
elif [[ $VERSION == 8.* ]]; then
    grow_to="3200000000"
fi

if [[ $IDENTIFIER == iPad5* || $IDENTIFIER == iPhone7* || $IDENTIFIER == iPod7* || $VERSION == 7.0* ]]; then
    actrec_restore=1
else
    actrec_restore=0
fi

if [[ "$ECID" == 0x* || "$ECID" == 0X* ]]; then
    ECID_CLEAN="${ECID#0x}"
    ECID_CLEAN="${ECID_CLEAN#0X}"
    ECID_DEC=$(printf '%d' "0x$ECID_CLEAN")
else
    ECID_CLEAN="$ECID"
    ECID_DEC="$ECID"
fi


mkdir -p noseprestore/$IDENTIFIER/$VERSION
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
DTRE_KEY=$(grep "dtre-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
RDSK_KEY=$(grep "rdsk-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
KRNL_KEY=$(grep "krnl-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
ROOT_KEY=$(grep "fstm-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
unzip "$IPSW_PATH" -d tmp1
unzip "$IPSW_PATH_LATEST" -d tmp2
# ramdisk handling
smallestlatest_dmg=$(find_dmg tmp2 smallest)
rootfs_dmg=$(find_dmg tmp1 largest)
rootfslatest_dmg=$(find_dmg tmp2 largest)
if [[ $VERSION == 7.0* ]]; then
    smallest_dmg=$(find_dmg tmp1 largest 10370000)
else
    smallest_dmg=$(find_dmg tmp1 smallest)
fi
./bin/img4 -i tmp1/Firmware/dfu/$IBSS_2 -o tmp1/iBSS.raw -k $IBSS_KEY
./bin/img4 -i tmp1/Firmware/dfu/$IBEC_2 -o tmp1/iBEC.raw -k $IBEC_KEY
./bin/$ibootpatcher tmp1/iBSS.raw tmp1/iBSS.patch
./bin/$ibootpatcher tmp1/iBEC.raw tmp1/iBEC.patch -b "rd=md0 debug=0x2014e -v wdt=-1 nand-enable-reformat=1 -restore amfi=0xff cs_enforcement_disable=1"
./bin/img4 -i tmp1/iBSS.patch -o tmp2/Firmware/dfu/$IBSS -A -T ibss
./bin/img4 -i tmp1/iBEC.patch -o tmp2/Firmware/dfu/$IBEC -A -T ibec
./bin/img4 -i tmp1/Firmware/all_flash/$ALLFLASH/$DEVICETREE -o tmp1/DeviceTree.raw -k $DTRE_KEY
perl -pi -e 's/content-protect/content-protecV/g' tmp1/DeviceTree.raw
./bin/img4 -i tmp1/DeviceTree.raw -o tmp2/Firmware/all_flash/$DEVICETREE -A -T rdtr
./bin/img4 -i tmp1/$KERNEL10 -o tmp1/kernel.raw -k $KRNL_KEY
./bin/img4 -i tmp1/$KERNEL10 -o tmp1/kernel.im4p -k $KRNL_KEY -D
if [[ $VERSION == 7.* ]]; then
    ./bin/Kernel64Patcher2 tmp1/kernel.raw tmp1/kernel.patch -u 7 -m 7 -e 7 -f 7 -k
elif [[ $VERSION == 8.* ]]; then
    ./bin/Kernel64Patcher2 tmp1/kernel.raw tmp1/kernel.patch -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d
else
    ./bin/Kernel64Patcher2 tmp1/kernel.raw tmp1/kernel.patch -u 9 -f 9 -k -v
fi
./bin/kerneldiff tmp1/kernel.raw tmp1/kernel.patch tmp1/kernel.diff
./bin/img4 -i tmp1/kernel.im4p -o tmp2/$KERNEL -T rkrn -P tmp1/kernel.diff -J || true
./bin/img4 -i $smallest_dmg -o tmp1/ramdisk.raw -k $RDSK_KEY
./bin/hfsplus tmp1/ramdisk.raw grow 40000000
./bin/hfsplus tmp1/ramdisk.raw extract usr/sbin/asr tmp1/asr
./bin/asr64_patcher tmp1/asr tmp1/asr_patched
if [[ $VERSION == 8.* || $VERSION == 9.* ]]; then
    ./bin/ldid -e tmp1/asr > tmp1/ents.plist
    ./bin/ldid -Stmp1/ents.plist tmp1/asr_patched
fi
./bin/hfsplus tmp1/ramdisk.raw rm usr/sbin/asr
./bin/hfsplus tmp1/ramdisk.raw add tmp1/asr_patched usr/sbin/asr
./bin/hfsplus tmp1/ramdisk.raw chmod 100755 usr/sbin/asr
if [[ $IDENTIFIER == iPhone7* || $IDENTIFIER == iPad5* || $IDENTIFIER == iPod7* ]]; then
    ./bin/hfsplus tmp1/ramdisk.raw extract usr/local/bin/restored_external tmp1/restored_external
    ./bin/restoredpatcher tmp1/restored_external tmp1/restored_patch -b
    ./bin/ldid -e tmp1/restored_external > tmp1/ents.plist
    ./bin/ldid -Stmp1/ents.plist tmp1/restored_patch
    ./bin/hfsplus tmp1/ramdisk.raw rm usr/local/bin/restored_external
    ./bin/hfsplus tmp1/ramdisk.raw add tmp1/restored_patch usr/local/bin/restored_external
    ./bin/hfsplus tmp1/ramdisk.raw chmod 100755 usr/local/bin/restored_external
fi
./bin/img4 -i tmp1/ramdisk.raw -o $smallestlatest_dmg -A -T rdsk
rm -rf $rootfslatest_dmg
./bin/dmg extract $rootfs_dmg tmp1/rootfs.raw -k $ROOT_KEY
# dyld patches
if [[ $VERSION == 7.* ]]; then
    ./bin/hfsplus tmp1/rootfs.raw extract System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64 dyld.raw
    ./bin/dsc64patcher dyld.raw dyld.patch -7
    ./bin/hfsplus tmp1/rootfs.raw rm System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
    ./bin/hfsplus tmp1/rootfs.raw add dyld.patch System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
    rm -rf dyld.*
    ./bin/hfsplus tmp1/rootfs.raw chmod 755 System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
    ./bin/hfsplus tmp1/rootfs.raw chown 0:0 System/Library/Caches/com.apple.dyld/dyld_shared_cache_arm64
fi
if [[ $VERSION == 7.* || $VERSION == 8.* ]]; then
    ./bin/hfsplus tmp1/rootfs.raw grow $grow_to
fi
if [[ $VERSION == 9.* ]]; then
    echo "跳过移除 powerd"
else
    # Try and work around deep sleep issues without jailbreak
    echo "正在移除 powerd"
    ./bin/hfsplus tmp1/rootfs.raw rm System/Library/CoreServices/powerd.bundle/powerd
    ./bin/hfsplus tmp1/rootfs.raw rm System/Library/LaunchDaemons/com.apple.powerd.plist
    if [[ $VERSION == 7.0* ]] && [[ $IDENTIFIER == iPhone6* ]]; then
        # fixes
        ./bin/hfsplus tmp1/rootfs.raw rm usr/libexec/biometrickitd
        ./bin/hfsplus tmp1/rootfs.raw rm System/Library/LaunchDaemons/com.apple.biometrickitd.plist
    fi
fi
if [[ $actrec_restore == 1 ]]; then
    actsave_dir="activation_records/$ECID_DEC"
    if [[ $VERSION == 8.3* || $VERSION == 8.4* || $VERSION == 9.* ]]; then
        make_actdir="./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/mobile/Library/mad/activation_records"
        placetodir="./bin/hfsplus "tmp1/rootfs.raw" add $actsave_dir/activation_record.plist private/var/mobile/Library/mad/activation_records/activation_record.plist"
        chmodfile="./bin/hfsplus "tmp1/rootfs.raw" chmod 666 private/var/mobile/Library/mad/activation_records/activation_record.plist"
    else
        make_actdir="./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/root/Library/Lockdown/activation_records"
        placetodir="./bin/hfsplus "tmp1/rootfs.raw" add $actsave_dir/activation_record.plist private/var/root/Library/Lockdown/activation_records/activation_record.plist"
        chmodfile="./bin/hfsplus "tmp1/rootfs.raw" chmod 666 private/var/root/Library/Lockdown/activation_records/activation_record.plist"
    fi
    echo "正在创建目录..."
    $make_actdir
    ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/mobile/Library/FairPlay/iTunes_Control/iTunes
    ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/wireless
    ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/wireless/Library
    ./bin/hfsplus "tmp1/rootfs.raw" mkdir private/var/wireless/Library/Preferences
    echo "正在将激活文件注入 rootfs..."
    $placetodir
    ./bin/hfsplus "tmp1/rootfs.raw" add $actsave_dir/IC-Info.sisv private/var/mobile/Library/FairPlay/iTunes_Control/iTunes/IC-Info.sisv
    sudo ./bin/hfsplus "tmp1/rootfs.raw" add $actsave_dir/com.apple.commcenter.device_specific_nobackup.plist private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist
    echo "正在设置权限..."
    $chmodfile
    ./bin/hfsplus "tmp1/rootfs.raw" chmod 664 private/var/mobile/Library/FairPlay/iTunes_Control/iTunes/IC-Info.sisv
    ./bin/hfsplus "tmp1/rootfs.raw" chmod 600 private/var/wireless/Library/Preferences/com.apple.commcenter.device_specific_nobackup.plist

fi
if [[ $JAILBREAK == 1 ]] && [[ $VERSION == 7.* ]]; then
    if [[ $VERSION == 7.1* ]]; then
        untether="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/panguaxe.tar"
    elif [[ $VERSION == 7.0.* ]]; then
        untether="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/evasi0n7-untether.tar"
    elif [[ $VERSION == 7.0 ]]; then
        untether="https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/evasi0n7-untether-70.tar"
    fi
    curl -L -o tmp1/freeze.tar.gz https://github.com/LukeZGD/Legacy-iOS-Kit/raw/refs/heads/main/resources/jailbreak/freeze.tar.gz
    curl -L -o tmp1/untether.tar $untether
    gzip -d tmp1/freeze.tar.gz
    ./bin/hfsplus tmp1/rootfs.raw untar tmp1/freeze.tar
    ./bin/hfsplus tmp1/rootfs.raw untar tmp1/untether.tar
fi
./bin/dmg build tmp1/rootfs.raw $rootfslatest_dmg
cd tmp2
zip -0 -r ../$restoredir/$ipsw_custom *
cd ..
rm -rf "tmp1"
rm -rf "tmp2"

}

prepare_boot_files_seprmvr64(){

if [[ $VERSION == 7.* ]]; then
    IBSS_2="$IBSS7"
    IBEC_2="$IBEC7"
else
    IBSS_2="$IBSS10"
    IBEC_2="$IBEC10"
fi
if [[ $VERSION == 9.* ]]; then
    ibootpatcher="kairos"
else
    ibootpatcher="ipatcher"
fi
IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
IBEC_KEY=$(grep "ibec-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
DTRE_KEY=$(grep "dtre-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
KRNL_KEY=$(grep "krnl-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
bootdir="boot/$IDENTIFIER/$VERSION"
mkdir -p boot/$IDENTIFIER/$VERSION
unzip -j "$IPSW_PATH" "Firmware/dfu/$IBSS_2" -d work
unzip -j "$IPSW_PATH" "Firmware/dfu/$IBEC_2" -d work
unzip -j "$IPSW_PATH" "Firmware/all_flash/$ALLFLASH/$DEVICETREE" -d work
unzip -j "$IPSW_PATH" "$KERNEL10" -d work
./bin/img4 -i work/$IBSS_2 -o work/iBSS.raw -k $IBSS_KEY
./bin/img4 -i work/$IBEC_2 -o work/iBEC.raw -k $IBEC_KEY
./bin/img4 -i work/$DEVICETREE -o work/DeviceTree.im4p -k $DTRE_KEY -D
./bin/img4 -i work/$KERNEL10 -o work/kernel.raw -k $KRNL_KEY
./bin/img4 -i work/$KERNEL10 -o work/kernel.im4p -k $KRNL_KEY -D
./bin/$ibootpatcher work/iBSS.raw work/iBSS.patch
./bin/$ibootpatcher work/iBEC.raw work/iBEC.patch -b "-v"
./bin/img4 -i work/iBSS.patch -o $bootdir/iBSS.img4 -A -T ibss -M $im4m
./bin/img4 -i work/iBEC.patch -o $bootdir/iBEC.img4 -A -T ibec -M $im4m
./bin/img4 -i work/DeviceTree.im4p -o $bootdir/DeviceTree.img4 -T rdtr -M $im4m
if [[ $VERSION == 7.* ]]; then
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 7 -m 7 -e 7 -f 7 -k
elif [[ $VERSION == 8.* ]]; then
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 8 -t -p -e 8 -f 8 -a -m 8 -g -s -d
else
    ./bin/Kernel64Patcher2 work/kernel.raw work/kernel.patch -u 9 -f 9 -k -v
fi
./bin/kerneldiff work/kernel.raw work/kernel.patch work/kernel.diff
./bin/img4 -i work/kernel.im4p -o $bootdir/Kernelcache.img4 -T rkrn -P work/kernel.diff -J -M $im4m || true
rm -rf "work"
echo "启动文件已成功创建！假设恢复已成功，你现在可以启动设备了。"

}

do_tethered_seprmvr64_restore(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "未选择 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW 不存在：$IPSW_PATH"
    exit 1
fi
if [[ -z "$IPSW_PATH_LATEST" ]]; then
    echo "未选择最新 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH_LATEST" ]]; then
    echo "最新 IPSW 不存在：$IPSW_PATH_LATEST"
    exit 1
fi

echo "以下是 seprmvr64 恢复时可能发生的以下情况："
echo "1. Touch ID 将无法工作"
echo "2. 密码将无法工作"
echo "3. 受密码保护的 Wi-Fi 网络将无法使用"
echo "4. iOS 7/8 上电池续航可能会受影响，因为我们在那里使用了变通方法来避免深度睡眠崩溃"
echo "5. 其他可能损坏的功能"
if [[ $IDENTIFIER == iPad5,2 || $IDENTIFIER == iPad5,4 || $IDENTIFIER == iPhone7* ]]; then
    echo "6. 基带将无法工作。"
fi
read -p "按回车继续"

restoredir="noseprestore/$IDENTIFIER/$VERSION"
stitch_activation=0
if [[ "$ECID" == 0x* || "$ECID" == 0X* ]]; then
    ECID_CLEAN="${ECID#0x}"
    ECID_CLEAN="${ECID_CLEAN#0X}"
    ECID_DEC=$(printf '%d' "0x$ECID_CLEAN")
else
    ECID_CLEAN="$ECID"
    ECID_DEC="$ECID"
fi
if [[ $VERSION == 7.0* || $VERSION == 9.* ]]; then
    stitch_activation=1
fi
if [[ $JAILBREAK == 1 ]] && [[ $stitch_activation != 1 ]]; then
    ipsw_custom="customJB.ipsw"
elif [[ $JAILBREAK == 1 ]] && [[ $stitch_activation == 1 ]]; then
    ipsw_custom="customJB_$ECID_DEC.ipsw"
elif [[ $JAILBREAK != 1 ]] && [[ $stitch_activation == 1 ]]; then
    ipsw_custom="custom_$ECID_DEC.ipsw"
else
    ipsw_custom="custom.ipsw"
fi

if [[ $VERSION == 9.3* ]]; then
    echo "不支持 9.3.x 的恢复"
    exit 1
fi

if [[ ! -f "$restoredir/$ipsw_custom" ]]; then
    echo "恢复文件不存在，正在生成新的"
    if [[ $VERSION == 7.0* || $VERSION == 9.* ]]; then
        activation_records_check
        actrec_restore=1
    elif [[ $IDENTIFIER == iPad5* || $IDENTIFIER == iPhone7* || $IDENTIFIER == iPod7* ]]; then
        activation_records_check
        actrec_restore=1
    else
        actrec_restore=0
    fi
    prepare_seprmvr64_ipsw_legacy
else
    echo "恢复文件已存在"
    read -p "你是否要生成新的？（y/n）：" restorefiles_remake
    restorefiles_remake="${restorefiles_remake//[$'\r']/}"
    if [[ $restorefiles_remake == Y || $restorefiles_remake == y ]]; then
        rm -rf "$restoredir"
        prepare_seprmvr64_ipsw_legacy
    fi
fi

rm -rf "shsh"
mkdir -p shsh
ensure_firmwares_json
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh
# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "在 shsh 文件夹中未找到 SHSH 文件。中止"
    exit 1
fi
./bin/img4tool -s "$SHSH_PATH" -e -m "$IDENTIFIER-im4m"
im4m="$IDENTIFIER-im4m"

dfu_helper
pwn_device
sleep 5
ECID=$(./bin/irecovery -q 2>/dev/null | grep "^ECID:" | cut -d ':' -f2 | xargs) || true
mkdir -p boot
echo "$VERSION" > boot/$ECID.txt
sudo LD_LIBRARY_PATH="lib" ./bin/idevicerestore -ey $restoredir/$ipsw_custom
echo "恢复已结束！如有任何错误，请查看上方输出"
prepare_boot_files_seprmvr64
exit 0

}

restore_tethered_opts(){

clear 
echo "$INFO_TEXT"
echo ""
echo "选项："
echo ""
echo "1. 选择目标 IPSW"
echo "2. 选择基础 IPSW"
echo "3. 开始恢复"
echo "4. 返回"
read -p "请输入选项（1-4）：" tether_options
tether_options="${tether_options//[$'\r']/}"
if [[ $tether_options == 1 ]]; then
    ipsw_selector target
    restore_tethered_opts
elif [[ $tether_options == 2 ]]; then
    ipsw_selector base
    restore_tethered_opts
elif [[ $tether_options == 3 ]]; then
    if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
        do_tethered_restore_a12_a13
    elif [[ $VERSION == 7.* || $VERSION == 8.* || $VERSION == 9.* ]]; then
        if [[ $VERSION == 8.* ]]; then
            echo "surrealra1n 不支持恢复至 8.x 的 seprmvr64"
            exit 1
        elif [[ $VERSION == 7.* ]]; then
            read -p "你是否想将此恢复的一部分也进行越狱？（Y/n）：" jailbreak_choice
            jailbreak_choice="${jailbreak_choice//[$'\r']/}"
            if [[ $jailbreak_choice == Y || $jailbreak_choice == y ]]; then
                echo "越狱选项已启用"
                JAILBREAK=1
            else
                echo "越狱选项已禁用"
            fi
        fi
        do_tethered_seprmvr64_restore
    else
        do_tethered_restore
    fi
elif [[ $tether_options == 4 ]]; then
    reset_restore_vars
    restore_utils
else
    echo "无效选项。退出。"
    exit 0
fi

}

restore_a7_to_1033(){

if [[ -z "$IPSW_PATH" ]]; then
    echo "未选择 IPSW。中止。"
    exit 1
fi
if [[ ! -f "$IPSW_PATH" ]]; then
    echo "IPSW 不存在：$IPSW_PATH"
    exit 1
fi
dfu_helper
pwn_device
download_1033_ota_sep
rm -rf "shsh"
mkdir -p shsh
sudo ./bin/tsschecker -d $IDENTIFIER -i 10.3.3 -e $ECID -o -m tmp/BuildManifest-SEP.plist -s --save-path shsh
# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "在 shsh 文件夹中未找到 SHSH 文件。中止"
    exit 1
fi
det_rsep_flag
prepatch_ibssibec_fr
while true; do
    set +e
    sudo FUTURERESTORE_I_SOLEMNLY_SWEAR_THAT_I_AM_UP_TO_NO_GOOD=1 \
        ./futurerestore/futurerestore -t $SHSH_PATH --use-pwndfu \
        --sep $sep_path --sep-manifest $manifest_path \
        --custom-latest $LATEST_VERSION \
        $updatebb_flag $rsep_flag $IPSW_PATH
    EXIT_CODE=$?
    set -e
    if [[ $EXIT_CODE -eq 139 ]]; then
        echo "futurerestore 段错误（退出码 139），正在重试..."
        sleep 2
    else
        break
    fi
done
if [[ $EXIT_CODE -eq 0 ]]; then
    echo "恢复已完成！如有任何错误，请查看上方输出"
    exit 0
else
    echo "futurerestore 失败，退出码 $EXIT_CODE"
    exit 1
fi


}

restore_a7_options(){

if [[ $IDENTIFIER == iPhone6* || $IDENTIFIER == iPad4,1 || $IDENTIFIER == iPad4,2 || $IDENTIFIER == iPad4,3 || $IDENTIFIER == iPad4,4 || $IDENTIFIER == iPad4,5 ]]; then
    clear
else
    restore_utils
    return
fi
 
echo "$INFO_TEXT"
echo "此 OTA 恢复将使用 $LATEST_VERSION 基带"
echo ""
echo "选项："
echo ""
echo "1. 选择 10.3.3 IPSW"
echo "2. 开始恢复"
echo "3. 返回"
read -p "请输入选项（1-3）：" restore_a7_options_choice
restore_a7_options_choice="${restore_a7_options_choice//[$'\r']/}"
if [[ $restore_a7_options_choice == 1 ]]; then
    ipsw_selector target
    if [[ $VERSION == 10.3.3 ]] && [[ $BUILD == 14G60 ]]; then
        restore_a7_options
    else
        echo "IPSW 无效"
        sleep 2
        reset_restore_vars
        restore_a7_options
    fi
elif [[ $restore_a7_options_choice == 2 ]]; then
    restore_a7_to_1033
elif [[ $restore_a7_options_choice == 3 ]]; then
    reset_restore_vars
    restore_utils
fi

}

restore_utils(){

if [[ $outdated == 1 ]]; then
    echo "此 surrealra1n 测试版已过期"
    echo "有更新的测试版可用。请更新后再继续。"
    echo "你需要退出并重新运行 surrealra1n.sh，当其提示更新时，更新 surrealra1n。"
    sleep 10
    main_menu
    return
fi

if [[ $IDENTIFIER == NONE ]]; then
    main_menu
    return
fi

clear 
echo "$INFO_TEXT"
echo ""
echo "选项："
echo ""
echo "1. 恢复（使用 SHSH blob）"
echo "2. 恢复（有线）"
echo "3. 非有线恢复至 10.3.3（仅部分 A7 设备）"
echo "4. 仅启动"
echo "5. 返回"
read -p "请输入选项（1-5）：" restore_options
restore_options="${restore_options//[$'\r']/}"
if [[ $restore_options == 1 ]]; then
    restore_untethered_opts
elif [[ $restore_options == 2 ]]; then
    restore_tethered_opts
elif [[ $restore_options == 3 ]]; then
    restore_a7_options
elif [[ $restore_options == 4 ]]; then
    just_boot
elif [[ $restore_options == 5 ]]; then
    main_menu
else
    echo "无效选项。退出。"
    exit 1
fi

}

ios184(){

ramdisk_dmg="090-43874-358.dmg"
if [[ $IDENTIFIER == iPhone12,8 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-15768/008C2862-195B-48EE-B790-997431B752FD/iPhone12,8_18.4_22E240_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone12,5 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-15843/BDD88763-DC3F-4DB6-B82D-133EAB3E5F49/iPhone12,3,iPhone12,5_18.4_22E240_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone12,1 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-14797/272F08A9-B8B7-4649-9954-D83781B69280/iPhone12,1_18.4_22E240_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone11,8 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-14374/4BFDFFD2-985B-46A1-9444-D7EFB985F545/iPhone11,8_18.4_22E240_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-13816/F8D156A2-DBE7-49A4-8C2C-6EF6F6776F06/iPhone11,2,iPhone11,4,iPhone11,6_18.4_22E240_Restore.ipsw"
elif [[ $IDENTIFIER == iPad11* ]]; then
    ipsw_url="https://updates.cdn-apple.com/2025SpringFCS/fullrestores/082-14949/21FC3275-F323-4DF7-B410-3C2703F200CB/iPad_Spring_2019_18.4_22E240_Restore.ipsw"
fi

}

ios175(){

ramdisk_dmg="090-24459-112.dmg"
if [[ $IDENTIFIER == iPhone12,8 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2024SpringFCS/fullrestores/052-39310/C4EC1938-411B-4999-91AF-31AD24FDCE63/iPhone12,8_17.5_21F79_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone12,3 || $IDENTIFIER == iPhone12,5 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2024SpringFCS/fullrestores/052-39300/4FE26628-C36C-4AC4-A941-8846700C5F39/iPhone12,3,iPhone12,5_17.5_21F79_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone12,1 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2024SpringFCS/fullrestores/052-39253/2CBCD25D-6FE6-41AE-BA15-A5ECCABE2DAB/iPhone12,1_17.5_21F79_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone11,8 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2024SpringFCS/fullrestores/052-39331/01B884E9-B6BA-493B-B9C2-A877A9F29360/iPhone11,8_17.5_21F79_Restore.ipsw"
elif [[ $IDENTIFIER == iPhone11,2 || $IDENTIFIER == iPhone11,4 || $IDENTIFIER == iPhone11,6 ]]; then
    ipsw_url="https://updates.cdn-apple.com/2024SpringFCS/fullrestores/052-39325/8BB623C4-E600-4BC0-A5F3-2416D0FF2369/iPhone11,2,iPhone11,4,iPhone11,6_17.5_21F79_Restore.ipsw"
elif [[ $IDENTIFIER == iPad11* ]]; then
    ipsw_url="https://updates.cdn-apple.com/2024SpringFCS/fullrestores/052-39324/51A41966-4F0F-4BFD-AD3E-F007C678327E/iPad_Spring_2019_17.5_21F79_Restore.ipsw"
fi

}

sshrd_build_a12(){

echo "你想为 SSHRD 制作哪个 iOS 版本的 ramdisk？"
echo "1. iOS 18.4"
echo "2. iOS 17.5"
#echo "3. iOS 16.4"
#echo "4. iOS 16.0 (do not use this ramdisk if device is on 16.4 or later)"
#echo "5. iOS 15.4 (do not use this ramdisk if device is on 16.4 or later)"
#echo "6. iOS 14.5 (do not use this ramdisk if device is on 16.4 or later)"
#echo "7. iOS 14.0 (do not use this ramdisk if device is on 16.4 or later)"
read -p "请选择一个选项（1-2）：" version_option
version_option="${version_option//[$'\r']/}"

sshrd_path="SSHRD/$IDENTIFIER"
mkdir -p $sshrd_path
echo "正在获取 iOS $LATEST_VERSION 的 shsh blob"
rm -rf "shsh"
mkdir -p shsh
mkdir -p tarwork
mkdir -p work
ensure_firmwares_json
sudo ./bin/tsschecker -d $IDENTIFIER -s -e $ECID -i $LATEST_VERSION --save-path shsh

# Find the .shsh2 file in the shsh directory
SHSH_PATH=$(find shsh -type f -name "*.shsh2" | head -n 1)
if [[ -z "$SHSH_PATH" ]]; then
    echo "在 shsh 文件夹中未找到 SHSH 文件。中止"
    exit 1
fi
im4m="work/im4m"
./bin/img4tool -e -s $SHSH_PATH -m work/im4m
if [[ $version_option == 1 ]]; then
    VERSION="18.4"
    ios184
    key=""
elif [[ $version_option == 2 ]]; then
    VERSION="17.5"
    IBSS_KEY=$(grep "ibss-$VERSION:" "$KEY_FILE" | cut -d':' -f2 | xargs)
    key="-k $IBSS_KEY"
    ios175
else
    echo "无效选项"
    exit 1
fi
curl -L -o work/ssh.tar.gz https://github.com/verygenericname/sshtars/raw/refs/heads/main/ssh.tar.gz
gzip -d work/ssh.tar.gz
( cd work && sudo ../bin/pzb -g $ramdisk_dmg $ipsw_url && sudo ../bin/pzb -g Firmware/$ramdisk_dmg.trustcache $ipsw_url && sudo ../bin/pzb -g Firmware/agx/$GFX $ipsw_url && sudo ../bin/pzb -g Firmware/ane/$ANE $ipsw_url && sudo ../bin/pzb -g Firmware/$IOFW $ipsw_url && sudo ../bin/pzb -g Firmware/all_flash/$DEVICETREE $ipsw_url && sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url && sudo ../bin/pzb -g $KERNEL $ipsw_url )
./bin/img4 -i work/$IBSS -o work/iBSS.raw $key
./bin/iBootPatch -v -b "-v rd=md0 wdt=-1" work/iBSS.raw $sshrd_path/iBSS.patch
# kernel
./bin/img4tool -e work/$KERNEL -o work/kernel.raw
if [[ $version_option == 1 || $version_option == 2 ]]; then
    ./bin/Kernel64Patcher3 work/kernel.raw work/kernel.patch -ue
    ./bin/img4 -i work/kernel.patch -o $sshrd_path/kernel.img4 -M $im4m -A -T rkrn
else
    ./bin/img4 -i work/kernel.raw -o $sshrd_path/kernel.img4 -M $im4m -A -T rkrn
fi
# before ramdisk
./bin/img4 -i work/$GFX -o $sshrd_path/GFX.img4 -M $im4m
./bin/img4 -i work/$ANE -o $sshrd_path/ANE.img4 -M $im4m
./bin/img4 -i work/$IOFW -o $sshrd_path/SIO.img4 -M $im4m
./bin/img4 -i work/$DEVICETREE -o $sshrd_path/DeviceTree.img4 -M $im4m -T rdtr
# now it's real ramdisk prep
./bin/img4 -i work/$ramdisk_dmg -o work/ramdisk.dmg
hdiutil attach work/ramdisk.dmg -mountpoint rdwork
hdiutil create -size 210m -imagekey diskimage-class=CRawDiskImage -format UDZO -fs HFS+ -layout NONE -srcfolder rdwork -copyuid root work/ramdisk1.dmg
hdiutil detach -force rdwork
hdiutil attach work/ramdisk1.dmg -mountpoint rdwork
cd rdwork
tar -xvf ../work/ssh.tar
cd ..
hdiutil detach -force rdwork
./bin/img4 -i work/ramdisk1.dmg -o $sshrd_path/ramdisk.img4 -M $im4m -A -T rdsk
cd tarwork
tar -xvf ../work/ssh.tar
cd ..
find tarwork > work/list.txt
./bin/img4 -i work/$ramdisk_dmg.trustcache -o work/trustcache.raw
./bin/trustcache append work/trustcache.raw $(cat work/list.txt)
./bin/img4 -i work/trustcache.raw -o $sshrd_path/trustcache.img4 -M $im4m -A -T rtsc
# Done!
rm -rf work
rm -rf tarwork
echo "$VERSION" > SSHRD/$IDENTIFIER/version.txt
sleep 4
echo "SSH ramdisk 已成功创建！"

}

connect_to_ssh(){

./bin/iproxy 2222 22 &>/dev/null &
./bin/sshpass -p 'alpine' ssh -o HostKeyAlgorithms=+ssh-rsa -o StrictHostKeyChecking=no -p2222 root@localhost "${1:-}"

}

create_fakevar_a12(){

echo "FakeVar 将无法正常激活。此功能不面向普通用户。"
echo "而且我们不会为此提供绕过激活。"
sleep 4
boot_dir="boot/$IDENTIFIER/fakevar"
mkdir -p $boot_dir
echo "fakevar" > boot/$ECID.txt 
./bin/iproxy 2222 22 &>/dev/null &
mkdir -p work
curl -L -o work/var.tar.xz https://github.com/khanhduytran0/khanhduytran0.github.io/raw/master/var.tar.xz
xz -d work/var.tar.xz
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "/sbin/mount_apfs /dev/disk1s1 /mnt1 || true"
current_ios=$(./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "cat /mnt1/System/Library/CoreServices/SystemVersion.plist || true")
ios184
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "/sbin/newfs_apfs -A -D -o role=r -v DataX /dev/disk0s1 || true"
if [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11,2 || $IDENTIFIER == iPad11,4 ]]; then
    preboot="/dev/disk1s6"
    data="/dev/disk1s9"
else
    preboot="/dev/disk1s5"
    data="/dev/disk1s8"
fi
( cd work && sudo ../bin/pzb -g Firmware/dfu/$IBSS $ipsw_url )
./bin/img4 -i work/$IBSS -o work/iBSS.raw
./bin/iBootPatch -v -b "-v" work/iBSS.raw work/iBSS.patch
./bin/iBootpatch3 work/iBSS.patch $boot_dir/iBSS.boot
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "/sbin/mount_apfs $data /mnt2 || true"
./bin/sshpass -p "alpine" scp -P2222 work/var.tar root@localhost:/mnt2/var.tar
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "tar -xvf /mnt2/var.tar -C /mnt2 || true"
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "rm -rf /mnt2/var.tar || true"
./bin/sshpass -p "alpine" scp -P2222 hax/disabled.plist root@localhost:/mnt2/db/com.apple.xpc.launchd/disabled.plist
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "/sbin/mount_apfs $preboot /mnt6 || true"
active=$(./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "cat /mnt6/active || true")
./bin/sshpass -p "alpine" scp -P2222 root@localhost:/mnt6/$active/usr/standalone/firmware/devicetree.img4 work/devicetree.img4
./bin/sshpass -p "alpine" scp -P2222 root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcache work/kernelcache
./bin/img4tool -e work/devicetree.img4 -m work/im4m
./bin/img4tool -e work/devicetree.img4 -p work/devicetree.im4p
./bin/img4tool -e work/kernelcache -p work/kernelcache.im4p
./bin/img4tool -e work/kernelcache.im4p -o work/kernel.raw
./bin/img4tool -e work/devicetree.im4p -o work/devicetree.raw
curl -L -o bin/dtpatch.py https://github.com/pwnerblu/usbliter8-fun/raw/refs/heads/funny/work-27.0b4-n104/patch_dt2.py
python3 bin/dtpatch.py work/DeviceTree.raw -o work/DeviceTree.patch
./bin/dtree_patcher work/DeviceTree.patch work/DeviceTree.patch2 -d r
./bin/Kernel64Patcher3 work/kernel.raw work/kernel.patch -i
./bin/img4 -i work/DeviceTree.patch2 -o work/devicetred.img4 -M work/im4m -A -T dtre
./bin/img4 -i work/kernel.patch -o work/kernelcachd -M work/im4m -A -T krnl
./bin/sshpass -p "alpine" scp -P2222 work/devicetred.img4 root@localhost:/mnt6/$active/usr/standalone/firmware/devicetred.img4
./bin/sshpass -p "alpine" scp -P2222 work/kernelcachd root@localhost:/mnt6/$active/System/Library/Caches/com.apple.kernelcaches/kernelcachd
./bin/sshpass -p "alpine" ssh root@127.0.0.1 -p2222 -o StrictHostKeyChecking=no "/sbin/reboot || true" || true
echo "FakeVar 已创建！你可以使用「仅启动」进入 FakeVar。"
exit 0

}

sshrd_a12(){

if [[ $IDENTIFIER == NONE ]]; then
    main_menu
    return
elif [[ $IDENTIFIER == iPhone11* || $IDENTIFIER == iPhone12* || $IDENTIFIER == iPad11* ]]; then
    echo ""
else
    echo "不支持的设备"
    sleep 4
    main_menu
    return
fi

if [[ $dist == 3 || $dist == 4 ]]; then
    echo ""
else
    echo "surrealSSHRD 需要 macOS。"
    exit 1
fi

echo "欢迎使用 surrealsshrd v1.0 测试版"
echo "SSH tar 来自 SSHRD_Script：https://github.com/verygenericname/SSHRD_Script"
sshrd_path="SSHRD/$IDENTIFIER"
if [[ ! -d $sshrd_path ]] || [[ ! -f $sshrd_path/iBSS.patch ]] || [[ ! -f $sshrd_path/ramdisk.img4 ]] || [[ ! -f $sshrd_path/trustcache.img4 ]] || [[ ! -f $sshrd_path/GFX.img4 ]] || [[ ! -f $sshrd_path/ANE.img4 ]] || [[ ! -f $sshrd_path/SIO.img4 ]] || [[ ! -f $sshrd_path/DeviceTree.img4 ]] || [[ ! -f $sshrd_path/kernel.img4 ]]; then
    sshrd_build_a12
    sshrd_just_made=1
    make_ramdisk_again=0
else
    sshrd_just_made=0
fi
sshrdversion=$(cat $sshrd_path/version.txt)
if [[ $sshrdversion == 16.0* || $sshrdversion == 15.* || $sshrdversion == 14.* ]] && [[ $sshrd_just_made == 0 ]]; then
    echo "当前为 $IDENTIFIER 存在的 ramdisk 是用于 $sshrdversion 的"
    echo "如果你的设备运行 16.3.1 或更低版本，使用这个可能没问题。"
    echo "如果你的设备运行 iOS 16.4 或更高版本，请勿启动此 ramdisk。请创建 ramdisk 版本至少为 iOS 16.4 的 ramdisk。"
    read -p "你是否要重建 ramdisk？（y/n）：" remake_ramdisk_opt
    remake_ramdisk_opt="${remake_ramdisk_opt//[$'\r']/}"
    if [[ $remake_ramdisk_opt == Y || $remake_ramdisk_opt == y ]]; then
        make_ramdisk_again=1
    else
        make_ramdisk_again=0
    fi
elif [[ $sshrdversion == 17.* || $sshrdversion == 18.* ]] && [[ $sshrd_just_made == 0 ]]; then
    echo "当前为 $IDENTIFIER 存在的 ramdisk 是用于 $sshrdversion 的"
    echo "如果你的设备运行 16.4 或更高版本，使用这个可能没问题。"
    echo "如果你的设备运行 16.3.1 或更低版本，最好为 iOS 16.4 以下的版本创建 ramdisk。"
    read -p "你是否要重建 ramdisk？（y/n）：" remake_ramdisk_opt
    remake_ramdisk_opt="${remake_ramdisk_opt//[$'\r']/}"
    if [[ $remake_ramdisk_opt == Y || $remake_ramdisk_opt == y ]]; then
        make_ramdisk_again=1
    else
        make_ramdisk_again=0
    fi
fi
if [[ $make_ramdisk_again == 1 ]]; then
    sshrd_build_a12
fi
if [[ $IDENTIFIER == iPhone* ]]; then
    dfu_helper_a11
else
    dfu_helper
fi
pwn_device
if [[ ! -s bin/liter8ctl ]]; then
    curl -L -o bin/liter8ctl https://github.com/ahmadkamal09999-tech/usbliter8/raw/refs/heads/main/usbliter8ctl || true
fi
python3 bin/liter8ctl boot $sshrd_path/iBSS.patch || true
echo "usbliter8ctl 可能会出错。"
echo "只要设备进入 iBSS 恢复模式，这个错误可能也是正常的（屏幕应保持黑屏，但会被识别为恢复模式设备）。"
sleep 6
echo "正在检查设备是否处于恢复模式"
MODE=$(./bin/irecovery -q 2>/dev/null | grep "^MODE:" | cut -d ':' -f2 | xargs) || true
if [[ $MODE == Recovery ]]; then
    echo "已检测到设备处于恢复模式。"
else
    echo "未在恢复模式检测到设备。退出"
    exit 1
fi
ECID=$(./bin/irecovery -q | grep "^ECID:" | cut -d ':' -f2 | xargs)
irecovery -f $sshrd_path/ramdisk.img4
irecovery -c ramdisk
irecovery -f $sshrd_path/trustcache.img4
irecovery -c firmware
irecovery -f $sshrd_path/GFX.img4
irecovery -c firmware
irecovery -f $sshrd_path/ANE.img4
irecovery -c firmware
irecovery -f $sshrd_path/SIO.img4
irecovery -c firmware
irecovery -f $sshrd_path/DeviceTree.img4
irecovery -c devicetree
irecovery -f $sshrd_path/kernel.img4
irecovery -c bootx
echo "SSH ramdisk 现在应该正在启动！稍后你将连接至 SSH 会话"
echo "端口：2222 | 主机：sftp://127.0.0.1 | 用户：root | 密码：alpine"
echo "请记住，目前挂载数据分区可能无法使用！"
sleep 12
echo "选项："
echo "1. 创建 FakeVar（iOS 18+）"
echo "2. 连接到 SSH"
echo "3. 退出"
read -p "请选择一个选项（1-3）：" option_ssh
option_ssh="${option_ssh//[$'\r']/}"
if [[ $option_ssh == 1 ]]; then
    create_fakevar_a12
elif [[ $option_ssh == 2 ]]; then
    connect_to_ssh
fi


}

main_menu(){

clear
echo "$INFO_TEXT"
echo ""
echo "选项："
echo ""
echo "1. 降级选项"
echo "2. 杂项工具"
echo "3. surrealSSHRD（A12/A13）"
echo "4. 切换到 main 分支"
echo "5. 退出"
read -p "请输入选项（1-5）：" option
option="${option//[$'\r']/}"
if [[ $option == 1 ]]; then
    restore_utils
elif [[ $option == 2 ]]; then
    misc_utils
elif [[ $option == 3 ]]; then
    sshrd_a12
elif [[ $option == 4 ]]; then
    switch_to_main
elif [[ $option == 5 ]]; then
    echo "surrealra1n 正在退出"
    exit 0
else
    echo "无效选项。退出。"
    exit 1
fi

}

main_menu


