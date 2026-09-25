#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
按订单生成客户引导包
用法：
  python3 make_order_package.py                 # 交互式：列出仓库可选
  python3 make_order_package.py --ecid 0x0006216e3c05402e --name 张三
  python3 make_order_package.py --id iPhone11,8 --ver 14.3 --ecid 0x001e... --name 李四
输出：boot_<客户名>_<机型>_<版本>.zip（放当前目录，直接微信/QQ 发送）
"""
import argparse
import glob
import os
import sys
import time
import zipfile

def find_repo():
    """boot/ 仓库定位：脚本旁 → 脚本上级（标准仓库布局）→ 当前目录"""
    here = os.path.dirname(os.path.abspath(__file__))
    for cand in (os.path.join(here, "boot"), os.path.join(here, "..", "boot"), os.path.join(os.getcwd(), "boot")):
        if glob.glob(os.path.join(cand, "0x*.txt")):
            return os.path.abspath(cand)
    print("[!] 找不到 boot/ 仓库（需要在脚本旁、上级目录或当前目录存在含 0x*.txt 的 boot 文件夹）")
    sys.exit(1)


REPO = find_repo()

README_TMPL = """「一键开机」引导启动包 —— 请妥善保存
================================================

客户：{name}
机型：{identifier}（iOS {version}）
设备 ECID：{ecid}
出品：{brand}（{site}）

一、准备（只需一次）
  1. 在电脑上安装好「一键开机」工具（boot_tool.exe / boot_tool.py）
  2. 把本压缩包解压，将里面的 boot 文件夹放到工具旁边（同一层）
  3. 手机进入 DFU 模式后用 Pi Pico 破解器完成破解（购买时附赠说明）

二、每次开机（关机/没电后都需要）
  1. 双击运行工具
  2. 按提示让手机进 DFU（音量+ → 音量- → 长按电源黑屏 → 电源+音量- 5 秒 → 松电源按音量- 10 秒）
  3. 连接 Pi Pico 破解，再插回电脑
  4. 工具自动发送引导，等待手机开机（10-30 秒）

三、重要提醒
  - 本引导包仅适用于上面标注的这一台手机（ECID 绑定），请勿转给他人使用
  - 引导包和工具请至少备份两处（网盘/U盘）：文件丢失后手机无法开机，需重新下单制作
  - 遇到问题：运行 boot_tool --selftest，把结果截图发给客服（{contact}）
  - 任何时刻刷回官方最新版系统即可恢复正常手机（兜底方案，永远有效）
