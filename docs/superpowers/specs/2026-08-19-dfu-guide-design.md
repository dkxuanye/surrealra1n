# surrealra1n DFU 引导脚本设计

日期：2026-08-19
状态：已批准

## 背景与目标

surrealra1n 的恢复/降级流程需要设备进入 DFU 模式，现有 `dfu_helper` 的提示较为简陋。受 spironolactone 项目中商业工具逆向报告的启发（rkeytools 的分步按键文案、ifine/skynet 的 DFUDetector 先检测后引导、iezpro 的完整状态机），新增一个独立的 `dfu_guide.sh` 脚本，提供：设备状态检测 → 机型识别 → 中文分步按键引导（含倒计时）→ 进 DFU 验证循环。

## 文件

- Create: `surrealra1n/dfu_guide.sh`（纯 bash，`#!/bin/bash`，UTF-8 中文界面）

## 架构与组件

每个函数单一职责：

| 函数 | 职责 |
|---|---|
| `detect_device_state()` | 输出设备状态：`DFU` / `Recovery` / `Normal` / `NONE` |
| `identify_model()` | 输出机型（如 iPhone12,8），供按键组合决策；拿不到时按有无 Home 键询问用户 |
| `guide_to_dfu()` | 分步按键引导（按机型分支）+ 倒计时 |
| `wait_for_dfu()` | 轮询验证进入 DFU（`irecovery -q` 的 MODE + USB VID/PID 兜底） |
| `main()` | 菜单：1. 引导进 DFU 2. 仅检测状态 3. 退出 |

依赖：仅项目已有的 `./bin/irecovery`、`idevice_id`、`ideviceinfo`，无新依赖。

## 检测逻辑

状态检测优先级：

| 状态 | 判定方式 | 优先级 |
|---|---|---|
| DFU | USB VID/PID = `05ac:1227` | 1 |
| Recovery | USB VID/PID = `05ac:1281` | 2 |
| Normal | `idevice_id` 能列出设备 | 3 |
| NONE | 都检测不到 | 4 |

- macOS 用 `ioreg -r -c IOUSBHostDevice` 查 VID/PID（无需 sudo）；Linux 用 `lsusb`（按 `uname` 分支）
- DFU/Recovery 下用 `./bin/irecovery -q` 二次确认（MODE 行）

机型识别：
- Normal：`ideviceinfo` 取 `ProductType`
- Recovery：`irecovery -q` 取 `PRODUCT`（板型，如 d79ap），用板型→按键映射表判断（iPhone 5s/6/6s/SE1 板型 n51ap/n53ap/n61ap/n56ap/n66ap/n71ap/n69ap → Home 键；d* 板型（iPhone 7 及以后）→ 音量减；j* 板型（surrealra1n 支持的 A7-A13 iPad 全部带 Home）→ Home 键）
- 两者都拿不到：按有无 Home 键询问用户

按键组合映射（覆盖 A7-A13，按"DFU 进入是否使用 Home 键"判定）：
- 使用 Home 键（iPhone 6s 及更早、SE1、iPod touch、带 Home 的 iPad 含 iPad Air 3/iPad 8/9 代）：按住电源+Home 10 秒 → 松开电源 → 继续按住 Home 直到 DFU
- 使用音量减（iPhone 7/8/8+/X 及以后所有 iPhone 含 SE2/SE3、无 Home 的 iPad Pro/Air 4+/mini 6+）：按住电源+音量减 10 秒 → 松开电源 → 继续按住音量减直到 DFU
  （注：iPhone 8/8+ 虽有实体 Home 键但为固态按键，DFU 进入使用电源+音量减，与 iPhone 7 相同）

验证循环：每 1 秒轮询 `irecovery -q`，`MODE: DFU` 即成功；兜底 USB VID/PID = 1227；默认超时 120 秒，`DFU_GUIDE_TIMEOUT` 环境变量可覆盖。

## 交互界面

```
=== 引导设备进入 DFU 模式 ===
设备：iPhone SE 2nd generation (iPhone12,8)
当前状态：正常模式
按键组合：电源 + 音量减（无 Home 键）

请按以下步骤操作：
① 同时按住「电源键」和「音量减键」，保持 10 秒
   [倒计时 10 9 8 ... 1]
② 松开「电源键」，继续按住「音量减键」
   （屏幕保持黑屏，等待设备进入 DFU）
③ 保持按住，等待自动进入 DFU 模式...
[验证中，已等待 15 秒...]
✅ 设备已进入 DFU 模式！
```

- 倒计时与现有 surrealra1n 风格一致（`echo "10" && sleep 1` 式递减）
- 进入 DFU 后显示"设备已进入 DFU 模式！"退出码 0
- 设备已在 DFU：直接提示"设备已处于 DFU 模式，无需引导"并退出 0

## 错误处理与退出码

| 场景 | 行为 | 退出码 |
|---|---|---|
| 成功进入 DFU（或已在 DFU） | 显示成功提示 | 0 |
| 引导超时（120s 未进入） | 提示检查按键操作，建议重试 | 1 |
| 检测不到设备 | 提示检查连接线/USB 口，循环等待或退出 | 1 |
| irecovery 不存在 | 提示运行依赖检查 | 1 |
| 用户 Ctrl+C | 干净退出 | 130 |
| 菜单选 3 退出 | 显示"正在退出" | 2 |

菜单选项 2（仅检测设备状态）执行后刷新状态并返回菜单（不退出）。

## 测试

1. `bash -n dfu_guide.sh` 语法检查
2. 离线分支测试：PATH 前置 mock 命令（假 `irecovery`/`ideviceinfo`/`ioreg`）模拟 DFU/Recovery/Normal/无设备四种状态，验证各分支输出与退出码
3. 实机验证：设备插线跑一遍全流程

## 不做的（YAGNI）

- 不做 pwn/引导 ramdisk（那是 spiro.sh 的职责，本脚本只管进 DFU）
- 不移植 spironolactone 的 lib/ 设备检测库（557 条映射对进 DFU 过剩）
- 不做 GUI/图像化引导
