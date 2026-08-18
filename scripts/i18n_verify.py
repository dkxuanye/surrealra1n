#!/usr/bin/env python3
"""验证中文化结果。

用法: python3 scripts/i18n_verify.py [目标文件] [备份文件]
默认: surrealra1n.sh  surrealra1n.sh.bak_before_i18n

检查项:
1. 翻译表变量保真: 每条译文的 $变量 集合与英文原文完全一致
   （唯一允许的例外: $CURRENT_VERSION -> $VERSION_DISPLAY，规格第 8 条）
2. 改动行审计: 被修改的行必须包含 echo/printf/read/pick_file/zenity/INFO_TEXT
   等输出语句关键字（防止误改逻辑代码），且引号数为偶数
3. 英文残留扫描（信息性输出，不判失败）: 列出行首为输出命令、引号内仍含
   4 个以上连续英文字母的行，供人工按 4 类判定
"""
import re
import sys

SRC = "surrealra1n.sh"
BACKUP = "surrealra1n.sh.bak_before_i18n"
TABLE = "scripts/i18n_translations.txt"

VAR_RE = re.compile(r"\$\([^)]*\)|\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")
OUTPUT_TOKENS = re.compile(
    r"\b(?:echo|printf|read|pick_file|zenity|title|INFO_TEXT|CURRENT_VERSION|VERSION_DISPLAY)\b"
)
RESIDUE_RE = re.compile(
    r'^(\s*(?:echo(?: -[a-z]+)?|printf(?: -v\s+\w+)?|read(?: -[a-z](?: \S+)?)*\s+-p|pick_file|--title=)\s*)("[^"]*[A-Za-z]{4,}[^"]*")'
)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    backup = sys.argv[2] if len(sys.argv) > 2 else BACKUP
    problems = []

    for line in open(TABLE, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        en, sep, zh = line.partition("|||")
        zh = zh.strip()
        if not sep or not en or not zh:
            problems.append(f"翻译表格式错误: {line!r}")
            continue
        ev = set(VAR_RE.findall(en))
        zv = {("$CURRENT_VERSION" if v == "$VERSION_DISPLAY" else v) for v in VAR_RE.findall(zh)}
        if ev != zv:
            problems.append(
                f"变量不一致: {en[:60]!r}\n"
                f"  英文变量: {sorted(ev)}\n"
                f"  译文变量: {sorted(zv)}"
            )

    old = open(backup, encoding="utf-8").read().split("\n")
    new = open(src, encoding="utf-8").read().split("\n")
    if len(old) != len(new):
        problems.append(f"行数变化: {len(old)} -> {len(new)}")
    changed = 0
    for i, (o, n) in enumerate(zip(old, new), 1):
        if o == n:
            continue
        changed += 1
        if not OUTPUT_TOKENS.search(n):
            problems.append(f"第 {i} 行被修改但无输出语句关键字: {n[:80]!r}")
        if n.count('"') % 2 != 0:
            problems.append(f"第 {i} 行引号数为奇数: {n[:80]!r}")

    print(f"改动行数: {changed}")
    print("=== 残留英文扫描（以下行需人工复核）===")
    for i, n in enumerate(new, 1):
        if RESIDUE_RE.search(n):
            print(f"{i}: {n.strip()[:110]}")

    if problems:
        print("\n=== 问题 ===")
        for p in problems:
            print(p)
        sys.exit(1)
    print("\n全部检查通过")


if __name__ == "__main__":
    main()
