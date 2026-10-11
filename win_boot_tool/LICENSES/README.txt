本目录为「玄烨品果·一键开机」随包第三方组件的许可与来源说明。
完整许可文本请访问对应项目仓库获取。

1. Zadig (zadig.exe, v2.9)
   许可：GPL-3.0
   来源：https://github.com/pbatard/libwdi （Releases）
   说明：本包原样分发官方发行版二进制。源码获取方式即上述仓库；
   如需本包所用确切版本的源码压缩包，请联系客服索取。

2. wdi-simple.exe（libwdi 示例程序，本项目 CI 构建）
   许可：LGPL-3.0（libwdi 项目）
   来源：https://github.com/pbatard/libwdi （examples/wdi-simple.c）
   构建：本项目 .github/workflows/build-wdi-simple.yml（可复现构建）
   说明：动态链接 LGPL 库的独立可执行文件分发；libwdi 源码见上述仓库。

3. libusb-1.0.dll (v1.0.27, x64)
   许可：LGPL-2.1（部分 BSD）
   来源：https://github.com/libusb/libusb （Releases，MS64/dll）
   说明：以动态链接方式随包分发，未修改。

4. WebView2 运行时
   说明：使用 Windows 系统自带的 WebView2 运行时（微软许可），本包未捆绑。

5. 本工具自身（boot_tool.exe 等）
   许可：未对外授权——仅限玄烨品果正式客户按订单使用，禁止再分发。
