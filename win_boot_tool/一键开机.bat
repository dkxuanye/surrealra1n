@echo off
chcp 65001 >nul
title 一键开机
cd /d "%~dp0"

if exist boot_tool.exe (
    boot_tool.exe
) else if exist boot_tool.py (
    where python >nul 2>&1
    if %errorlevel% neq 0 (
        echo 未找到 boot_tool.exe，且本机没有安装 Python。
        echo 请联系客服重新获取完整工具包。
        pause
        exit /b 1
    )
    python boot_tool.py
) else (
    echo 工具文件缺失：boot_tool.exe 不在本文件夹内。
    echo 请联系客服重新获取。
    pause
    exit /b 1
)
