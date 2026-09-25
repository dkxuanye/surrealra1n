# surrealra1n 

A tethered downgrade tool for some A7/A8(X) devices, all A11 devices and A12/A13 iPhones.

Supports macOS (10.15+) and Linux

For surrealra1n support, join the [surrealra1n](https://discord.gg/kDXVHhTQs2) Discord Server

# Compatible devices and versions:

View the [Supported Devices](https://github.com/pwnerblu/surrealra1n/wiki/Supported-Devices) section in the wiki for more information

# Usage:

Download surrealra1n [here](https://github.com/pwnerblu/surrealra1n/releases/latest) or clone it using git:
```
git clone -b main https://github.com/pwnerblu/surrealra1n
```
Extract the zip file and open a terminal window to the folder that contains surrealra1n, then launch it using the command: ```./surrealra1n.sh```.

## 国内用户（China users）

国内网络访问 Homebrew / GitHub 较慢，运行前先执行一键配置脚本（新增，非上游）：

```
./setup_cn.sh
```

该脚本会配置 Homebrew / pip 镜像、`GITHUB_PROXY` 代理前缀，以及 git 的
`url.<proxy>/https://github.com/.insteadOf` 规则，使二进制下载、git clone 都走代理。

常用参数：

```
./setup_cn.sh                          # 默认清华镜像 + ghfast.top 代理
./setup_cn.sh --mirror ustc            # 切换中科大镜像
./setup_cn.sh --proxy https://gh-proxy.com/   # 换代理前缀
./setup_cn.sh --no-proxy               # 跳过 GitHub 加速（自备代理）
```

不运行 `setup_cn.sh` 也可手动用代理启动：

```
GITHUB_PROXY=https://ghfast.top/ ./surrealra1n.sh
```

## 更新检查（新增，非上游）

脚本默认跳过启动更新检查（离线优先：不联网、不提示、绝不强制更新）。如需在
启动时联网检查更新：

```
SKIP_UPDATE_CHECK=0 ./surrealra1n.sh
```

联网检查失败（离线/网络问题）时会自动回退到本地缓存的更新信息并跳过，
不会中断流程或强求你更新。



# Thanks to:

libimobiledevice team, tihmstar, LukeeGD/LukeZGD, xerub, plooshi, etc! (for the tools it has to download)

Mineek - iPhone X restored patcher, used for ipx restores 14.3-15.6.1 (my fork of the patcher is used for seprmvr64 restores on A8+), openra1n, and seprmvr64

Nathan (verygenericname) - SSHRD_Script

[kok3shidoll](https://github.com/kok3shidoll) - [daibutsu](https://github.com/kok3shidoll/daibutsu)

[Clarity](https://github.com/TheRealClarity) - [fork of daibutsu](https://github.com/TheRealClarity/daibutsu), [wtfis](https://github.com/TheRealClarity/wtfis) which is used as part of jailbreaking iOS 8 downgrades











