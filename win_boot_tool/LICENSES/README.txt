本目录为「玄烨品果·一键开机」随包第三方组件的许可与来源说明。

1. Zadig (zadig.exe, v2.9, 官方发行版原样分发)
   许可：GPL-3.0（全文见 gpl-3.0.txt）
   来源/源码：https://github.com/pbatard/libwdi  tag v1.5.1
   （对应源码包与构建说明可向客服索取，或自行从上述仓库获取）

2. libusb-1.0.dll (v1.0.27, x64, 原样动态链接分发，未修改)
   许可：LGPL-2.1（全文见 lgpl-2.1.txt）
   来源/源码：https://github.com/libusb/libusb  tag v1.0.27

3. WebView2 运行时
   使用 Windows 系统自带运行时（微软许可），本包未捆绑其任何文件。

4. 本工具自身（boot_tool.exe 等）
   专有软件，限制见 NOTICE.txt。

历史说明：早期版本曾随包分发 wdi-simple.exe（libwdi LGPL-3.0，
源码 https://github.com/pbatard/libwdi，本项目 CI 可复现构建），
v1.2.2 起已从发行包移除；lgpl-3.0.txt 保留供历史版本用户查阅。
