# Windows 一键开机工具 · 构建与使用说明

## 给客户发什么（按订单）

1. `boot_tool.exe`（工具本体，所有客户通用）
2. 该设备的「引导启动包」——两种形态任选：
   - `boot/` 文件夹（含 `boot/<机型>/<版本>/iBSS.boot` + `boot/0x<ECID>.txt`）
   - 或整个 `.zip`（工具自动解包，微信可直接发）

   生成方法：从本机 `boot/` 仓库里复制该设备对应的机型目录 + ECID 记录文件，打包即可
   （参考成品：`surrealra1n-boot-XR-iPhone11-14.0-14.3.zip`）

## Windows 构建步骤（在 Windows 机器上执行一次）

```bat
pip install pyusb pyinstaller
pyinstaller -F -n boot_tool boot_tool.py
:: 把 libusb-1.0.dll 放到 dist 目录（与 exe 同级）
:: 下载地址: https://github.com/libusb/libusb/releases （LibUSB-Win32/MS64/dll/libusb-1.0.dll）
```

> macOS 上开发调试直接 `python3 boot_tool.py --selftest`

## 客户端驱动（关键 UX）

DFU 模式的手机在 Windows 上默认没有可用驱动，需要绑定 WinUSB：

1. 首次引导时工具会提示，客户按指引让手机进 DFU
2. 打开 Zadig（建议随工具附带）→ Options 勾选 List All Devices
3. 下拉选择 **Apple Mobile (DFU Mode)** → 驱动选 **WinUSB** → Install
4. 之后永久生效，不再需要

改进方向（v1.1）：Zadig 有命令行模式（`zadig.exe /handler`相关参数），可做到工具内一键静默装驱动；或改用 libusb 过滤驱动安装包（全局生效但免选择）。

## 客户使用流程（写在包内使用说明里的逻辑）

1. 双击 `boot_tool.exe`
2. 按提示让手机进 DFU（工具内置分步指引）
3. 按提示把手机连到 Pi Pico 完成破解，再插回电脑
4. 工具自动发送引导文件 → 手动开机完成

## 诊断

客户报障时让他在工具所在目录跑：`boot_tool.exe --selftest`，把输出发回来即可定位
（能看到：USB 库状态 / 引导包 ECID 与版本 / 引导文件清单 / DFU 设备与序列号）
