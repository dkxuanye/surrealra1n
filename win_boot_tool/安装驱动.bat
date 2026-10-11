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
set "CERTID=832E96B6DA1FF0DCF635376400BE43CAE8E0819E"

echo ==============================================
echo   一次性驱动安装（装完以后不再需要）
echo ==============================================
echo.
echo 建议让手机先进 DFU 再运行本脚本（立即生效）。
echo 手机不连接也可以装（下次进 DFU 时自动生效）。
echo 撤销方法见同文件夹《驱动回滚说明.txt》。
echo.

if not exist "%~dp0driver_pkg\dfu_driver.cer" goto :zadig_gui

echo [1/3] 导入驱动信任证书（发布者+根）...
certutil -addstore -f TrustedPublisher "%~dp0driver_pkg\dfu_driver.cer" >nul 2>&1
if errorlevel 1 goto :zadig_gui
certutil -addstore -f Root "%~dp0driver_pkg\dfu_driver.cer" >nul 2>&1
if errorlevel 1 goto :revoke_zadig
echo       完成

echo [2/3] 注册驱动包（WinUSB）...
pnputil /add-driver "%~dp0driver_pkg\apple_mobile_device_(dfu_mode).inf" /install >nul 2>&1
set PNP=%errorlevel%
echo pnputil exit=%PNP% >> "%DRVLOG%"
if "%PNP%"=="0" goto :pnputil_ok
if "%PNP%"=="3010" goto :pnputil_ok
echo       [失败] pnputil 退出码 %PNP%（详见 %DRVLOG%）
goto :revoke_zadig
:pnputil_ok
echo       完成（已注册）

echo [3/3] 强制绑定到 DFU 设备（替换 Apple 驱动）...
if not exist "%~dp0driver_install.ps1" goto :revoke_zadig
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
    goto :end
)
echo   绑定失败，撤销已导入的证书并转 Zadig 手动安装...
goto :revoke_zadig

:revoke_zadig
rem 本链失败：撤销刚导入的两处证书信任，避免留下无用根信任
certutil -delstore TrustedPublisher %CERTID% >nul 2>&1
certutil -delstore Root %CERTID% >nul 2>&1

:zadig_gui
echo.
echo 改用 Zadig 手动安装（本文件夹内已附 zadig.exe）：
echo   1. 双击 zadig.exe
echo   2. 菜单 Options 勾选 List All Devices
echo   3. 下拉选择 Apple Mobile (DFU Mode)
echo   4. 右侧驱动选择框选 WinUSB
echo   5. 点击 Replace Driver，等待完成
echo   完成后回到本工具即可。
if exist zadig.exe (start "" zadig.exe) else (echo 未找到 zadig.exe，请联系客服)

:end
echo.
pause
