#!/bin/bash
# make_share.sh - 打包国内分享版 surrealra1n（离线优先 / 免 GitHub）
# 用法: ./make_share.sh
# 产出: surrealra1n-cn-v<版本>-YYYYMMDD.zip
# 说明: 只打包运行所需文件；排除本地降级文件、引导文件、开发文档、敏感/本地缓存
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(sed -n 's/^CURRENT_VERSION="\(.*\)"/\1/p' surrealra1n.sh | head -1)
VERSION=${VERSION:-unknown}
OUT="surrealra1n-cn-${VERSION}-$(date +%Y%m%d).zip"
STAGE="$(mktemp -d /tmp/surreal_share.XXXXXX)"
PKG="$STAGE/surrealra1n"
trap 'rm -rf "$STAGE"' EXIT

echo "==> [1/4] 校验关键文件"
missing=0
while read -r f; do
    if [[ ! -s "$f" ]]; then
        echo "    [缺失] $f"
        missing=1
    fi
done <<'EOF'
surrealra1n.sh
setup_cn.sh
启动surrealra1n.command
启动setup_cn.command
activate.sh
backup.sh
README.md
LICENSE
NOTICE
firmwares.json
hax/asr
hax/disabled.plist
futurerestore/futurerestore
update/latest.txt
bin/gaster
bin/tsschecker
bin/irecovery
bin/idevicerestore
bin/img4
bin/img4tool
bin/hfsplus
bin/pzb
bin/liter8ctl
bin/iproxy
bin/sshpass
bin/zenity
bin/trustcache
bin/kerneldiff
bin/ldid
bin/dmg
bin/Kernel64Patcher
bin/iBoot64Patcher
EOF

tools=$(ls bin | wc -l | tr -d ' ')
if [[ "$tools" -lt 30 ]]; then
    echo "    [异常] bin/ 只有 $tools 个文件（应 ≥30），工具可能不齐"
    missing=1
fi
if ! bash -n surrealra1n.sh 2>/dev/null; then
    echo "    [异常] surrealra1n.sh 语法错误"
    missing=1
fi
if [[ $missing -ne 0 ]]; then
    echo "!! 关键文件缺失，中止打包（先补齐再运行本脚本）"
    exit 1
fi
echo "    全部就绪（版本 ${VERSION}，bin/ 共 $tools 个工具）"

echo "==> [2/4] 收集文件"
mkdir -p "$PKG"
cp -R surrealra1n.sh setup_cn.sh activate.sh backup.sh README.md LICENSE NOTICE firmwares.json \
      启动surrealra1n.command 启动setup_cn.command "$PKG/"
for d in bin keys futurerestore update hax SSHRD_Script; do
    cp -R "$d" "$PKG/"
done

# 过期的本地 brew shim：会顶掉真实 brew，导致依赖检查误判（如 jq），不要分发
rm -f "$PKG/bin/brew"
# 本地缓存（切换分支时生成，非包内必需）
rm -f "$PKG/update/latest_main.txt"
# SSHRD_Script 的运行产物/日志/下载缓存，不要分发
rm -rf "$PKG/SSHRD_Script/logs" "$PKG/SSHRD_Script/sshtars"
rm -f "$PKG/SSHRD_Script/gaster" "$PKG/SSHRD_Script/gaster-Darwin.zip" "$PKG/SSHRD_Script/gaster-Linux.zip"
find "$PKG" -name '.DS_Store' -delete
find "$PKG" -name '._*' -delete

# 兜底：本地降级/引导文件、开发文档、敏感内容一旦误拷入立即中止
forbidden=(
    boot shsh restorefiles firmware_downloads ipsw SSHRD activation_records
    docs scripts win_boot_tool .workbuddy .github .git
    GLM.md QWEN.md hy4.md make_share.sh
    start_13.5_restore.command update/latest_main.txt
)
for f in "${forbidden[@]}"; do
    if [[ -e "$PKG/$f" || -L "$PKG/$f" ]]; then
        echo "!! 检测到受限内容被误打包: ${f}（已中止）"
        exit 1
    fi
done

# 敏感信息扫描（文本文件）
if grep -rInE 'dkxuanye|/Users/[A-Za-z][A-Za-z0-9._-]+|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}' "$PKG" \
       --exclude-dir=.licenses --exclude='*.zip' --exclude='*.png' 2>/dev/null; then
    echo "!! 上面的文件疑似包含本机路径/用户名/密钥（已中止，请检查）"
    exit 1
fi

# 国内使用必读
cat > "$PKG/国内使用必读.txt" <<'EOF'
surrealra1n 国内分享版 —— 使用前必读
====================================

版本: v2.2.1（已合并上游 v2.1/v2.2/v2.2.1，新增 iOS 8 免引导降级等）

