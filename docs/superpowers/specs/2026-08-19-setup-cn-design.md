# setup_cn.sh 国内镜像依赖安装脚本设计

日期：2026-08-19
状态：已批准

## 背景与目标

surrealra1n 运行前需要安装 Homebrew 及若干依赖（libimobiledevice、libirecovery、libusb、binutils、jq、aria2），国内用户访问默认源（github.com / ghcr.io）速度慢，导致安装体验极差（binutils、aria2 甚至被迫源码编译数小时）。目标：提供一个 `setup_cn.sh`，自动配置清华/中科大镜像并一键安装全部依赖，让国内用户快速就绪。

## 文件

- Create: `surrealra1n/setup_cn.sh`（纯 bash，中文界面，与项目风格一致）

## 架构与组件

| 函数 | 职责 |
|---|---|
| `check_os()` | 非 macOS 直接退出（退出码 1） |
| `ensure_xcode_clt()` | 检测 Xcode CLT（`xcode-select -p`），缺失则提示执行 `xcode-select --install` 并等待 |
| `install_homebrew()` | 已装则跳过；未装用清华安装脚本安装（`NONINTERACTIVE=1`），装完立即把 brew 本体 remote 切到镜像 |
| `set_mirrors()` | 配置镜像环境变量（写入 `~/.zshrc`，幂等）；`--mirror ustc` 切换中科大 |
| `install_deps()` | 循环 `brew install` 依赖数组，已装（`brew list`）跳过 |
| `print_summary()` | 输出每个依赖结果（✅/❌）和下一步提示 |
| `main()` | 解析参数（`--mirror` / `--dry-run` / `--help`）→ 按序执行 |

依赖数组与 surrealra1n.sh 内置检查一致：`libimobiledevice libirecovery binutils libusb jq aria2`。

## 镜像配置

默认清华 TUNA，`--mirror ustc` 切换：

| 项目 | 清华 TUNA | 中科大 USTC |
|---|---|---|
| brew 本体 remote | `https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git` | `https://mirrors.ustc.edu.cn/brew.git` |
| homebrew-core remote | `https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git` | `https://mirrors.ustc.edu.cn/homebrew-core.git` |
| HOMEBREW_API_DOMAIN | `https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api` | `https://mirrors.ustc.edu.cn/homebrew-bottles/api` |
| HOMEBREW_BOTTLE_DOMAIN | `https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles` | `https://mirrors.ustc.edu.cn/homebrew-bottles` |

关键点：
1. Homebrew 安装完成后立即执行 `git remote set-url` + 写入环境变量，在下一次 brew 更新前源已就位
2. `HOMEBREW_API_DOMAIN` + `HOMEBREW_BOTTLE_DOMAIN` 必须配：默认走 ghcr.io 导致 API 慢和 bottle 不可达，brew 自动回退源码编译（用户实测的痛点根因）
3. `~/.zshrc` 写入幂等（grep 检测再追加）；同时写入 `HOMEBREW_NO_AUTO_UPDATE=1` 避免每次 `brew install` 前自动 update 卡住
4. 若 `HOMEBREW_BOTTLE_DOMAIN` 已被用户手动设置，跳过覆盖（尊重已有配置）
5. `--dry-run` 只打印将要执行的命令

## 安装流程

```
./setup_cn.sh [--mirror ustc] [--dry-run]

[1/5] 系统检测        → macOS ✓ / 非 macOS ✗ 退出
[2/5] Xcode CLT      → 缺失时提示执行 xcode-select --install，检测到后继续
[3/5] Homebrew       → 未装：清华安装脚本 + 立即换源；已装：直接换源
[4/5] 镜像配置       → 写入 ~/.zshrc（幂等），新值立即 export 到当前会话
[5/5] 安装依赖       → 逐个安装，已装跳过，显示 ✅/❌ 与耗时
摘要 → 提示运行 ./surrealra1n.sh
```

## 错误处理与退出码

- 非 macOS → 退出码 1，提示仅支持 macOS
- Homebrew 安装失败 → 退出码 1，提示手动安装（附官方链接）
- 单个 `brew install` 失败 → 记录 ❌ 继续装其余依赖，摘要标红提示重试命令
- Ctrl+C 干净退出（130）

退出码：0=全部就绪，1=有失败项/环境不满足，130=中断

## 测试

1. `bash -n setup_cn.sh` 语法检查
2. mock 离线测试（`tests/setup_cn_tests.sh`，沿用 dfu_guide 模式）：PATH 前置假 `brew`/`xcode-select`/`git`，模拟"已装/未装/装失败"场景，断言输出与退出码
3. 实机验证由用户操作

## 不做的（YAGNI）

- 不改 surrealra1n.sh 本身
- 不做 Linux 支持
- 不做 pip 换源
- 不自动覆盖用户已有的镜像配置
