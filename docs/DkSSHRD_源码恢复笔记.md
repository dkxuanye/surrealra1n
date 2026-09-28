# DkSSHRD / DownRa1n 源码恢复笔记（2026-09-28）

## 样本：Downloads/DownRa1n_Beta2.zip（5.4M）

- **.NET 程序**（C#，WPF/WinForms GUI）：`DownRa1n.exe`（壳）+ `DownRa1n.dll`（主程序集 2.8M）
- **带 `DownRa1n.pdb` 调试符号** —— 反编译质量会非常好（带行号/局部名）
- 工具链：`ref/irecovery.exe` + libirecovery/libusbmuxd/libusb dlls（发送引导文件用）、
  Renci.SshNet（SSH 上传/执行，对应 Mac 端 activate.sh 激活流程：
  ref/ 里有 activation_record.plist / data_ark / FairPlay IC-Info.sisv / trollstorehelper）
- `boot/`、`ramdisk/`、`shsh/` 为用户放入区（shsh 里带了一个 shsh.shsh2）
- **无独立 gaster.exe** —— checkm8 pwn 要么内置于 C# 代码，要么流程另有来源（反编译重点确认）

## 已提取的类/方法地图（dnfile 元数据分析）

```
DownRa1n.App                      程序入口
DownRa1n.MainWindow               主窗口，按钮事件：
  <Boot_Click>d__8                ★ 开机（核心：downr1n 引导文件发送流程）
  <Ramdisk_Click>d__9             Ramdisk 启动
  <ExecuteCommands>d__10/2 d__11  执行外部命令（irecovery 调用大概率在这）
  <SendCommand>d__12              发送命令
  <StartIproxy>d__13/2 d__14      启动 iproxy（2222 端口转发，SSH 用）
  <SpcUploadFileAsync>d__5        SSH 上传文件
  <SpcDownloadFileAsync>d__6      SSH 下载文件
  <DownloadFiles>d__17            下载文件
  <UploadsFiles>d__18/2 d__19     上传文件
  <ExecuteStepWithProgress>d__20  带进度条的步骤执行
  <Mount_Click>d__21              挂载（mount_filesystems 类操作）
  <Activated_Click>d__23          ★ 激活（activate.sh 的 Windows 化）
  <Backup_Click>d__24             备份（backup.sh 的 Windows 化）
  <Troll_Click>d__22              TrollStore 安装
FileUploader / ProcessExtensions  辅助类
共 76 个方法
```

## Windows 端恢复源码（两条路任选）

```powershell
# 路 A：ilspycmd（命令行，最快）
dotnet tool install -g ilspycmd
ilspycmd DownRa1n.dll -p -o D:\DkSSHRD_recovered     # -p 连项目文件一起生成

# 路 B：dnSpy / ILSpy GUI
#   github.com/dnSpy/dnSpy releases → 打开 DownRa1n.dll（同目录放 .pdb）
#   → File → Export to Project
```

## 恢复后的对接点（与 boot_tool 生态合并）

1. `Boot_Click` 的引导文件发送序列 = A9 在 Windows 的开机流程（对照 downr1n 的
   iBSS/iBEC/DeviceTree/kernel/trustcache 五件套）
2. checkm8 pwn 的实现位置（内置 C# 还是外部调用）—— 决定 boot_tool 是否直接移植
3. 激活流程（Activated_Click + SshNet）可补进 win_boot_tool 的售后服务链
4. 建议恢复后把源码推到 github.com/dkxuanye/DkSSHRD（当前该仓库查不到内容）
