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
echo （若之后手机重新进过 DFU 又提示驱动问题，重新运行本脚本即可）
goto :end

:force_fail
echo.
echo [未完成] 强制绑定未成功（日志：%DRVLOG%）
pnputil /enum-devices /connected 2>nul | find /i "PID_1227" >nul
if errorlevel 1 (
    echo   原因：当前没有处于 DFU 模式的手机。
    echo   绑定只在手机进入 DFU 时生效——证书和驱动包已装好，
    echo   手机下次进入 DFU 后重新运行本脚本即可完成绑定。
) else (
    echo   手机已在 DFU 但绑定失败，请用 zadig.exe 手动装一次：
    echo   Options 勾 List All Devices - 选 Apple Mobile (DFU Mode)
    echo   - 驱动选 WinUSB - 点 Replace Driver
)

:zadig_gui
echo.

:end
echo.
pause
