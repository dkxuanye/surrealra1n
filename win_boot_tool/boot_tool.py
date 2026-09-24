#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
玩机乐园 · 一键开机（Windows / macOS 通用）
适用：A12/A13 设备（iPhone XR / 11 / XS 系列 / SE2）配合 Pi Pico 破解器使用
用法：把「引导启动包」里的 boot 文件夹（或同名 zip）放在本工具旁边，双击运行
"""
import os
import sys
import time
import glob
import shutil
import tempfile
import zipfile

import usb.core
import usb.util

APPLE_VID = 0x05AC
DFU_PID = 0x1227
DFU_DNLOAD = 1
DFU_ABORT = 4
CUSTOM_BOOT = 8
TRANSFER_SIZE = 0x800

TOOL_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))

if os.name == "nt":
    os.system("chcp 65001 >nul")
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass


def pause():
    try:
        input("\n按回车键退出...")
    except (EOFError, KeyboardInterrupt):
        pass


def out(s="", **kw):
    kw.setdefault("flush", True)
    print(s, **kw)


def banner():
    out("=" * 46)
    out("      玩机乐园 · 一键开机工具")
    out("      适用：iPhone XR / 11 / SE2（半引导机型）")
    out("=" * 46)
    out()


def load_boot_bundle():
    """定位引导包：优先同级 boot/ 目录，其次同级 *.zip。返回 (boot_dir, 需清理的临时目录)"""
    local_boot = os.path.join(TOOL_DIR, "boot")
    if os.path.isdir(local_boot) and glob.glob(os.path.join(local_boot, "0x*.txt")):
        return local_boot, None

    for z in sorted(glob.glob(os.path.join(TOOL_DIR, "*.zip"))):
        try:
            zf = zipfile.ZipFile(z)
            names = zf.namelist()
            if any("boot/0x" in n and n.endswith(".txt") for n in names):
                tmp = tempfile.mkdtemp(prefix="bootpkg_")
                zf.extractall(tmp)
                out(f"[*] 已加载引导包：{os.path.basename(z)}")
                return os.path.join(tmp, "boot"), tmp
        except zipfile.BadZipFile:
            continue
    return None, None


def dfu_devices():
    return list(usb.core.find(idVendor=APPLE_VID, idProduct=DFU_PID, find_all=True))


def serial_of(dev):
    try:
        return dev.serial_number or ""
    except usb.core.USBError:
        return ""


def wait_dfu_pwned():
    """等待出现已破解（PWND）的 DFU 设备，返回该设备。期间给出引导。"""
    out("[1/3] 正在寻找设备（DFU 模式）...")
    gave_dfu_tips = False
    gave_pico_tips = False
    while True:
        devs = dfu_devices()
        for dev in devs:
            srnm = serial_of(dev)
            if "PWND:[" in srnm:
                return dev
            if not gave_pico_tips:
                gave_pico_tips = True
                out()
                out("    检测到 DFU 设备，但还未破解。")
                out("    请把手机从电脑上拔下，连接到 Pi Pico 破解器，")
                out("    等 Pico 上的灯闪烁完成后，再把手机插回电脑。")
                out("    （保持手机处于 DFU 状态：屏幕全程全黑）")
                out()
        if not devs and not gave_dfu_tips:
            gave_dfu_tips = True
            out()
            out("    未检测到 DFU 设备。请按下面步骤让手机进入 DFU 模式：")
            out("    1) 按一下「音量+」松开")
            out("    2) 按一下「音量-」松开")
            out("    3) 按住「电源键」直到屏幕完全变黑")
            out("    4) 黑屏瞬间，同时按住「电源键+音量-」，心里数 5 秒")
            out("    5) 松开「电源键」，继续按住「音量-」约 10 秒")
            out("    6) 屏幕保持全黑 = 成功；出现 Apple 标志 = 失败，请重试")
            out()
        out(".", end="", flush=True)
        time.sleep(1.5)


def ecid_of(dev):
    srnm = serial_of(dev)
    for token in srnm.split():
        if token.upper().startswith("ECID:"):
            return token.split(":", 1)[1].lower()
    return ""


def pick_boot_files(boot_dir, device_ecid):
    """根据 ECID 匹配版本记录，返回 (identifier, version, iBSS.boot 路径)"""
    ecid_files = glob.glob(os.path.join(boot_dir, "0x*.txt"))
    if not ecid_files:
        out("[!] 引导包内没有版本记录文件（boot/0x*.txt）")
        return None
    version = None
    for f in ecid_files:
        base = os.path.basename(f)          # 0x001e0d1c3462002e.txt
        pkg_ecid = base[2:-4].lower()       # 001e0d1c3462002e
        if pkg_ecid == device_ecid:
            with open(f, "r", encoding="utf-8", errors="ignore") as fh:
                version = fh.read().strip()
            break
    if version is None:
        out(f"[!] 这个启动包不属于当前手机（ECID 不匹配）。")
        out(f"    当前手机 ECID: {device_ecid}")
        out(f"    启动包对应:    {[os.path.basename(f)[:-4] for f in ecid_files]}")
        return None
    if not version:
        out("[!] 版本记录文件为空，无法确定引导版本")
        return None

    matches = sorted(glob.glob(os.path.join(boot_dir, "*", version, "iBSS.boot")))
    if not matches:
        out(f"[!] 引导包内没有 iOS {version} 的引导文件")
        avail = sorted({os.path.basename(os.path.dirname(p)) for p in glob.glob(os.path.join(boot_dir, "*", "*", "iBSS.boot"))})
        out(f"    包内可用版本：{avail}")
        return None
    ibss = matches[0]
    identifier = os.path.basename(os.path.dirname(os.path.dirname(ibss)))
    out(f"[*] 机型: {identifier} | 系统: iOS {version}")
    return identifier, version, ibss


def send_ibss(dev, ibss_path):
    with open(ibss_path, "rb") as f:
        buf = f.read()
    out(f"[2/3] 正在发送引导文件（{len(buf) // 1024} KB）...")
    sent = 0
    left = len(buf)
    while left:
        n = min(TRANSFER_SIZE, left)
        dev.ctrl_transfer(0x21, DFU_DNLOAD, 0, 0, buf[sent:sent + n], 1000)
        sent += n
        left -= n
        pct = sent * 100 // len(buf)
        print(f"\r    进度 {pct:3d}%  (0x{sent:x})", end="", flush=True)
    print(flush=True)
    dev.ctrl_transfer(0x21, DFU_DNLOAD, 0, 0, None, 100)
    dev.ctrl_transfer(0x21, CUSTOM_BOOT, 0, 0, None, 100)
    try:
        dev.ctrl_transfer(0x21, DFU_ABORT, 0, 0, None, 100)
    except usb.core.USBError:
        pass
    # Windows 下设备收到开机指令后会立刻离开 DFU，最后的收尾指令可能撞上
    # 断开而报错，属正常。以「设备是否离开 DFU」为准判定成败。
    deadline = time.time() + 8
    while time.time() < deadline:
        if not dfu_devices():
            return
        time.sleep(1)
    raise usb.core.USBError("开机指令未被设备接受（设备仍停留在 DFU）")


def selftest():
    out("=== 自检 ===")
    try:
        import usb.core  # noqa: F401
        out("[✓] USB 库正常")
    except Exception as e:
        out(f"[✗] USB 库异常：{e}（Windows 请确认 libusb1.dll 与工具在同一目录）")
    boot_dir, _ = load_boot_bundle()
    if boot_dir:
        out(f"[✓] 引导包已找到：{boot_dir}")
        ecid_files = glob.glob(os.path.join(boot_dir, "0x*.txt"))
        for f in ecid_files:
            with open(f, encoding="utf-8", errors="ignore") as fh:
                out(f"    包 ECID: {os.path.basename(f)[:-4]} | 记录版本: iOS {fh.read().strip()}")
        boots = glob.glob(os.path.join(boot_dir, "*", "*", "iBSS.boot"))
        for b in boots:
            out(f"    引导文件: {os.path.relpath(b, boot_dir)} ({os.path.getsize(b) // 1024} KB)")
    else:
        out("[✗] 未找到引导包（boot 文件夹或 .zip）")
    devs = dfu_devices()
    if devs:
        for d in devs:
            out(f"[✓] DFU 设备: {serial_of(d) or '(读不到序列号——请用 Zadig 安装驱动)'}")
    else:
        out("[i] 当前无 DFU 设备（手机开机/恢复模式状态属正常，引导时才需要 DFU）")
    out("=== 自检结束，把以上全部截图发给客服 ===")
    return 0


def main():
    if "--selftest" in sys.argv:
        return selftest()

    banner()

    boot_dir, tmp = load_boot_bundle()
    if not boot_dir:
        out("[!] 没有找到引导包。")
        out("    请把「引导启动包」里的 boot 文件夹（或 .zip）放到本工具旁边。")
        out("    （boot 文件由卖家按你的设备定制提供）")
        pause()
        return 1

    dev = wait_dfu_pwned()
    out("[*] 已连接已破解的设备")
    device_ecid = ecid_of(dev)
    out(f"[*] 设备 ECID: {device_ecid}")

    picked = pick_boot_files(boot_dir, device_ecid)
    if not picked:
        pause()
        return 1
    identifier, version, ibss = picked

    try:
        send_ibss(dev, ibss)
    except usb.core.USBError as e:
        out()
        out(f"[!] 发送失败：{e}")
        out("    常见原因：手机在发送过程中退出了 DFU（请重试）；驱动未安装（见附带说明）")
        pause()
        return 1

    out("[3/3] 发送完成！设备正在启动。")
    out()
    out("    请等待 10-30 秒，屏幕亮起进入系统即可正常使用。")
    out("    提醒：关机/没电后需要重新执行本工具。")
    out()
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    pause()
    return 0


if __name__ == "__main__":
    sys.exit(main())
