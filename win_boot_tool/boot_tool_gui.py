#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
玩机乐园 · 一键开机（图形界面版）
引擎逻辑复用 boot_tool.py（同目录），界面 tkinter（Python 自带）。
构建：pyinstaller -w -F -n boot_tool boot_tool_gui.py  （-w 无黑窗口）
"""
import os
import sys
import time
import glob
import queue
import threading
import traceback

TOOL_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
sys.path.insert(0, TOOL_DIR)

import tkinter as tk
from tkinter import ttk, messagebox

import boot_tool as engine  # 复用已验证的引擎

APP_TITLE = f"{engine.BRAND['name']} · 一键开机"
GREEN = "#2e9e4f"
RED = "#c0392b"
BLUE = "#2469a8"
BG = "#f5f6f8"


class App:
    def __init__(self, root):
        self.root = root
        root.title(APP_TITLE)
        root.geometry("560x640")
        root.configure(bg=BG)
        root.minsize(520, 600)

        self.q = queue.Queue()
        self.worker = None

        self._build_ui()
        self.root.after(100, self._drain_queue)

    # ---------- UI ----------
    def _build_ui(self):
        # 标题栏
        head = tk.Frame(self.root, bg=BG)
        head.pack(fill="x", padx=24, pady=(18, 6))
        tk.Label(head, text="一键开机", font=("PingFang SC", 26, "bold"),
                 bg=BG, fg="#222").pack(side="left")
        tk.Label(head, text=engine.BRAND["slogan"], font=("PingFang SC", 11),
                 bg=BG, fg="#888").pack(side="left", padx=(10, 0), pady=(10, 0))

        # 步骤大字提示
        self.step_var = tk.StringVar(value="准备就绪")
        tk.Label(self.root, textvariable=self.step_var, font=("PingFang SC", 16, "bold"),
                 bg=BG, fg=BLUE, wraplength=500, justify="left").pack(padx=24, pady=(8, 2), anchor="w")

        # 详细指引文本区
        self.guide = tk.Text(self.root, height=12, font=("PingFang SC", 12), bd=0,
                             bg="#ffffff", fg="#333", padx=16, pady=12, spacing2=6,
                             wrap="word", state="disabled")
        self.guide.pack(fill="both", expand=True, padx=24, pady=8)

        # 进度条
        self.prog = ttk.Progressbar(self.root, mode="determinate", maximum=100)
        self.prog.pack(fill="x", padx=24, pady=(0, 8))

        # 按钮区
        btns = tk.Frame(self.root, bg=BG)
        btns.pack(fill="x", padx=24, pady=(4, 6))
        self.go_btn = tk.Button(btns, text="开 始", font=("PingFang SC", 15, "bold"),
                                bg=GREEN, fg="white", activebackground="#257a3d",
                                activeforeground="white", bd=0, height=2,
                                cursor="hand2", command=self.on_start)
        self.go_btn.pack(side="left", fill="x", expand=True)
        self.diag_btn = tk.Button(btns, text="诊 断", font=("PingFang SC", 13),
                                  bg="#e8e8ec", fg="#444", activebackground="#d8d8de",
                                  bd=0, height=2, width=8, cursor="hand2",
                                  command=self.on_diag)
        self.diag_btn.pack(side="left", padx=(10, 0))

        # 底部品牌/联系
        foot = tk.Frame(self.root, bg=BG)
        foot.pack(fill="x", padx=24, pady=(2, 12))
        contact = f"{engine.BRAND['contact']}    {engine.BRAND['site']}"
        tk.Label(foot, text=contact, font=("PingFang SC", 10), bg=BG, fg="#999").pack()
        self.status_var = tk.StringVar(value="")
        tk.Label(foot, textvariable=self.status_var, font=("PingFang SC", 10),
                 bg=BG, fg=BLUE).pack()

        # 二维码（可选：卖家放 二维码.png 在工具旁，成功页显示）
        self.qr_img = None
        for name in ("二维码.png", "qr.png", "群二维码.png"):
            p = os.path.join(TOOL_DIR, name)
            if os.path.isfile(p):
                try:
                    from PIL import Image, ImageTk  # 可选依赖
                    img = Image.open(p)
                    img.thumbnail((150, 150))
                    self.qr_img = ImageTk.PhotoImage(img)
                except Exception:
                    self.qr_img = None
                break

    # ---------- UI 工具 ----------
    def set_step(self, text, color=BLUE):
        self.step_var.set(text)
        for w in self.root.winfo_children():
            pass
        # 直接改色：重建 label 成本高，用 tag 不便，这里简单重设 fg
        for w in self.root.winfo_children():
            if isinstance(w, tk.Label) and w["textvariable"]:
                try:
                    w.configure(fg=color)
                except tk.TclError:
                    pass

    def set_guide(self, lines):
        self.guide.configure(state="normal")
        self.guide.delete("1.0", "end")
        for line in lines:
            self.guide.insert("end", line + "\n")
        self.guide.configure(state="disabled")

    def set_status(self, text):
        self.status_var.set(text)

    def _drain_queue(self):
        try:
            while True:
                ev, data = self.q.get_nowait()
                if ev == "step":
                    self.set_step(data)
                elif ev == "guide":
                    self.set_guide(data)
                elif ev == "progress":
                    self.prog["value"] = data
                elif ev == "status":
                    self.set_status(data)
                elif ev == "done":
                    self._on_done(data)
                elif ev == "postboot":
                    self._watch_postboot()
                elif ev == "postboot_result":
                    self._on_postboot_result(data)
        except queue.Empty:
            pass
        self.root.after(100, self._drain_queue)

    def _on_done(self, ok):
        self.go_btn.configure(state="normal", text="开 始")
        if ok:
            self.set_step("✓ 开机指令已发送", GREEN)
            self.set_guide([
                "手机正在启动，请等待 10-30 秒屏幕亮起。",
                "",
                "【提醒】",
                "· 关机 / 没电后，需要重新运行本工具",
                "· 引导包与你的手机一一绑定，请备份保存",
            ])
            if self.qr_img:
                top = tk.Toplevel(self.root)
                top.title("加入交流群")
                tk.Label(top, image=self.qr_img).pack(padx=20, pady=20)
                tk.Label(top, text=f"扫码加入 {engine.BRAND['name']} 交流群",
                         font=("PingFang SC", 12)).pack(pady=(0, 16))
        else:
            self.set_step("✗ 未成功", RED)
        self.worker = None

    def _watch_postboot(self):
        """发送成功后确认设备去向（后台线程，不卡界面）"""
        def worker():
            def on_check(pids):
                tag = {0x1227: "DFU", 0x1281: "恢复", 0x12A8: "已开机"}.get(
                    next(iter(pids), None), "等待") if len(pids) <= 1 else "等待"
                self.q.put(("status", f"确认开机状态：{tag}..."))
            result = engine.detect_post_boot(on_check=on_check)
            self.q.put(("postboot_result", result))
        threading.Thread(target=worker, daemon=True).start()

    def _on_postboot_result(self, result):
        if result == "booted":
            self.set_step("✓ 开机成功", GREEN)
            self.set_status("已确认手机正常开机")
        elif result == "recovery_stall":
            self.set_step("✗ 未能自动开机", RED)
            self.set_guide([
                "手机停留在恢复模式，未能自动开机。",
                "",
                "最常见原因：引导包版本与手机当前系统不一致",
                "（例如手机之后刷过其他版本）。",
                "请联系客服核对手机当前的 iOS 版本，",
                "重新制作对应版本的引导包。",
            ])
        elif result == "dfu_back":
            self.set_step("✗ 本次开机未成功", RED)
            self.set_guide(["设备退回了 DFU 模式。", "请重新点「开始」再试一次。"])
        else:
            self.set_status("未能确认状态；屏幕亮起即成功")

    # ---------- 事件 ----------
    def on_start(self):
        if self.worker and self.worker.is_alive():
            return
        self.go_btn.configure(state="disabled", text="进行中...")
        self.prog["value"] = 0
        self.worker = threading.Thread(target=self._run, daemon=True)
        self.worker.start()

    def on_diag(self):
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                engine.selftest()
        except Exception:
            buf.write(traceback.format_exc())
        self.root.clipboard_clear()
        self.root.clipboard_append(buf.getvalue())
        messagebox.showinfo(
            "诊断结果",
            "诊断完成，结果已复制到剪贴板。\n\n请粘贴发给客服（微信/QQ 均可）。")

    # ---------- 引擎流程（后台线程） ----------
    def _run(self):
        q = self.q
        try:
            q.put(("step", "检查引导包..."))
            boot_dir, _tmp = engine.load_boot_bundle()
            if not boot_dir:
                q.put(("step", "✗ 没有找到引导包"))
                q.put(("guide", [
                    "请把卖家发给你的引导包（boot 文件夹或 zip）",
                    "放到本工具所在的文件夹里，然后点「开始」重试。",
                    "",
                    "文件夹位置：" + TOOL_DIR,
                ]))
                q.put(("done", False))
                return
            q.put(("status", "引导包已就绪"))

            # 等待 DFU + 破解
            q.put(("step", "第 1 步：让手机进入 DFU 模式"))
            q.put(("guide", [
                "手机用数据线连接电脑，然后：",
                "  1. 按一下「音量+」松开",
                "  2. 按一下「音量-」松开",
                "  3. 按住「电源键」直到屏幕完全变黑",
                "  4. 黑屏后，同时按住「电源键+音量-」数 5 秒",
                "  5. 松开「电源键」，继续按住「音量-」约 10 秒",
                "",
                "屏幕保持全黑 = 成功（出现苹果标志请重来）",
                "进入后工具会自动继续...",
            ]))
            pico_hinted = False
            dfu_hinted = False
            dev = None
            while not dev:
                devs = engine.dfu_devices()
                hit = None
                for d in devs:
                    if "PWND:[" in engine.serial_of(d):
                        hit = d
                        break
                if hit:
                    dev = hit
                    break
                if devs and not pico_hinted:
                    pico_hinted = True
                    q.put(("step", "第 2 步：用 Pi Pico 破解"))
                    q.put(("guide", [
                        "已检测到 DFU 设备，但还未破解：",
                        "",
                        "  1. 把手机从电脑拔下",
                        "  2. 连接到 Pi Pico 破解器，等灯闪完",
                        "  3. 把手机插回电脑",
                        "",
                        "（期间手机屏幕保持全黑）",
                    ]))
                elif not devs and not dfu_hinted:
                    dfu_hinted = True  # 首条指引已给，静默等待
                    q.put(("status", "等待 DFU 设备..."))
                time.sleep(1.0)

            q.put(("step", "设备已就绪，正在匹配..."))
            ecid = engine.ecid_of(dev)
            q.put(("status", f"ECID: {ecid}"))
            picked = engine.pick_boot_files(boot_dir, ecid)
            if not picked:
                q.put(("step", "✗ 引导包与手机不匹配"))
                q.put(("guide", [
                    "这个引导包不属于当前手机（ECID 不一致）。",
                    "请确认拿错了包，或联系客服重新制作。",
                ]))
                q.put(("done", False))
                return
            _identifier, version, ibss = picked
            q.put(("status", f"iOS {version}"))
            q.put(("step", f"第 3 步：发送引导文件（iOS {version}）"))
            q.put(("guide", ["正在发送，请勿拔线...", ""]))

            # 发送（进度回调）
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
                q.put(("progress", sent * 100 // total))
            dev.ctrl_transfer(0x21, engine.DFU_DNLOAD, 0, 0, None, 100)
            dev.ctrl_transfer(0x21, engine.CUSTOM_BOOT, 0, 0, None, 100)
            try:
                dev.ctrl_transfer(0x21, engine.DFU_ABORT, 0, 0, None, 100)
            except engine.usb.core.USBError:
                pass
            # 以「设备离开 DFU」判定成功（Windows 实测确立的判据）
            ok = False
            deadline = time.time() + 8
            while time.time() < deadline:
                if not engine.dfu_devices():
                    ok = True
                    break
                time.sleep(1)
            q.put(("progress", 100))
            q.put(("done", ok))
            if ok:
                # 继续确认开机去向（booted / 卡恢复模式 / 退回 DFU）
                q.put(("postboot", None))
        except Exception as e:
            q.put(("step", f"✗ 出错：{e}"))
            q.put(("guide", ["请截图本窗口发给客服。", "", traceback.format_exc()[:500]]))
            q.put(("done", False))


def run_selftest_dialog():
    """--selftest 入口：无主窗口，弹窗展示自检结果并复制到剪贴板（-w 打包无控制台）"""
    root = tk.Tk()
    root.withdraw()
    import io
    from contextlib import redirect_stdout
    buf = io.StringIO()
    try:
        with redirect_stdout(buf):
            engine.selftest()
    except Exception:
        buf.write(traceback.format_exc())
    text = buf.getvalue()
    root.clipboard_clear()
    root.clipboard_append(text)
    root.update()  # 让剪贴板在销毁前生效
    messagebox.showinfo(
        "自检结果",
        text + "\n\n（结果已复制到剪贴板，请粘贴发给客服）")
    root.destroy()


def main():
    if "--selftest" in sys.argv:
        return run_selftest_dialog()
    root = tk.Tk()
    try:
        from tkinter import font as tkfont
        for fam in ("PingFang SC", "Microsoft YaHei UI", "Microsoft YaHei"):
            try:
                if fam in tkfont.families():
                    tkfont.nametofont("TkDefaultFont").configure(family=fam)
                    break
            except tk.TclError:
                continue
    except Exception:
        pass
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
