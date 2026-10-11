#!/bin/bash
# make_win_release.sh - 组装 Windows 客户发货包
# 前置：在 Windows 上 pyinstaller -F -n boot_tool boot_tool.py 得到 boot_tool.exe，
#       与 libusb-1.0.dll 一起放回本目录（或 dist/ 子目录）
# 用法：./make_win_release.sh [订单引导包.zip] [客户名]
# 产出：发货包_<客户名>.zip —— 微信/QQ 直发客户
set -euo pipefail
cd "$(dirname "$0")"

ORDER_ZIP="${1:-}"
CUSTOMER="${2:-客户}"
OUT="发货包_${CUSTOMER}.zip"

# 定位 exe（Nuitka Web 版优先，旧 tkinter 版次之）
EXE=""
for c in build_web/boot_tool.exe build_nuitka/boot_tool.exe dist/boot_tool.exe; do
    [[ -s "$c" ]] && EXE="$c" && break
done
if [[ -z "$EXE" ]]; then
    echo "!! 未找到 boot_tool.exe（先在 Windows 上 pyinstaller 打包后放回）"
    exit 1
fi

# 定位 libusb dll
DLL=""
for c in dist/libusb-1.0.dll libusb-1.0.dll vendor/libusb-1.0.dll; do
    [[ -s "$c" ]] && DLL="$c" && break
done

STAGE="$(mktemp -d /tmp/win_release.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
D="$STAGE/一键开机工具"
mkdir -p "$D"

