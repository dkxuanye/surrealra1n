@echo off
title 一次性安装驱动（管理员）
cd /d "%~dp0"

rem ========== 自提权（驱动安装需要管理员）==========
rem 必须在提权前 cd 到脚本目录——提权重启后工作目录会变成 System32
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限，正在请求...
    powershell -Command "Start-Process '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

echo ==============================================
echo   一次性驱动安装（装完以后不再需要）
echo ==============================================
echo.
echo 本步骤为手机 DFU 模式安装通用 USB 驱动。
echo 手机可不连接（驱动预装，手机下次进 DFU 自动生效）。
echo.

rem ========== 方案一：随包驱动（证书 + WinUSB 驱动包，纯静默）==========
if exist "%~dp0driver_pkg\dfu_driver.cer" if exist "%~dp0driver_pkg\apple_mobile_device_(dfu_mode).inf" goto :pkg_install

rem ========== 方案二：wdi-simple（vendor\，静默）==========
set "WDI="
if exist "%~dp0wdi-simple.exe" set "WDI=%~dp0wdi-simple.exe"
if not defined WDI if exist "%~dp0vendor\wdi-simple.exe" set "WDI=%~dp0vendor\wdi-simple.exe"
if defined WDI goto :wdi_install

rem ========== 方案三：Zadig 图形界面（人工）==========
goto :zadig_gui

:pkg_install
echo [1/2] 导入驱动信任证书...
certutil -addstore -f TrustedPublisher "%~dp0driver_pkg\dfu_driver.cer" >nul 2>&1
if errorlevel 1 goto :pkg_fail
echo       完成
echo [2/2] 安装 DFU 驱动（WinUSB）...
pnputil /add-driver "%~dp0driver_pkg\apple_mobile_device_(dfu_mode).inf" /install >nul 2>&1
if errorlevel 1 goto :pkg_fail
echo.
echo [成功] 驱动安装完成！以后直接双击「一键开机」即可。
goto :end

:pkg_fail
echo.
echo [失败] 随包驱动安装出错，改用备用方案...
if defined WDI goto :wdi_install
goto :zadig_gui

:wdi_install
echo 正在静默安装驱动（wdi-simple）...
"%WDI%" --vid 0x05AC --pid 0x1227 --type 0
if errorlevel 1 goto :zadig_gui
echo.
echo [成功] 驱动安装完成！以后直接双击「一键开机」即可。
goto :end

:zadig_gui
echo 将打开 Zadig 工具，请按提示操作：
echo   1. 菜单 Options 勾选 List All Devices
echo   2. 下拉选择 Apple Mobile (DFU Mode)
echo   3. 右侧驱动选择框选 WinUSB
echo   4. 点击 Replace Driver，等待完成
if exist zadig.exe (start "" zadig.exe) else (echo 请联系客服获取 zadig.exe)

:end
echo.
pause
