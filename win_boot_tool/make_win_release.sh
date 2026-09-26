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

# 定位 exe（dist/ 优先，本目录次之）
EXE=""
for c in dist/boot_tool.exe boot_tool.exe; do
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
cp "安装驱动.bat" "一键开机.bat" "$D/"
[[ -s vendor/wdi-simple.exe ]] && cp vendor/wdi-simple.exe "$D/"
[[ -s zadig.exe ]] && cp zadig.exe "$D/"   # 无 wdi-simple 时 安装驱动.bat 的 GUI 降级工具
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
  在本文件夹打开命令行（地址栏输入 cmd 回车），执行：
      boot_tool.exe --selftest
  把显示的结果截图发给客服。

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
