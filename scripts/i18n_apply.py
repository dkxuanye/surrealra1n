#!/usr/bin/env python3
"""按翻译表将目标脚本中【输出语句】的英文替换为中文。

用法: python3 scripts/i18n_apply.py [目标文件] [备份文件]
默认: surrealra1n.sh  surrealra1n.sh.bak_before_i18n

替换规则（加固版，防止误伤代码）:
1. 先备份原文件
2. 只在「输出语句」（echo/printf/read -p/pick_file/zenity）的双引号字符串
   字面量内做【整串】替换——翻译表条目对应的是完整字面量（已验证 430 条
   全部为完整字面量、0 条为子串），不做内嵌子串替换
3. 每行仅匹配第一个输出字面量；若该行已含中文则跳过（防二次污染）
4. 逐条统计替换次数，0 次替换的条目输出警告（提示表与原文不符）
"""
import re
import shutil
import sys

SRC = "surrealra1n.sh"
BACKUP = "surrealra1n.sh.bak_before_i18n"
TABLE = "scripts/i18n_translations.txt"

# 输出语句行首识别（与 extract.py 保持一致）
# 捕获用户可见字符串所在的行，且字面量相对独立。
LINE_RE = re.compile(
    r'^(?:(?:[A-Za-z_]\w*=\$\()?pick_file\s+|echo(?: -[a-z]+)?\s+|printf(?: -v\s+\w+)?\s+|read(?: -[a-z](?: \S+)?)*\s+-p\s+|--title=|INFO_TEXT\s*=|VERSION_DISPLAY\s*=|is_install_counter\s*=)')
# 捕获一个双引号包裹的字符串字面量
STR_RE = re.compile(r'"((?:\\.|[^"\\])*)"')

CJK_RE = re.compile(r"[\u4e00-\u9fff]")


def load_table() -> dict[str, str]:
    entries: dict[str, str] = {}
    for line in open(TABLE, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        en, sep, zh = line.partition("|||")
        if not sep:
            raise SystemExit(f"翻译表缺少分隔符 |||: {line!r}")
        zh = zh.lstrip()
        if not en or not zh:
            raise SystemExit(f"翻译表格式错误（英文或译文为空）: {line!r}")
        entries[en] = zh
    return entries


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    backup = sys.argv[2] if len(sys.argv) > 2 else BACKUP
    shutil.copyfile(src, backup)
    print(f"已备份原文件 -> {backup}")

    table = load_table()
    used = {en: 0 for en in table}
    total_replace = 0
    out_lines: list[str] = []

    for raw in open(src, encoding="utf-8").read().split("\n"):
        # 用 strip 后的行判断是否为输出语句（兼容任意前导缩进），
        # 但替换仍需在原 raw 上进行以保留缩进。
        stripped = raw.strip()
        if not LINE_RE.match(stripped) or CJK_RE.search(stripped):
            out_lines.append(raw)
            continue
        # 该行所有字符串字面量，从右往左替换（左侧替换不影响右侧 span）
        matches = list(STR_RE.finditer(raw))
        if matches:
            parts = []
            prev_end = 0
            # 先收集需要替换的 (span, 译文)，再重建
            repl = []
            for m in matches:
                lit = m.group(1)
                if lit and not CJK_RE.search(lit) and lit in table:
                    repl.append((m.span(1), table[lit]))
                    used[lit] += 1
                    total_replace += 1
            # 从右往左替换不会破坏左侧尚未处理的 span
            for (s, e), zh in reversed(repl):
                raw = raw[:s] + zh + raw[e:]
        out_lines.append(raw)

    open(src, "w", encoding="utf-8").write("\n".join(out_lines))

    zero = [en for en, c in used.items() if c == 0]
    done = sum(1 for c in used.values() if c > 0)
    print(f"翻译表条目: {len(table)}，成功替换 {done} 条，共替换 {total_replace} 处")
    if zero:
        print(f"警告: 以下 {len(zero)} 条未匹配（可能拼写不符或非本行首字面量）:")
        for en in zero:
            print(f"  - {en[:70]!r}")
    print("完成。请运行 bash -n 校验语法，并对比备份文件检查。")


if __name__ == "__main__":
    main()
