#!/usr/bin/env python3
"""提取 surrealra1n.sh 中的用户可见字符串（去重），生成清单文件。

输出格式: 每行 "字符串<TAB>行号1,行号2,..."，按字符串长度从长到短排序。
仅匹配 echo / printf / read -p / zenity --title 后的双引号内容。
"""
import re
from collections import OrderedDict

SRC = "surrealra1n.sh"
OUT = "scripts/i18n_strings.txt"

LINE_RE = re.compile(
    r'^(?:echo(?: -[a-z]+)?\s+|printf(?: -v\s+\w+)?\s+|read(?: -[a-z]+)*\s+-p\s+|--title=)(".*")'
)


def unquote(s: str) -> str:
    s = s[1:-1]
    return (s.replace('\\"', '"').replace('\\n', '\n')
             .replace('\\e', '\x1b').replace('\\t', '\t'))


def main() -> None:
    lines = open(SRC, encoding="utf-8").read().split("\n")
    entries: OrderedDict[str, list[int]] = OrderedDict()
    for i, raw in enumerate(lines, 1):
        m = LINE_RE.match(raw.strip())
        if not m:
            continue
        val = unquote(m.group(1))
        entries.setdefault(val, []).append(i)
    with open(OUT, "w", encoding="utf-8") as f:
        for val, lns in sorted(entries.items(), key=lambda kv: len(kv[0]), reverse=True):
            f.write(f"{val}\t{','.join(map(str, lns))}\n")
    total = sum(len(v) for v in entries.values())
    print(f"总出现次数: {total}")
    print(f"去重字符串数: {len(entries)}")
    print(f"清单已写入: {OUT}")


if __name__ == "__main__":
    main()
