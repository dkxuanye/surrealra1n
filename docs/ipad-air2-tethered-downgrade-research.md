# iPad Air 2 有线（tethered）降级调研

调研日期：2026-09-08 · 范围：Reddit / GitHub / 工具源码 / 作者一手发言
对象：iPad Air 2 = iPad5,3 / iPad5,4 = **j81ap / j82ap** = **Apple A8X (T7001)**，系统终点 **iPadOS 15.8.8**

---

## 0. 结论先行

**"iPad Air 2 没有有线降级"这个前提不准确。** 它确实有有线 tethered 降级，但可用区间比同代设备窄得多，且每往下一档功能就残一截。真正的卡点不在 checkm8，而在 **A8X 的 SEP 断档**：

| 环节 | iPad Air 2 状态 |
|---|---|
| checkm8 / pwned DFU | ✅ 完全可用（A8X 在 checkm8 覆盖内） |
| SEP 漏洞（hardbird/blackbird） | ❌ **都没有** —— 唯一断档代际 |
| 借用最新签名 SEP（15.8.8） | ⚠️ 可用，但 ABI 向下只兼容到 **11.3** |
| 去掉 SEP（seprmvr64） | ❌ surrealra1n 官方名单里没有 A8X |
| 免线（untethered）降 10.3.x | ❌ wiki 点名 "this excludes iPad Air 2" |

---

## 1. 前提修正：它其实有

- **surrealra1n 官方 wiki**（2026-08-17 修订）"Supported Devices" 明确列出 **iPad Air 2：Supports tethered downgrades to iOS 11.3 or later**。
- **作者 pwnerblu 本人实机做过**（X 发言）：*"i tether downgraded my ipad air 2 from ios 15.8.6 to 11.3 using haxx (this currently uses latest sep, not blackbird, so 11.3 is the lowest possible without losing a ton of sep related features) — SEP functionality is mostly intact in this setup except for Touch ID"*。
- 社区其它工具链：Semaphorin（y08wilm，基于 checkm8 + seprmvr64，A7–A9）设备清单含 iPad Air 2；sunst0rm / downr1n / dualra1n 对 A8X 也列了 tethered 路径。

**真正没有的三件事**：
1. 低版本（≤ 11.x，更不用说 10.x / 9.x）**且 SEP 功能完好**的有线降级；
2. 免线 untethered 降到 10.3.x（wiki 显式排除 Air 2）；
3. turdus merula / blackbird 那条"任意版本随便降"的通路。

---

## 2. 三条硬阻塞

### 阻塞 1：A8X 既没有 hardbird 也没有 blackbird（根因）

SEP 有自己的固件、独立签名。即使你手握 SHSH blob + bootrom 漏洞，SEP 不配合照样恢复不了。

| SoC | SEP 漏洞 | 对应工具 | 结果 |
|---|---|---|---|
| A7 | hardbird | LeetDown / Legacy iOS Kit | **免 blob 降 10.3.3** |
| A8 / A8X | **无可用实现** | — | 断档 |
| A9(X) / A10(X) | blackbird | turdus merula | 任意版本，有 blob 则不连线 |

`bootloader-unlock-wall-of-shame` 直接写明：**"A8 is currently not supported"**（blackbird 理论覆盖 A8–A10，但公开实现只落地了 A9/A9X/A10/A10X）。A8X 连理论落地都没有。

### 阻塞 2：只能借用 latest SEP，而 15.8.x 的 SEP 向下兼容窗口很窄

iPad Air 2 系统终点是 15.8.8，能合法拿到的 SEP 只有 15.8.x。用它去喂旧 iOS：

- 作者实测：**11.3 是在"不丢一大堆 SEP 功能"前提下的地板**；
- 再往下 SEP 提供的服务逐项失效，到 11.2 及更低直接无法完成恢复。

### 阻塞 3：A8X 是孤品，没有同族 SEP 可借

- iPad mini 4（iPad5,1/5,2 = **j96/j97**）能降到 **10.x**，靠的是脚本里的 `download_tvos_sep`：拉 **AppleTV5,3 (j42d) 10.2.2** 的 tvOS SEP 当 "cursed SEP" 顶替 —— Apple TV 4 恰好也是 **A8**，SEP 同族。
- iPad Air 2（**j81/j82**）是**唯一**的 A8X 设备，脚本里单独分了一支 `REFER="ipad5b"`，**没有同族 SEP 可借**。
- 结果：mini 4 的档位是 "10.1–10.3.3 和 11.3+"，Air 2 只有 "11.3+"（代码实际 12.x+）。

---

## 3. 当前项目（本地 surrealra1n v2.1 beta）的真实判定链

本地这份是 `v2.1 beta`（分支 `v2.1-beta-switch`）；我拉取上游 `development` 对照，上游已到 `v2.1 beta 3 re-release`，**两边都还保留同一行 A8X iOS 11 拦截** —— 不是本地改坏了，是上游就还没开放。

`do_tethered_restore()` 里对 iPad5,3/5,4 的判定（本地行号）：

