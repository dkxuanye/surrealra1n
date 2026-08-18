#!/usr/bin/env python3
"""按翻译表将目标脚本中的英文替换为中文。

用法: python3 scripts/i18n_apply.py [目标文件] [备份文件]
默认: surrealra1n.sh  surrealra1n.sh.bak_before_i18n

替换规则:
1. 先备份原文件
2. 按字符串长度从长到短排序替换（长文本优先，避免短串误伤长串中的子串）
3. 逐条统计替换次数，0 次替换的条目输出警告（提示表与原文不符）
"""
import re
import shutil
import sys

SRC = "surrealra1n.sh"
BACKUP = "surrealra1n.sh.bak_before_i18n"
TABLE = "scripts/i18n_translations.txt"


def load_table() -> list[tuple[str, str]]:
    entries = []
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
        entries.append((en, zh))
    return sorted(entries, key=lambda e: len(e[0]), reverse=True)


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    backup = sys.argv[2] if len(sys.argv) > 2 else BACKUP
    shutil.copyfile(src, backup)
    print(f"已备份原文件 -> {backup}")
    text = open(src, encoding="utf-8").read()
    if re.search(r"[\u4e00-\u9fff]", text):
        raise SystemExit(
            f"目标文件已包含中文，可能已翻译过。\n"
            f"请先从备份恢复英文原版后再运行（备份: {backup}）"
        )
    stats = []
    for en, zh in load_table():
        n = text.count(en)
        if n == 0:
            print(f"警告: 未找到原文（可能拼写不符或已替换）: {en[:60]!r}")
        text = text.replace(en, zh)
        stats.append((en, zh, n))
    open(src, "w", encoding="utf-8").write(text)
    done = sum(1 for _, _, n in stats if n > 0)
    total = sum(n for _, _, n in stats)
    print(f"翻译表条目: {len(stats)}，成功替换 {done} 条，共替换 {total} 处")
    if done < len(stats):
        print("存在未匹配的条目，请检查警告信息后重试（文件已回写，注意从备份恢复）")
        sys.exit(1)


if __name__ == "__main__":
    main()
