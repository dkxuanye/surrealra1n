# surrealra1n 国内资源全覆盖设计

日期：2026-08-19
状态：已批准

## 背景与目标

setup_cn.sh 已覆盖 Homebrew 依赖镜像，但项目运行时仍有大量外网依赖未覆盖：106 处 GitHub 二进制下载（curl -L，来源 Semaphorin/Legacy-iOS-Kit/downr1n/spironolactone 等仓库）、update/latest.txt 拉取、git clone（更新/切分支流程）、pip3（usbliter8ctl 的 pyusb）。目标：通过可配置的 GitHub 代理前缀 + git insteadOf + pip3 清华源，实现国内资源全覆盖（Apple 服务器 IPSW/TSS/FDR 除外，无法镜像）。

## 改动范围

### 1. surrealra1n.sh：curl_l 函数 + 批量替换

顶部（版本变量之后）新增：

```bash
# GitHub 下载加速：GITHUB_PROXY 非空时自动为 github.com URL 加前缀
curl_l() {
    local url last
    for last in "$@"; do :; done
    if [[ -n "${GITHUB_PROXY:-}" && "$last" == https://github.com/* ]]; then
        set -- "${@:1:$#-1}" "${GITHUB_PROXY}${last}"
    fi
    curl -L "$@"
}
```

批量替换：106 处 `curl -L ` → `curl_l `（仅替换以 `curl -L ` 开头的调用；不动 `curl -s` 等其他调用）。`GITHUB_PROXY` 为空时行为逐字节不变。

### 2. i18n_verify.py 白名单

`OUTPUT_TOKENS` 正则加入 `curl_l`（否则改动行审计会把替换后的 106 行报为"被修改但无输出语句关键字"）。

### 3. setup_cn.sh 扩展（三个新函数）

| 函数 | 职责 | 幂等判断 |
|---|---|---|
| `set_github_proxy()` | 写入 `export GITHUB_PROXY=<前缀>` 到 ~/.zshrc + 当前会话 export | grep 检测 `GITHUB_PROXY=` 已存在则跳过 |
| `set_git_insteadof()` | `git config --global url."<前缀>/https://github.com/".insteadOf "https://github.com/"` | `git config --global --get-all` 含该值则跳过 |
| `set_pip_mirror()` | `pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple` | `pip3 config get global.index-url` 已指向清华则跳过 |

流程 5 步 → 7 步：系统检测 → Xcode CLT → Homebrew → 镜像配置 → GitHub 加速（新增）→ pip3 清华源（新增）→ 安装依赖。

参数扩展：`--proxy <前缀>`（默认 `https://ghfast.top/`）、`--no-proxy`（跳过 GitHub 加速，用户自备代理）、`--dry-run`（演练全部步骤）。

尊重已有配置：GITHUB_PROXY 已设置 → 跳过；git insteadOf 已配置 → 跳过；pip 已指向非清华源 → 跳过。

### 4. 测试

- `tests/curl_l_tests.sh`：source 出 curl_l 函数，断言前缀逻辑（空前缀不变 / 加前缀 / 非 github.com 不变）
- `tests/setup_cn_tests.sh` 新增场景：默认代理写入幂等、`--no-proxy` 不写、git insteadOf 幂等、pip3 幂等（新增 mock：git config、pip3 config）
- 回归：bash -n、i18n_verify 全过、原 18 项 + 新增全绿、零 bash 3.2 隐患

## 不做（YAGNI）

- Apple 服务器（IPSW 下载 / TSS / FDR）不做镜像——无法镜像，教程说明换网络
- 不做代理服务商自动检测/多服务商切换
- 不修改 update/latest.txt 之外的 GitHub raw 拉取逻辑（已被 curl_l 覆盖）
- 不做 Linux 支持
