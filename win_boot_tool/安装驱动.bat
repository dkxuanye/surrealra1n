@echo off
chcp 65001 >nul
title 一次性安装驱动（管理员）

rem ========== 自提权（驱动安装需要管理员）==========
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 需要管理员权限，正在请求...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ==============================================
echo   一次性驱动安装（装完以后不再需要）
echo ==============================================
echo.
echo 本步骤为手机 DFU 模式安装通用 USB 驱动。
echo 请先确保手机已用数据线连接电脑（不必进 DFU 也可以装）。
echo.

where wdi-simple.exe >nul 2>&1
if %errorlevel% equ 0 (
    echo 正在静默安装 WinUSB 驱动（Apple DFU 设备）...
    wdi-simple.exe --vid 0x05AC --pid 0x1227 --type 2
    if %errorlevel% equ 0 (
        echo.
        echo [成功] 驱动安装完成！以后直接双击「一键开机」即可。
    ) else (
        echo.
        echo [失败] 错误码 %errorlevel%，请截图联系客服。
    )
) else (
    echo 未找到 wdi-simple.exe，将打开 Zadig 图形工具，请按提示操作：
    echo   1. 菜单 Options 勾选 List All Devices
    echo   2. 下拉选择 Apple Mobile (DFU Mode)
    echo   3. 右侧驱动选择框选 WinUSB
    echo   4. 点击 Replace Driver / Install Driver，等待完成
    if exist zadig.exe (start "" zadig.exe) else (echo 请联系客服获取 zadig.exe)
)
echo.
pause
