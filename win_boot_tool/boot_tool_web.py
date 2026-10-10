#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
玄烨品果 · 一键开机（液体玻璃界面版）
前端 ui/index.html（WebView2 渲染），引擎复用 boot_tool.py（同目录）。
构建：build_exe.cmd（Nuitka；ui/ 与 exe 同目录发布）
"""
import io
import json
import os
import queue
import sys
import threading
import time
import traceback
from contextlib import redirect_stdout

TOOL_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
sys.path.insert(0, TOOL_DIR)

import webview  # pywebview（Windows 走 WebView2）

import boot_tool as engine


class Api:
    def __init__(self):
        self.window = None  # webview.start 后注入
        self.events = queue.Queue()

    # ---- JS 可调用 ----
    def get_state(self):
        info = engine.bundle_summary()
        return {
            "brand": engine.BRAND,
            "version": engine.VERSION,
            "tool_dir": TOOL_DIR,
            "bundle": info,
        }

    def poll(self):
        """前端每 250ms 拉一次事件（evaluate_js 跨线程在 WebView2 上不可用，
        轮询是稳妥通道）"""
        out = []
        try:
            while True:
                out.append(self.events.get_nowait())
        except queue.Empty:
            pass
        return out

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    def install_driver(self):
        bat = os.path.join(TOOL_DIR, "安装驱动.bat")
        if os.path.isfile(bat):
            try:
                os.startfile(bat)  # noqa: S606 bat 自带 UAC 提权
            except Exception:
                pass

    def copy_qq(self):
        qq = "".join(c for c in engine.BRAND["contact"] if c.isdigit())
        self._clipboard(qq)

    def selftest(self):
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                engine.selftest()
        except Exception:
            buf.write(traceback.format_exc())
        text = buf.getvalue()
        self._clipboard(text)
        return text

    def report(self, s):
        """前端 #probe 自检回传（生产环境无操作）"""
        if os.environ.get("XYPG_PROBE"):
            with open(os.environ["XYPG_PROBE"], "a", encoding="utf-8") as f:
                f.write(s + "\n")

    # ---- 内部 ----
    def _clipboard(self, text):
        try:
            import tkinter as tk
            r = tk.Tk(); r.withdraw()
            r.clipboard_clear(); r.clipboard_append(text)
            r.update(); r.destroy()
        except Exception:
            pass

    def _ev(self, typ, **data):
        self.events.put({"type": typ, "data": data})

    # ---- 引导主流程（后台线程；逻辑与 boot_tool_gui 一致，事件推给前端）----
    def _run(self):
        try:
            self._ev("step", t="检查引导包...")
            boot_dir, _tmp = engine.load_boot_bundle()
            if not boot_dir:
                self._ev("step", t="✗ 没有找到引导包", cls="err")
                self._ev("guide", html=(
                    "请把卖家发给你的引导包（boot 文件夹或 zip）<br>"
                    "放到本工具所在的文件夹里，然后点「开始」重试。<br><br>"
                    f"📁 {TOOL_DIR}"))
                self._ev("done", ok=False)
                return
            self._ev("status", t="引导包已就绪", hot=True)

            # 阶段1：DFU
            self._ev("stage", n=1)
            self._ev("step", t="第 1 步：让手机进入 DFU 模式")
            self._ev("guide", html=(
                "手机用数据线连接电脑，然后：<br>"
                "　1. 按一下「音量+」松开<br>"
                "　2. 按一下「音量-」松开<br>"
                "　3. 按住「电源键」直到屏幕完全变黑<br>"
                "　4. 黑屏后，同时按住「电源键+音量-」数 <b>5 秒</b><br>"
                "　5. 松开「电源键」，继续按住「音量-」约 <b>10 秒</b><br><br>"
                "屏幕保持全黑 = 成功（出现苹果标志请重来）<br>"
                "进入后工具会自动继续。<br><br>"
                "💡 数不准秒？点下方按钮，开按的瞬间启动倒数"))
            self._ev("timer", show=True)

            pico_hinted = False
            driver_fix_at = 0.0
            dev = None
            while dev is None:
                # 读不到序列号的（半失明/Apple 占用）按未出现处理，交给失明自愈
                devs = [d for d in engine.dfu_devices() if engine.serial_of(d)]
                hit = None
                for d in devs:
                    if "PWND:[" in engine.serial_of(d):
                        hit = d
                        break
                if hit is not None:
                    dev = hit
                    break
                if devs and not pico_hinted:
                    pico_hinted = True
                    self._ev("timer", show=False)
                    self._ev("stage", n=2)
                    self._ev("step", t="第 2 步：用 Pi Pico 破解")
                    self._ev("guide", html=(
                        "已检测到 DFU 设备，但还未破解：<br><br>"
                        "　1. 把手机从电脑拔下<br>"
                        "　2. 连接到 Pi Pico 破解器，等灯闪完<br>"
                        "　3. 把手机插回电脑<br><br>"
                        "（期间手机屏幕保持全黑）"))
                elif not devs:
                    now = time.time()
                    if now - driver_fix_at > 10 and engine.dfu_driver_blind():
                        driver_fix_at = now
                        self._ev("timer", show=False)
                        self._ev("step", t="正在自动安装驱动…", cls="warn")
                        self._ev("guide", html=(
                            "手机已进入 DFU，但驱动被 Apple 驱动占用。<br><br>"
                            "已自动启动驱动安装，<br>"
                            "请在弹出的窗口中点「是」允许管理员权限。<br>"
                            "安装完成后这里会自动继续。"))
                        bat = os.path.join(TOOL_DIR, "安装驱动.bat")
                        if os.path.isfile(bat):
                            try:
                                os.startfile(bat)  # noqa: S606
                            except Exception:
                                pass
                time.sleep(1.0)

            # 阶段3：匹配 + 授权 + 发送
            self._ev("stage", n=3)
            self._ev("timer", show=False)
            self._ev("step", t="设备已就绪，正在匹配…")
            ecid = engine.ecid_of(dev)
            self._ev("status", t=f"ECID: {ecid}", hot=True)
            picked = engine.pick_boot_files(boot_dir, ecid)
            if not picked:
                self._ev("step", t="✗ 引导包与手机不匹配", cls="err")
                self._ev("guide", html=(
                    "这个引导包不属于当前手机（ECID 不一致）。<br>"
                    "请确认拿错了包，或联系客服重新制作。"))
                self._ev("done", ok=False)
                return
            _identifier, version, ibss = picked

            lic_ok, lic_msg = engine.license_check(boot_dir, ecid)
            if not lic_ok:
                self._ev("step", t="✗ 未获授权", cls="err")
                self._ev("guide", html="<br>".join(lic_msg.splitlines()) +
                         f"<br><br>客服：{engine.BRAND['contact']}")
                self._ev("done", ok=False)
                return
            self._ev("license_ok", t=lic_msg)

            self._ev("step", t=f"第 3 步：发送引导文件（iOS {version}）")
            self._ev("guide", html="正在发送，请勿拔线…")
            self._ev("progress", pct=0)

            with open(ibss, "rb") as f:
                buf = f.read()
            total = len(buf)
            sent = 0
            while True:
                n = min(engine.TRANSFER_SIZE, total - sent)
                if n <= 0:
                    break
                dev.ctrl_transfer(0x21, engine.DFU_DNLOAD, 0, 0, buf[sent:sent + n], 1000)
                sent += n
                self._ev("progress", pct=sent * 100 // total)
            dev.ctrl_transfer(0x21, engine.DFU_DNLOAD, 0, 0, None, 100)
            dev.ctrl_transfer(0x21, engine.CUSTOM_BOOT, 0, 0, None, 100)
            try:
                dev.ctrl_transfer(0x21, engine.DFU_ABORT, 0, 0, None, 100)
            except engine.usb.core.USBError:
                pass
            ok = False
            deadline = time.time() + 8
            while time.time() < deadline:
                if not engine.dfu_devices():
                    ok = True
                    break
                time.sleep(1)
            self._ev("progress", pct=100)
            self._ev("done", ok=ok)
            if ok:
                self._postboot()
        except Exception as e:
            self._ev("error", msg=f"{e}\n{traceback.format_exc()[:400]}")
            self._ev("done", ok=False)

    def _postboot(self):
        def worker():
            def on_check(pids):
                tag = {0x1227: "DFU", 0x1281: "恢复模式", 0x12A8: "已开机"}.get(
                    next(iter(pids), None), "等待") if len(pids) <= 1 else "等待"
                self._ev("postboot", t=f"确认开机状态：{tag}…")
            result = engine.detect_post_boot(on_check=on_check)
            if result == "booted":
                pass  # done(ok) 已展示成功页；这里只刷状态
            elif result == "recovery_stall":
                self._ev("stall")
            elif result == "dfu_back":
                self._ev("dfu_back")
        threading.Thread(target=worker, daemon=True).start()


def main():
    api = Api()
    html = os.path.join(TOOL_DIR, "ui", "index.html")
    window = webview.create_window(
        "玄烨品果 · 一键开机", html,
        js_api=api, width=580, height=880, min_size=(520, 760),
        background_color="#0a0c13")
    api.window = window
    webview.start()


if __name__ == "__main__":
    main()
