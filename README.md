# surrealra1n 

A tethered downgrade tool for some A7/A8(X) devices, all A11 devices and A12/A13 iPhones.

Supports macOS and Linux

For surrealra1n support, join the [surrealra1n](https://discord.gg/kDXVHhTQs2) Discord Server

# Compatible devices and versions:

View the [Supported Devices](https://github.com/pwnerblu/surrealra1n/wiki/Supported-Devices) section in the wiki for more information

# Usage:

Download surrealra1n [here](https://github.com/pwnerblu/surrealra1n/releases/latest) or clone it using git:
```
git clone -b development https://github.com/pwnerblu/surrealra1n
```
Extract the zip file and open a terminal window to the folder that contains surrealra1n, then launch it using the command: ```./surrealra1n.sh```.



# 国内用户加速（China users）

国内网络访问 Homebrew / GitHub 较慢，运行前先执行一键配置脚本：

```
./setup_cn.sh
```

该脚本会自动完成：

| 步骤 | 说明 |
|---|---|
| 系统检测 / Xcode CLT | 检查 macOS 与命令行工具 |
| Homebrew 安装 | 使用 HomebrewCN 一键安装脚本（Gitee，交互选择镜像源） |
| Homebrew 镜像配置 | HOMEBREW_API_DOMAIN / BOTTLE_DOMAIN / NO_AUTO_UPDATE 写入 ~/.zshrc |
| GitHub 下载加速 | 106 处二进制下载走代理前缀（默认 ghfast.top）+ git insteadOf 全局配置 |
| pip3 清华源 | pyusb 等 Python 依赖安装加速 |
| 安装全部依赖 | libimobiledevice / libirecovery / libusb / binutils / jq / aria2 |

常用参数：

```
./setup_cn.sh                          # 默认清华镜像 + ghfast.top 代理
./setup_cn.sh --mirror ustc            # 切换中科大镜像
./setup_cn.sh --proxy https://gh-proxy.com/   # 切换 GitHub 代理前缀（默认服务失效时）
./setup_cn.sh --no-proxy               # 跳过 GitHub 加速（已自备代理工具）
./setup_cn.sh --dry-run                # 演练，不执行任何操作
```

注意：ghfast.top 为第三方加速服务，若失效请用 `--proxy` 切换其他前缀，或 `--no-proxy` 后自行开启 Clash 等代理工具。Apple 服务器（IPSW 下载 / SHSH / FDR）无法镜像，如遇速度问题请更换网络环境。



# Thanks to:

libimobiledevice team, tihmstar, LukeeGD/LukeZGD, xerub, plooshi, etc! (for the tools it has to download)

Mineek - iPhone X restored patcher, used for ipx restores 14.3-15.6.1 (my fork of the patcher is used for seprmvr64 restores on A8+), openra1n, and seprmvr64

Nathan (verygenericname) - SSHRD_Script












