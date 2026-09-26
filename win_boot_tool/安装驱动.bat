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

echo ==============================================
echo   一次性驱动安装（装完以后不再需要）
echo ==============================================
echo.
echo 建议让手机先进 DFU 再运行本脚本（立即生效）。
echo 手机不连接也可以装（下次进 DFU 时自动生效）。
echo.

rem ========== 方案一：wdi-simple 静默强制安装（可替换 Apple 驱动）==========
set "WDI="
if exist "%~dp0wdi-simple.exe" set "WDI=%~dp0wdi-simple.exe"
if not defined WDI if exist "%~dp0vendor\wdi-simple.exe" set "WDI=%~dp0vendor\wdi-simple.exe"
if defined WDI goto :wdi_install

rem ========== 方案二：随包证书+驱动包（pnputil）==========
if exist "%~dp0driver_pkg\dfu_driver.cer" goto :pkg_install

rem ========== 方案三：Zadig 图形界面 ==========
goto :zadig_gui

:wdi_install
echo [1/1] 正在静默安装 DFU 驱动（WinUSB，可自动替换 Apple 驱动）...
set "WDIDEST=%TEMP%\wdi_drv_%RANDOM%"
"%WDI%" --vid 0x05AC --pid 0x1227 --type 0 --name "Apple Mobile Device (DFU Mode)" --dest "%WDIDEST%" --silent
if errorlevel 1 goto :pkg_try
echo.
echo [成功] 驱动安装完成！以后直接双击「一键开机」即可。
goto :end

:pkg_try
echo wdi-simple 未成功，尝试备用方案...

:pkg_install
if not exist "%~dp0driver_pkg\dfu_driver.cer" goto :zadig_gui
echo [1/2] 导入驱动信任证书...
certutil -addstore -f TrustedPublisher "%~dp0driver_pkg\dfu_driver.cer" >nul 2>&1
if errorlevel 1 goto :zadig_gui
echo       完成
echo [2/2] 安装 DFU 驱动（WinUSB）...
pnputil /add-driver "%~dp0driver_pkgpple_mobile_device_(dfu_mode).inf" /install >nul 2>&1
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
