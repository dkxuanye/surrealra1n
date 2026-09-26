@echo off
title 一次性安装驱动（管理员）
cd /d "%~dp0"

rem ========== 自提权（驱动安装需要管理员）==========
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限，正在请求...
    powershell -Command "Start-Process '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

set "DRVLOG=%TEMP%\drv_install_result.log"

echo ==============================================
echo   一次性驱动安装（装完以后不再需要）
echo ==============================================
echo.
echo 建议让手机先进 DFU 再运行本脚本（立即生效）。
echo 手机不连接也可以装（下次进 DFU 时自动生效）。
echo.

if not exist "%~dp0driver_pkg\dfu_driver.cer" goto :zadig_gui

echo [1/3] 导入驱动信任证书...
certutil -addstore -f TrustedPublisher "%~dp0driver_pkg\dfu_driver.cer" >nul 2>&1
if errorlevel 1 goto :zadig_gui
echo       完成

echo [2/3] 注册驱动包（WinUSB）...
pnputil /add-driver "%~dp0driver_pkg\apple_mobile_device_(dfu_mode).inf" /install >nul 2>&1
echo pnputil exit=%errorlevel% >> "%DRVLOG%"
echo       完成（已注册）

echo [3/3] 强制绑定到 DFU 设备（替换 Apple 驱动）...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0driver_install.ps1" -InfPath "%~dp0driver_pkg\apple_mobile_device_(dfu_mode).inf" -HardwareId "USB\VID_05AC&PID_1227" >> "%DRVLOG%" 2>&1
if errorlevel 1 goto :force_fail
echo       完成
pnputil /scan-devices >nul 2>&1
echo.
echo [成功] 驱动安装完成！以后直接双击「一键开机」即可。
goto :end

:force_fail
echo       强制绑定未成功，日志：%DRVLOG%
echo       将打开 Zadig 工具，请按提示操作。

:zadig_gui
echo.
echo Zadig 手动步骤：
echo   1. 菜单 Options 勾选 List All Devices
echo   2. 下拉选择 Apple Mobile (DFU Mode)
echo   3. 右侧驱动选择框选 WinUSB
echo   4. 点击 Replace Driver，等待完成
if exist zadig.exe (start "" zadig.exe) else (echo 请联系客服获取 zadig.exe)

:end
echo.
pause
