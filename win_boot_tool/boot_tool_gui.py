#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
玄烨品果 · 一键开机（图形界面版）
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

if os.name == "nt":
    try:
        import winsound
    except ImportError:
        winsound = None
else:
    winsound = None

import boot_tool as engine  # 复用已验证的引擎

# ---- iOS 风格配色 ----
BG = "#f5f5f7"          # 背景
CARD = "#ffffff"        # 卡片
INK = "#1d1d1f"         # 主文字
INK2 = "#86868b"        # 次要文字
HAIR = "#e5e5ea"        # 分隔线/描边
BLUE = "#007aff"        # 主色
BLUE_D = "#0062d6"      # 主色按下
GREEN = "#34c759"       # 成功
RED = "#ff3b30"         # 失败

FONT = "Microsoft YaHei UI" if os.name == "nt" else "PingFang SC"

APP_TITLE = f"{engine.BRAND['name']} · 一键开机"


class App:
    def __init__(self, root):
        self.root = root
        root.title(APP_TITLE)
        root.configure(bg=BG)
        root.geometry("540x740")
        root.minsize(500, 700)

        self.q = queue.Queue()
        self.worker = None

        self._build_ui()
        self.root.after(100, self._drain_queue)

    # ---------- UI ----------
    def _build_ui(self):
        # 窗口图标
        ico = os.path.join(TOOL_DIR, "brand.png")
        if os.path.isfile(ico):
            try:
                self._icon_img = tk.PhotoImage(file=ico)
                self.root.iconphoto(True, self._icon_img)
            except Exception:
                pass

        # 顶部品牌区
        head = tk.Frame(self.root, bg=BG)
        head.pack(fill="x", padx=28, pady=(26, 4))
        tk.Label(head, text=engine.BRAND["name"], font=(FONT, 25, "bold"),
                 bg=BG, fg=INK).pack(anchor="w")
        tk.Label(head, text=f"{engine.BRAND['slogan']}    一键开机 · 自动引导",
                 font=(FONT, 11), bg=BG, fg=INK2).pack(anchor="w", pady=(2, 0))

        # 步骤标题
        self.step_var = tk.StringVar(value="准备就绪")
        self.step_label = tk.Label(self.root, textvariable=self.step_var,
                                   font=(FONT, 16, "bold"), bg=BG, fg=BLUE,
                                   wraplength=470, justify="left")
        self.step_label.pack(padx=28, pady=(14, 8), anchor="w")

        # 指引卡片
        card = tk.Frame(self.root, bg=HAIR)
        card.pack(fill="both", expand=True, padx=28, pady=(0, 12))
        self.guide = tk.Text(card, height=11, font=(FONT, 12), bd=0,
                             bg=CARD, fg=INK, padx=16, pady=14, spacing2=7,
                             spacing1=2, wrap="word", state="disabled",
                             insertbackground=CARD, selectbackground="#cce4ff")
        self.guide.pack(fill="both", expand=True, padx=1, pady=1)

        # 进度条 + 百分比
        prog_wrap = tk.Frame(self.root, bg=BG)
        prog_wrap.pack(fill="x", padx=28, pady=(0, 4))
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("Slim.Horizontal.TProgressbar",
                        troughcolor="#e5e5ea", background=BLUE,
                        borderwidth=0, thickness=6)
        self.prog = ttk.Progressbar(prog_wrap, style="Slim.Horizontal.TProgressbar",
                                    mode="determinate", maximum=100)
        self.prog.pack(fill="x", side="left", expand=True)
        self.pct_var = tk.StringVar(value="")
        tk.Label(prog_wrap, textvariable=self.pct_var, font=(FONT, 11),
                 bg=BG, fg=INK2, width=5, anchor="e").pack(side="right", padx=(10, 0))

        # 数秒助手（DFU 阶段显示）
        self.timer_row = tk.Frame(self.root, bg=BG)
        tk.Label(self.timer_row, text="数秒助手：", font=(FONT, 11),
                 bg=BG, fg=INK2).pack(side="left")
        for secs, hint in ((5, "电源+音量-"), (10, "音量-")):
            b = tk.Button(self.timer_row,
                          text=f"{secs} 秒（{hint}）", font=(FONT, 11),
                          bg=CARD, fg=BLUE, activebackground="#f2f2f7",
                          bd=0, cursor="hand2", padx=10, pady=3,
                          highlightbackground=HAIR, highlightthickness=1,
                          command=lambda s=secs: self.start_countdown(s))
            b.pack(side="left", padx=(8, 0))

        # 状态行
        self.status_var = tk.StringVar(value="")
        self._status_label = tk.Label(self.root, textvariable=self.status_var,
                                      font=(FONT, 10), bg=BG, fg=INK2)
        self._status_label.pack(padx=28, pady=(2, 10), anchor="w")

        # 按钮区
        btns = tk.Frame(self.root, bg=BG)
        btns.pack(fill="x", padx=28, pady=(0, 10))
        self.go_btn = tk.Button(btns, text="开 始", font=(FONT, 15, "bold"),
                                bg=BLUE, fg="#ffffff", activebackground=BLUE_D,
                                activeforeground="#ffffff", bd=0, height=2,
                                cursor="hand2", command=self.on_start)
        self.go_btn.pack(side="left", fill="x", expand=True)
        self.drv_btn = tk.Button(btns, text="安装驱动", font=(FONT, 11),
                                 bg=CARD, fg=RED, activebackground="#f2f2f7",
                                 bd=0, height=2, width=9, cursor="hand2",
                                 highlightbackground=HAIR, highlightthickness=1,
                                 command=self.on_install_driver)
        self.drv_btn.pack(side="left", padx=(10, 0))
        self.diag_btn = tk.Button(btns, text="诊 断", font=(FONT, 12),
                                  bg=CARD, fg=INK, activebackground="#f2f2f7",
                                  bd=0, height=2, width=7, cursor="hand2",
                                  highlightbackground=HAIR, highlightthickness=1,
                                  command=self.on_diag)
        self.diag_btn.pack(side="left", padx=(10, 0))

        # 底部品牌/联系：QQ 可点击复制
        foot = tk.Frame(self.root, bg=BG)
        foot.pack(fill="x", padx=28, pady=(0, 14))
        tk.Label(foot, text=f"{engine.BRAND['name']} · {engine.BRAND['site']}    v{engine.VERSION}",
                 font=(FONT, 10), bg=BG, fg=INK2).pack(side="left")
        self.qq_label = tk.Label(foot, text="💬 " + engine.BRAND["contact"],
                                 font=(FONT, 10), bg=BG, fg=BLUE,
                                 cursor="hand2")
        self.qq_label.pack(side="right")
        self.qq_label.bind("<Button-1>", lambda e: self.copy_contact())

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

        info = engine.bundle_summary()
        self._stage1_lines = None
        if info:
            ecid_tail = info["ecid"][-6:].upper()
            self.set_guide([
                "欢迎使用一键开机。",
                "",
                f"📦 引导包：{info['identifier']} · iOS {info['version']}",
                f"🔗 已绑定你的手机（识别码 {ecid_tail}）",
                "",
                "把手机用数据线连接电脑后，点「开始」。",
            ])
        else:
            self.set_guide([
                "未找到引导包！",
                "",
                "请把卖家发给你的引导包（zip 或 boot 文件夹）",
                "放到本工具所在的文件夹里，再重新打开本工具。",
                "",
                "文件夹位置：" + TOOL_DIR,
            ])

    def copy_contact(self):
        qq = "".join(c for c in engine.BRAND["contact"] if c.isdigit())
        self.root.clipboard_clear()
        self.root.clipboard_append(qq)
        self.set_status(f"客服 QQ 已复制（{qq}），请打开 QQ 添加/粘贴发送")
        if winsound:
            try:
                winsound.MessageBeep()
            except Exception:
                pass

    def show_timer_row(self, show):
        if show:
            self.timer_row.pack(fill="x", padx=28, pady=(0, 4),
                                before=self._status_label)
        else:
            self.timer_row.pack_forget()

    def start_countdown(self, secs):
        """大字倒计时：DFU 第4步按 5 秒（电源+音量-），第5步按 10 秒（音量-）"""
        if self._stage1_lines is None:
            return
        if winsound:
            try:
                winsound.Beep(1200, 120)
            except Exception:
                pass

        def restore():
            if winsound:
                try:
                    winsound.Beep(1600, 250)
                except Exception:
                    pass
            self.set_guide(self._stage1_lines)
            self.set_status("倒计时结束——按指引继续下一步")

        def tick(n):
            if n <= 0:
                self.root.after(300, restore)
                return
            self.guide.configure(state="normal")
            self.guide.delete("1.0", "end")
            self.guide.tag_configure("big", font=(FONT, 88, "bold"),
                                     foreground=BLUE, justify="center")
            self.guide.tag_configure("cap", font=(FONT, 13),
                                     foreground=INK2, justify="center")
            self.guide.insert("end", "\n", "cap")
            self.guide.insert("end", f" {n} ", "big")
            self.guide.insert("end", "\n\n保持按住，不要松手…", "cap")
            self.guide.configure(state="disabled")
            self.root.after(1000, lambda: tick(n - 1))

        tick(secs)
        self.set_status(f"{secs} 秒倒计时中——按住对应的按键！")

    # ---------- UI 工具 ----------
    def set_step(self, text, color=BLUE):
        self.step_var.set(text)
        self.step_label.configure(fg=color)

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
                    self.pct_var.set(f"{data}%")
                elif ev == "status":
                    self.set_status(data)
                elif ev == "done":
                    self._on_done(data)
                elif ev == "postboot":
                    self._watch_postboot()
                elif ev == "postboot_result":
                    self._on_postboot_result(data)
                elif ev == "show_timer":
                    self.show_timer_row(data)
                elif ev == "stage1_lines":
                    self._stage1_lines = data
        except queue.Empty:
            pass
        self.root.after(100, self._drain_queue)

    def _on_done(self, ok):
        self.go_btn.configure(state="normal", text="开 始")
        if ok:
            self.set_step("开机指令已发送", GREEN)
            self.set_guide([
                "正在确认开机状态，请稍候...",
                "",
                "【先别拔线】",
                "· 手机正在启动，等待屏幕亮起（约 10-30 秒）",
                "· 关机 / 没电后，需要重新运行本工具",
            ])
        else:
            self.set_step("未成功", RED)
            self.pct_var.set("")
        self.worker = None

    def _watch_postboot(self):
        """发送成功后确认设备去向（后台线程，不卡界面）"""
        def worker():
            def on_check(pids):
                tag = {0x1227: "DFU", 0x1281: "恢复模式", 0x12A8: "已开机"}.get(
                    next(iter(pids), None), "等待") if len(pids) <= 1 else "等待"
                self.q.put(("status", f"确认开机状态：{tag}..."))
            result = engine.detect_post_boot(on_check=on_check)
            self.q.put(("postboot_result", result))
        threading.Thread(target=worker, daemon=True).start()

    def _on_postboot_result(self, result):
        if result == "booted":
            self.set_step("✓ 开机成功", GREEN)
            self.pct_var.set("100%")
            self.prog["value"] = 100
            self.set_status("已确认手机正常开机，可正常使用")
            self.set_guide([
                "开机成功！手机已进入系统，可以正常使用。",
                "",
                "【日常提醒】",
                "· 关机 / 没电后，需要重新运行本工具开机",
                "· 引导包与你的手机一一绑定，请备份保存",
                "· 遇到问题：点「诊断」，结果发给客服即可",
            ])
            self._show_qr()
        elif result == "recovery_stall":
            self.set_step("✗ 未能自动开机", RED)
            self.set_guide([
                "手机停留在恢复模式，未能自动开机。",
                "",
                "最常见原因：引导包版本与手机当前系统不一致",
                "（例如手机之后刷过其他版本）。",
                "",
                "请联系客服核对手机当前的 iOS 版本，",
                "重新制作对应版本的引导包。",
                f"（{engine.BRAND['contact']}）",
            ])
        elif result == "dfu_back":
            self.set_step("✗ 本次开机未成功", RED)
            self.set_guide(["设备退回了 DFU 模式。", "请重新点「开始」再试一次。"])
        else:
            self.set_status("未能确认状态；屏幕亮起即成功")

    def _show_qr(self):
        if self.qr_img:
            top = tk.Toplevel(self.root)
            top.title("加入交流群")
            top.configure(bg=CARD)
            tk.Label(top, image=self.qr_img, bg=CARD).pack(padx=24, pady=(24, 8))
            tk.Label(top, text=f"扫码加入 {engine.BRAND['name']} 交流群",
                     font=(FONT, 12), bg=CARD, fg=INK).pack(pady=(0, 18))

    # ---------- 事件 ----------
    def on_start(self):
        if self.worker and self.worker.is_alive():
            return
        self.go_btn.configure(state="disabled", text="进行中...")
        self.prog["value"] = 0
        self.pct_var.set("0%")
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

    def on_install_driver(self):
        """一键运行 安装驱动.bat（自动提权：证书注册+强制绑定，Zadig 兜底）"""
        bat = os.path.join(TOOL_DIR, "安装驱动.bat")
        if not os.path.isfile(bat):
            messagebox.showwarning("缺少文件", "未找到 安装驱动.bat，请联系客服。")
            return
        self.set_status("正在运行驱动安装（请在弹出的窗口里允许管理员权限）...")
        try:
            os.startfile(bat)  # noqa: S606 bat 自带 UAC 提权
        except Exception as e:
            messagebox.showerror("启动失败", str(e))

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
            stage1_lines = [
                "手机用数据线连接电脑，然后：",
                "  1. 按一下「音量+」松开",
                "  2. 按一下「音量-」松开",
                "  3. 按住「电源键」直到屏幕完全变黑",
                "  4. 黑屏后，同时按住「电源键+音量-」数 5 秒",
                "  5. 松开「电源键」，继续按住「音量-」约 10 秒",
                "",
                "屏幕保持全黑 = 成功（出现苹果标志请重来）",
                "进入后工具会自动继续...",
                "",
                "💡 数不准秒？用下方「数秒助手」按钮，开按的那一瞬间点它",
            ]
            q.put(("stage1_lines", stage1_lines))
            q.put(("guide", stage1_lines))
            q.put(("show_timer", True))
            pico_hinted = False
            dfu_hinted = False
            driver_hinted_at = 0.0
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
                    q.put(("show_timer", False))
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
                elif not devs:
                    # 每 10 秒做一次驱动失明检查（手机在 DFU 但工具看不见）
                    if time.time() - driver_hinted_at > 10 and engine.dfu_driver_blind():
                        driver_hinted_at = time.time()
                        q.put(("step", "✗ 正在自动安装驱动"))
                        q.put(("guide", [
                            "手机已进入 DFU，但驱动被 Apple 驱动占用。",
                            "",
                            "已自动启动驱动安装，",
                            "请在弹出的窗口中点「是」允许管理员权限。",
                            "安装完成后这里会自动继续。",
                            "",
                            "（若无窗口弹出，请点右下角红色「安装驱动」按钮）",
                        ]))
                        bat = os.path.join(TOOL_DIR, "安装驱动.bat")
                        if os.path.isfile(bat):
                            try:
                                os.startfile(bat)  # noqa: S606
                            except Exception:
                                pass
                    elif not dfu_hinted:
                        dfu_hinted = True  # 首条指引已给，静默等待
                        q.put(("status", "等待 DFU 设备..."))
                time.sleep(1.0)

            q.put(("step", "设备已就绪，正在匹配..."))
            q.put(("show_timer", False))
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
        for fam in ("Microsoft YaHei UI", "PingFang SC"):
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