cp "$EXE" "$D/boot_tool.exe"
[[ -n "$DLL" ]] && cp "$DLL" "$D/"
[[ -s brand.png ]] && cp brand.png "$D/"   # 窗口图标（exe 图标已内嵌）
[[ -d ui ]] && mkdir -p "$D/ui" && cp ui/index.html "$D/ui/"   # 液体玻璃前端
cp "安装驱动.bat" "一键开机.bat" "$D/"
[[ -s zadig.exe ]] && cp zadig.exe "$D/"   # 安装驱动.bat 的 GUI 兜底工具（官方签名版）
[[ -s driver_install.ps1 ]] && cp driver_install.ps1 "$D/"   # 安装驱动.bat 第3步依赖
# 注：wdi-simple.exe 已移出发行包（bat 不再调用，减体积并消除 LGPL 静态分发负担）
[[ -s NOTICE.txt ]] && cp NOTICE.txt "$D/"
[[ -s 驱动回滚说明.txt ]] && cp 驱动回滚说明.txt "$D/"
if [[ -d LICENSES ]]; then mkdir -p "$D/LICENSES"; cp LICENSES/* "$D/LICENSES/"; fi
# 随包静默驱动（证书+WinUSB 驱动包，优先方案）
if [[ -d driver_pkg && -s driver_pkg/dfu_driver.cer ]]; then
    mkdir -p "$D/driver_pkg"
    cp driver_pkg/* "$D/driver_pkg/"
fi
if [[ -n "$ORDER_ZIP" && -s "$ORDER_ZIP" ]]; then
    cp "$ORDER_ZIP" "$D/"
    ORDER_NAME=$(basename "$ORDER_ZIP")
else
    ORDER_NAME="（卖家随后单独发送的引导包.zip）"
fi

cat > "$D/使用说明.txt" << EOF
一键开机工具 · 使用说明
========================================

【第一次使用（只做一次）】
  1. 解压本文件夹到电脑任意位置（如桌面）
  2. 双击「安装驱动.bat」→ 允许管理员权限 → 等待提示成功
     （如果打开的是 Zadig 工具：Options 勾 List All Devices →
       选 Apple Mobile (DFU Mode) → 选 WinUSB → 点 Install Driver）
  3. 把卖家发来的引导包 zip（${ORDER_NAME}）放到本文件夹里，不要解压

【每次开机（关机/没电后都要）】
  1. 双击「一键开机.bat」
  2. 按窗口提示让手机进 DFU（屏幕全黑）
  3. 把手机连到 Pi Pico 破解器，灯闪完后再插回电脑
  4. 工具自动发送引导，等待 10-30 秒手机开机

【遇到问题】
  打开工具点右下角「诊断」按钮，点「复制诊断日志」发给客服。
  （或在本文件夹运行 boot_tool.exe --selftest，会生成 自检结果.txt）

【重要提醒】
  - 引导包与你的手机一一绑定（ECID），转给别人无法使用
  - 工具文件夹和引导包请备份两处，丢失后手机无法开机需重新购买
  - 任何时候都可以刷回官方最新版系统（兜底方案）
EOF

rm -f "$OUT"
# python3 优先（macOS/Linux）；Windows 下 python3 可能是 Microsoft Store 占位符，
# 必须验证可真正执行后才使用，否则回退 python
PY=""
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys" >/dev/null 2>&1; then
        PY="$c"; break
    fi
done
[[ -n "$PY" ]] || { echo "!! 未找到可用的 python3/python"; exit 1; }

# 生成并签署发布清单（版本/提交/每文件 SHA256，Ed25519 签名）
# 注意：本脚本必须在 git 提交之后运行，commit 才能对应真实发行物
VERSION=$(grep -oP 'VERSION\s*=\s*"\K[^"]+' boot_tool.py | head -1)
COMMIT=$(git describe --always --dirty 2>/dev/null || echo unknown)
KEY="license_signing_key.pem"
[[ -s "$KEY" ]] || { echo "!! 缺少签名私钥 $KEY，拒绝产出未签名发行包"; exit 1; }
"$PY" - "$D" "$VERSION" "$COMMIT" "$KEY" << 'PY'
import hashlib, os, sys
stage, version, commit, key = sys.argv[1:5]
lines = [f"玄烨品果·一键开机 发布清单", f"version={version}", f"commit={commit}", ""]
for root, dirs, files in os.walk(stage):
    for name in sorted(files):
        p = os.path.join(root, name)
        h = hashlib.sha256(open(p, "rb").read()).hexdigest()
        lines.append(f"{h}  {os.path.relpath(p, stage).replace(os.sep, '/')}")
manifest = ("\n".join(lines) + "\n").encode("utf-8")
# 二进制落盘（文本模式在 Windows 会把 LF 转 CRLF 导致签名失效）
open(os.path.join(stage, "清单.txt"), "wb").write(manifest)
from cryptography.hazmat.primitives import serialization
priv = serialization.load_pem_private_key(open(key, "rb").read(), password=None)
assert isinstance(priv, __import__("cryptography.hazmat.primitives.asymmetric.ed25519", fromlist=["Ed25519PrivateKey"]).Ed25519PrivateKey)
open(os.path.join(stage, "清单.sig"), "wb").write(priv.sign(manifest))
# 落盘后回读验签（防编码/换行再次破坏）
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
raw = open(os.path.join(stage, "清单.txt"), "rb").read()
sig = open(os.path.join(stage, "清单.sig"), "rb").read()
Ed25519PublicKey.from_public_bytes(priv.public_key().public_bytes_raw()).verify(sig, raw)
print("[✓] 清单已生成、落盘并回读验签通过")
PY

"$PY" - "$STAGE" "$PWD/$OUT" << 'PY'
import os, sys, time, zipfile
stage, out = sys.argv[1], sys.argv[2]
def zi(arc, st, is_dir=False):
    dt = time.localtime(st.st_mtime)[:6]
    z = zipfile.ZipInfo(arc, date_time=dt)
    z.flag_bits |= 0x800
    z.external_attr = (st.st_mode & 0xFFFF) << 16
    if is_dir: z.external_attr |= 0x10
    else: z.compress_type = zipfile.ZIP_DEFLATED
    return z
with zipfile.ZipFile(out, "w") as z:
    for root, dirs, files in os.walk(stage):
        for name in sorted(files):
            if name == ".DS_Store" or name.startswith("._"): continue
            p = os.path.join(root, name)
            with open(p, "rb") as f:
                z.writestr(zi(os.path.relpath(p, stage), os.stat(p)), f.read())
PY

echo "[✓] 已生成：${OUT}（$(du -h "$OUT" | cut -f1)）"
unzip -l "$OUT" | awk 'NR>3 {print "    ", $4}' | grep -v '^$' | head -12