"""


BRAND = {
    "name": "玄烨品果",                     # 与 boot_tool.py 的 BRAND 保持一致
    "contact": "客服 QQ：1544075460",
    "site": "dkxuanye.cn",
}


def list_repo():
    """扫描 boot/ 仓库，返回 [(ecid_file, version, identifier)]"""
    entries = []
    for f in sorted(glob.glob(os.path.join(REPO, "0x*.txt"))):
        with open(f, encoding="utf-8", errors="ignore") as fh:
            ver = fh.read().strip()
        ecid = os.path.basename(f)[:-4]
        idirs = glob.glob(os.path.join(REPO, "*", ver, "iBSS.boot"))
        for ibss in idirs:
            identifier = os.path.basename(os.path.dirname(os.path.dirname(ibss)))
            entries.append((ecid, ver, identifier, ibss))
    return entries


def interactive_pick():
    entries = list_repo()
    if not entries:
        print("[!] boot/ 仓库为空，没有可打包的设备")
        sys.exit(1)
    print("boot/ 仓库现有设备：")
    for i, (ecid, ver, identifier, _) in enumerate(entries, 1):
        print(f"  {i}) {identifier:<12} iOS {ver:<8} {ecid}")
    while True:
        try:
            n = int(input("选择序号: ").strip())
            if 1 <= n <= len(entries):
                return entries[n - 1]
        except ValueError:
            pass
        print("  无效输入，请输入序号")


def main():
    if os.name == "nt":
        os.system("chcp 65001 >nul")
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

    ap = argparse.ArgumentParser()
    ap.add_argument("--ecid", help="设备 ECID（如 0x0006216e3c05402e）")
    ap.add_argument("--id", dest="identifier", help="机型（如 iPhone11,8）")
    ap.add_argument("--ver", help="版本（如 14.3）")
    ap.add_argument("--name", default="客户", help="客户名/订单号（用于文件命名，默认「客户」")
    args = ap.parse_args()

    # 定位目标
    if args.ecid:
        ecid_file = os.path.join(REPO, f"{args.ecid}.txt")
        if not os.path.isfile(ecid_file):
            # 容错：不带 0x 前缀
            ecid_file = os.path.join(REPO, f"0x{args.ecid.lstrip('0x0X')}.txt")
        if not os.path.isfile(ecid_file):
            print(f"[!] boot/ 里找不到 {args.ecid} 的版本记录")
            sys.exit(1)
        with open(ecid_file, encoding="utf-8") as fh:
            ver = args.ver or fh.read().strip()
        identifier = args.identifier
        if identifier:
            ibss = os.path.join(REPO, identifier, ver, "iBSS.boot")
            if not os.path.isfile(ibss):
                print(f"[!] 找不到 {ibss}")
                sys.exit(1)
        else:
            cands = glob.glob(os.path.join(REPO, "*", ver, "iBSS.boot"))
            if len(cands) != 1:
                ids = [os.path.basename(os.path.dirname(os.path.dirname(c))) for c in cands]
                if len(cands) > 1 and sys.stdin.isatty():
                    print(f"[?] iOS {ver} 有多个机型引导文件：")
                    for i, (c, n) in enumerate(zip(cands, ids), 1):
                        print(f"   {i}) {n}")
                    while True:
                        try:
                            n = int(input("选择序号: ").strip())
                            if 1 <= n <= len(cands):
                                cands = [cands[n - 1]]
                                break
                        except ValueError:
                            pass
                        print("   无效输入")
                else:
                    print(f"[!] 版本 {ver} 匹配到 {len(cands)} 个机型（{ids}），请用 --id 指定")
                    sys.exit(1)
            ibss = cands[0]
            identifier = os.path.basename(os.path.dirname(os.path.dirname(ibss)))
        ecid = os.path.basename(ecid_file)[:-4]
    else:
        ecid, ver, identifier, ibss = interactive_pick()

    out = f"boot_{args.name}_{identifier}_{ver}.zip"
    if os.path.exists(out):
        os.remove(out)

    def zi(arc, st, is_dir=False):
        dt = time.localtime(st.st_mtime)[:6]
        z = zipfile.ZipInfo(arc, date_time=dt)
        z.flag_bits |= 0x800
        z.external_attr = (st.st_mode & 0xFFFF) << 16
        if is_dir:
            z.external_attr |= 0x10
        else:
            z.compress_type = zipfile.ZIP_DEFLATED
        return z

    readme = README_TMPL.format(
        name=args.name, identifier=identifier, version=ver, ecid=ecid,
        contact=BRAND["contact"], brand=BRAND["name"], site=BRAND["site"],
    )
    ecid_txt = os.path.join(REPO, f"{ecid}.txt")
    with zipfile.ZipFile(out, "w") as z:
        z.writestr(zi("使用说明.txt", os.stat(ibss)), readme)
        with open(ibss, "rb") as f:
            z.writestr(zi(f"boot/{identifier}/{ver}/iBSS.boot", os.stat(ibss)), f.read())
        with open(ecid_txt, "rb") as f:
            z.writestr(zi(f"boot/{ecid}.txt", os.stat(ecid_txt)), f.read())

    size_kb = os.path.getsize(out) // 1024
    print(f"[✓] 已生成：{out}（{size_kb} KB）")
    print(f"    内容：boot/{identifier}/{ver}/iBSS.boot + boot/{ecid}.txt + 使用说明.txt")
    print(f"    发给客户：连同 boot_tool 工具一起发送")


if __name__ == "__main__":
    main()
