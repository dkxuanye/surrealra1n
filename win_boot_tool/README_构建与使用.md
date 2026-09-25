# Windows 一键开机工具 · 构建与使用说明

## 文件总览

| 文件 | 用途 |
|---|---|
| `boot_tool.py` | 工具本体（跨平台 Python 引擎） |
| `make_order_package.py` | 接单后生成客户引导包（Mac 端使用） |
| `make_win_release.sh` | 组装 Windows 客户发货包（含 exe/bat/说明/订单包） |
| `安装驱动.bat` | 客户端一次性驱动安装（自动提权；优先 wdi-simple 静默，降级 Zadig GUI） |
| `一键开机.bat` | 客户端双击入口 |

## 发货全流程（接一单的完整动作）

```bash
# ① Mac 端：生成该客户的引导包
python3 make_order_package.py --ecid 0x<客户设备ECID> --id iPhone11,8 --ver 14.3 --name 张三

# ② Windows 端（一次性，工具版本不变则复用）：
#    pyinstaller -F -n boot_tool boot_tool.py
#    把 dist/boot_tool.exe + libusb-1.0.dll 放回本目录 dist/

# ③ Mac 端：组装发货包（客户微信/QQ 直发）
./make_win_release.sh boot_张三_iPhone11,8_14.3.zip 张三
```

## 驱动方案（v1.1）

首选 **wdi-simple.exe 静默安装**（libwdi 官方命令行示例，Zadig 的 CLI 版）：
`wdi-simple --vid 0x05AC --pid 0x1227 --type 2`（type 2 = WinUSB）
获取：Windows 上从 libwdi releases 下载或自行编译，放入 `vendor/wdi-simple.exe`，
`安装驱动.bat` 会自动检测并用它静默安装（自动提权）。
缺失时自动降级为引导客户用 Zadig GUI（步骤已打印在窗口里）。

> macOS 上开发调试直接 `python3 boot_tool.py --selftest`

## 客户使用流程（写在包内使用说明里的逻辑）

1. 首次：解压 → 双击「安装驱动.bat」→ 把订单引导包 zip 放进文件夹
2. 每次开机：双击「一键开机.bat」→ 按提示 DFU → Pico 破解 → 自动发送引导

## 诊断

客户报障时让他在工具目录执行：`boot_tool.exe --selftest`，把输出发回来即可定位
（能看到：USB 库状态 / 引导包 ECID 与版本 / 引导文件清单 / DFU 设备与序列号）