1) 双击「启动setup_cn.command」安装依赖（自动配置清华/中科大 brew 镜像 + GitHub 加速 +
   aria2c 证书），然后双击「启动surrealra1n.command」运行主程序；
   习惯终端的也可以跑 ./setup_cn.sh 和 ./surrealra1n.sh。

2) 取 blobs 已离线：包内自带 firmwares.json，脚本自动使用，无需访问 ipsw.me。
   若日后版本数据过旧，可在能联网的环境重新下载后覆盖：
   https://api.ipsw.me/v2.1/firmwares.json/condensed

3) 固件请提前自行下载（Apple 官方 CDN 国内直连速度快，无需代理）：
   - iPad Air 2: iPad_64bit_TouchID_13.6 / 15.8.8 等
   - iPhone SE 2: iPhone12,8_13.5 / 26.6 等
   版本查询: https://ipsw.me （或用 i4Tools 等工具下载）

4) 本包为 macOS 10.15+ (Intel) 构建；Apple Silicon 需 Rosetta 2（脚本会提示安装）。
   Linux 用户请勿使用本包，建议自行获取官方仓库对应版本。

5) 新功能提示：
   - iOS 8.0-8.2 免引导（untether）降级为实验性，仅支持 iPhone 5S；
   - iOS 7 有线恢复可选一并越狱（含 Wi-Fi 密码修复补丁）；
   - 主菜单「4. 切换到开发分支（不推荐）」可切换上游 development 版本。

6) 更新检查默认关闭（离线优先，不联网、不强制）。如需联网检查更新：
   SKIP_UPDATE_CHECK=0 ./surrealra1n.sh

7) 常见问题速查：
   - Finder 不认设备：先解锁 iPad 再插线（USB 限制模式）；
     或执行 killall -CONT AMPDevicesAgent AMPDeviceDiscoveryAgent MobileDeviceUpdater
   - tsschecker 卡住：确认 firmwares.json 在 surrealra1n 目录下
   - 每次开机需连电脑引导（tethered 特性），引导文件在运行后生成的 boot/ 目录
   - 刷机中断设备无恙：重新进 DFU 重跑即可，数据无损失（会清空）
EOF

echo "==> [3/4] 压缩"
# 用 python3 zipfile 打包：Info-ZIP 不写 UTF-8 名字标志，中文文件名（含启动器）解压会乱码
python3 - "$STAGE" "$OLDPWD/$OUT" <<'PY'
import os, sys, time, zipfile

stage, out = sys.argv[1], sys.argv[2]

def zipinfo(arc, st, is_dir):
    dt = time.localtime(st.st_mtime)[:6]
    if dt[0] < 1980:
        dt = (1980, 1, 1, 0, 0, 0)
    zi = zipfile.ZipInfo(arc, date_time=dt)
    zi.flag_bits |= 0x800
    zi.external_attr = (st.st_mode & 0xFFFF) << 16
    if is_dir:
        zi.external_attr |= 0x10
    else:
        zi.compress_type = zipfile.ZIP_DEFLATED
    return zi

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(stage):
        dirs[:] = sorted(d for d in dirs if d != "__MACOSX")
        for name in dirs:
            p = os.path.join(root, name)
            z.writestr(zipinfo(os.path.relpath(p, stage) + "/", os.stat(p), True), b"")
        for name in sorted(files):
            if name in (".DS_Store",) or name.startswith("._"):
                continue
            p = os.path.join(root, name)
            st = os.stat(p)
            with open(p, "rb") as f, z.open(zipinfo(os.path.relpath(p, stage), st, False), "w") as w:
                while True:
                    chunk = f.read(1024 * 1024)
                    if not chunk:
                        break
                    w.write(chunk)
PY

echo "==> [4/4] 校验并完成"
# 压缩后二次校验：确认没有本地/敏感内容混入（只看包内路径）
if ! python3 - "$OUT" <<'PY'
import re
import sys
import zipfile

pat = re.compile(
    r'^(?:[^/]+/)?(?:boot|shsh|restorefiles|firmware_downloads|ipsw|'
    r'activation_records|docs|scripts|win_boot_tool|\.git|\.github|\.workbuddy)(?:/|$)'
    r'|(?:^|/)(?:GLM\.md|QWEN\.md|hy4\.md|make_share\.sh|latest_main\.txt|'
    r'start_13\.5_restore\.command)$|(?:^|/)\.DS_Store$'
)
with zipfile.ZipFile(sys.argv[1]) as z:
    bad = [n for n in z.namelist() if pat.search(n)]
if bad:
    print("受限内容:")
    for n in bad[:20]:
        print("  -", n)
    sys.exit(1)
PY
then
    echo "!! 压缩包中发现受限内容（已中止）"
    exit 1
fi
echo "    输出: $(pwd)/$OUT"
echo "    大小: $(du -h "$OUT" | cut -f1 | tr -d ' ')"
echo "    文件: $(unzip -l "$OUT" | tail -1 | awk '{print $2}') 个"