| 行号 | 条件 | 结果 |
|---|---|---|
| 3540 | 7.x – 11.2.x | `SEP 不兼容` → exit 1 |
| 3564 | **11.x（全部）** | `surrealra1n v2.1 beta 尚不支持 A8X iOS 11 降级` → exit 1 |
| 3548 | 13.1 / 13.2 / 13.3 | `不支持 13.4 以下的 13.x 恢复` → exit 1 |
| 3514 | 12.x（及 11.3/11.4，但被 3564 拦掉） | 放行，警告 Touch ID 失效 |
| 3516 | 12.x 且 iPad5,3/5,4 | 追加警告：**USB 配件不可用 + 深度睡眠问题** |
| 3510 | 13.x | 放行，警告 Touch ID 失效 + 深度睡眠 |
| 3507 | 14.x / 15.x | 放行，仅提示深度睡眠问题 |

**代码实际可用区间 = 12.x / 13.4–13.7 / 14.x / 15.x。** 比 wiki 写的 11.3 高一档 —— 因为 3564 行对 11.x 是无条件拦截，把 11.3/11.4 一起挡在外面。

**wiki 与代码不一致的原因**：wiki 那条 "11.3 or later" 是作者用 haxx 手工达成后写进去的，**代码路径还没落地**。这是该社区常见的抱怨点。

**seprmvr64（去 SEP）这条路也走不通**：wiki 的 seprmvr64 名单只有 iPhone 5S / iPad Air 1 / iPad mini 2，**不含 iPad Air 2 与 iPad mini 4**；而 `restore_tethered_opts()` 只在目标版本为 7/8/9 时才走 seprmvr64 分支，且 8.x、9.3.x 又各自被显式拒绝。

---

## 4. 社区口径对照

| 来源 | 对 iPad Air 2 的说法 |
|---|---|
| r/iOSDowngrade 置顶长帖（LukeZGD，Gist + Reddit 双向维护） | 把 **iPad Air 2 / mini 4 单独归入 "iOS 14-15 devices" 一组**（其它 A7/A8 归 "iOS 12 devices"），因终点是 15.x，SEP 兼容窗口完全不同。该帖（futurerestore 路径）口径更保守：**只能用 blob 恢复到 14.x/15.x，"13.x and lower 即使有 blob 也不行"** |
| surrealra1n wiki | 官方矩阵：**tethered 到 11.3+**；untethered 10.3.x **排除 Air 2** |
| pwnerblu（作者 X） | 实机 15.8.6 → 11.3 成功，指明 11.3 是不丢 SEP 功能的地板 |
| Semaphorin（y08wilm） | 设备清单含 iPad Air 2（seprmvr64 路线，代价是 Touch ID / 密码 / 加密 Wi-Fi 全废） |
| turdus merula (sep.lol) | 明确 **A9(X)/A10(X) only**，A8/A8X 不在列 |
| surrealra1n Discord | 官方支持主阵地（README 里的 discord.gg 链接），**服务器内容不被搜索引擎索引，无法远程取证** —— 本报告中涉及"最新状态"的部分以 wiki + 作者 X 为准 |

---

## 5. 一句话归因

> iPad Air 2 不是没有有线降级，而是卡在 **A8X 的 SEP 断档**：
> 没有 hardbird / blackbird → 只能借用 iPadOS 15.8 的 SEP → SEP ABI 向下只兼容到 11.3（代码实际 12.x）→
> 想再往下（10.x / 9.x）必须走"去掉 SEP"的 seprmvr64，而 surrealra1n 的 seprmvr64 名单里没有 A8X。

---

## 6. 可能的突破口（按可行性排序）

1. **等 pwnerblu 把 haxx 的 11.3 路径合进脚本** —— wiki 已写、作者已跑通，只差落地。这是最近的一档。
2. **给 seprmvr64 补 A8X 支持**（Semaphorin / downr1n 声称做到的那条路）—— 代价是 Touch ID、密码、受密码保护的 Wi-Fi 全废，且需处理激活记录。
3. **把 blackbird 移植到 T7001 SEPROM** —— 天花板最高，但需要 SEPROM 层面的逆向投入，A8 本体都还没人做。
4. **找 A8X 的"可借 SEP"** —— 基本无望，A8X 是孤品 SoC，无同族设备。

---

## 附录：证据指针

- `surrealra1n.sh`（本地，v2.1 beta）：行 1426–1435（REFER 分支）、1529–1539（j81/j82 boardid 与 LATEST_VERSION=15.8.8）、2018–2054（`sep_checker`）、2056–2066（`download_tvos_sep`，AppleTV5,3 j42d）、3480–3573（`do_tethered_restore` 全部判定）、4134–4237（`do_tethered_seprmvr64_restore`）
- 上游对照：https://raw.githubusercontent.com/pwnerblu/surrealra1n/development/surrealra1n.sh （v2.1 beta 3 re-release，行 3516–3517 同样拦截 A8X iOS 11）
- https://github.com/pwnerblu/surrealra1n/wiki/Supported-Devices
- https://gist.github.com/LukeZGD/9d781f1b03a69fa46869384a9407a41a （Reddit 镜像 r/iOSDowngrade）
- https://sep.lol/ （turdus merula）
- https://github.com/zenfyrdev/bootloader-unlock-wall-of-shame/blob/main/brands/apple/README.md （SEP 漏洞代际覆盖）
