@echo off
rem 一键构建原生 exe（Nuitka：Python -> C -> 机器码，防解包看源码）
rem 前置：pip install nuitka zstandard cryptography + 本机有 MSVC(cl) 或让它自动下 MinGW
cd /d "%~dp0"
python -m nuitka --onefile --windows-console-mode=disable --windows-icon-from-ico=brand.ico --enable-plugin=tk-inter --output-dir=build_nuitka --output-filename=boot_tool.exe --assume-yes-for-downloads boot_tool_gui.py
echo.
echo 产物：build_nuitka\boot_tool.exe（发布时与 libusb-1.0.dll / brand.png 放一起）
pause
