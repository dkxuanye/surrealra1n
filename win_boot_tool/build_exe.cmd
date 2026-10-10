@echo off
rem 一键构建原生 exe（Nuitka：Python -> C -> 机器码 + WebView2 液体玻璃界面）
rem 前置：pip install nuitka zstandard cryptography pywebview + 本机有 MSVC(cl)
rem 产物需与 ui\ 文件夹、libusb-1.0.dll、brand.png 同目录发布
cd /d "%~dp0"
python -m nuitka --onefile --windows-console-mode=disable --windows-icon-from-ico=brand.ico --output-dir=build_web --output-filename=boot_tool.exe --assume-yes-for-downloads boot_tool_web.py
echo.
echo 产物：build_web\boot_tool.exe（发布时与 ui\ / libusb-1.0.dll 同放）
pause
