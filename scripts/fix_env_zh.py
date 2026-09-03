#!/usr/bin/env python3
"""修复翻译表中 $VAR 紧跟全角字符（非 ASCII）的 bash 3.2 解析隐患。

做法: 找到译文里 $name 或 ${name} 后紧跟非 ASCII 字符的位置，
对 $name 形式补齐 { }，得到 ${name}，避免 bash 误把全角字符并入变量名。
仅影响 zh 侧（zh 含中文，才是触发源）。也顺带修复 zh 中 $name 后为全角的情况。
"""
import re

TABLE = "scripts/i18n_translations.txt"
# $name 且其后紧跟非 ASCII 字符
AMBY_RE = re.compile(r"(?<!\$)(\$[A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])")


def fix_zh(zh: str) -> tuple[str, int]:
    def repl(m):
        return "${" + m.group(1)[1:] + "}"
    new, n = AMBY_RE.subn(repl, zh)
    return new, n


def main() -> None:
    out = []
    total = 0
    changed = 0
    for line in open(TABLE, encoding="utf-8"):
        line = line.rstrip("\n")
        en, sep, zh = line.partition("|||")
        if not sep:
            out.append(line)
            continue
        new_zh, n = fix_zh(zh)
        if n:
            total += n
            changed += 1
        out.append(f"{en}|||{new_zh}")
    with open(TABLE, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"修复 {changed} 条，共 {total} 处变量加花括号")


if __name__ == "__main__":
    main()
