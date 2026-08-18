# surrealra1n 中文化设计

日期：2026-08-18
状态：已批准

## 背景与目标

surrealra1n 是一个基于 bash 的 iOS 降级/恢复 TUI 工具。当前所有用户界面文字均为英文硬编码。目标：将所有用户可见文字改为中文显示（硬编码替换），不引入运行时语言切换。

## 范围

### 要翻译的（用户可见文本）

- 主脚本 `surrealra1n.sh` 中所有 `echo` / `printf` 输出的界面文字（菜单、提示、警告、错误、进度）
- `read -p` 的提示文字
- zenity 弹窗标题（`pick_file` 的 `--title`）
- INFO_TEXT 信息头（多行，含致谢、设备信息）
- 版本号文字（如 "v2.0 beta 27 re-release 4" → "v2.0 测试版 27 重新发布 4"）

统计基线：508 处 `echo`，去重后约 311 条不同字符串；另有 printf、read -p、zenity 标题若干。

### 不翻译的

- 代码逻辑（`$DISTRO` 变量值、`$MODE`、包名、路径、命令输出）
- 外部工具输出（futurerestore、irecovery、git 等）
- `error_handler` 中 GitHub 报错引导段落（保留英文，GitHub issue 建议英文书写）
- 代码注释、变量名、函数名
- 数字倒计时（"3"、"2"、"1"）、选项字符本身（y/N 保持，其提示文字翻译）
- `activate.sh`、`backup.sh` 及其他脚本（本次只做主脚本）

## 翻译规范

- 含 `$VARIABLE` 的句子：译文保留变量，中文语序合理。示例："futurerestore failed with exit code $EXIT_CODE" → "futurerestore 失败，退出码 $EXIT_CODE"
- 术语统一：
  - restore → 恢复
  - boot → 启动
  - blob / SHSH blob → SHSH 文件
  - SEP、DFU、iBSS、iBEC、APFS、IPSW、ECID 等专有名词保持英文
  - git、GitHub、zenity 等工具名保持英文
- 菜单项保持编号格式："1. Downgrade Options" → "1. 降级选项"
- 重复文本只翻译一次，全脚本一致

## 实现方式：翻译对照表 + 批量替换

用户已确认采用"直接硬编码替换"，执行上采用对照表驱动的批量替换，而非逐处手工编辑。

### 提取

Python 脚本从 `surrealra1n.sh` 提取用户可见字符串（去重）：

- `echo "..."` 内的文字（跳过仅含 ANSI 色码/纯命令回显的，人工复核）
- `printf "..."` 中的文字部分
- `read -p "..."` 提示
- zenity `--title` 参数

产出：翻译对照表 `原文 ||| 译文`，预计 330-350 条。

### 替换

Python 脚本执行替换，规则：

1. 按字符串长度从长到短排序替换（长文本优先，避免短串误伤长串中的子串）
2. 只替换引号内的精确匹配文本，不触碰引号外的代码
3. 替换后逐处校验：引号配对、`$变量` 保留

### 特殊场景

1. **多行 INFO_TEXT**：整块作为一条翻译（含换行），保持 `$CURRENT_VERSION`、`$NAME`、`$ECID`、`$MODE` 变量位置。
2. **DISTRO 显示映射**：变量值（macOS/Debian/Arch/Fedora/Unsupported）不改（参与逻辑判断），仅第 197 行 `Detected distro family: $DISTRO` 输出改为 case 映射的中文显示（如 "检测到系统发行版：macOS"）。Unsupported 分支的 `exit 1` 逻辑不受影响。
3. **变量字符串**：译文保留 `$变量`，保持双引号包裹，确保 `set -euo pipefail` 下正常展开。
4. **printf 格式串**：含 `%s`/`%d` 的 printf，译文保留格式符位置，按格式串整体替换。
5. **颜色输出函数**：`ok()`/`info()`/`error()` 等包装函数本身不翻译（只透传 `$1`），只翻译调用处参数。
6. **备份**：替换前生成 `surrealra1n.sh.bak_before_i18n` 备份，可回退。
7. **error_handler**：除 GitHub 引导段落外全部翻译（"已崩溃"、"退出码"、"行号"、"失败的命令"等）。

## 验证

1. **语法检查**：`bash -n surrealra1n.sh` 通过。
2. **变量保真检查**：对比脚本替换前后，每个被翻译字符串中的 `$VARIABLE` 集合完全一致。
3. **残留英文扫描**：grep 扫描引号内常见英文单词，人工复核剩余项（应为 GitHub 引导段落）。
4. **引号配对检查**：替换后每行引号数为偶数。
5. **抽查运行时输出**：条件允许时运行脚本查看主菜单/杂项菜单显示。

### 验收标准

- `bash -n` 通过
- 变量保真检查零差异
- 残留英文扫描仅剩 GitHub 引导段落
- 主菜单、misc 菜单、restore 菜单等关键界面全部中文

## 不做的（YAGNI）

- 不做中英文切换系统、翻译变量表、gettext 等 i18n 架构
- 不改动 activate.sh / backup.sh
- 不翻译外部工具输出
