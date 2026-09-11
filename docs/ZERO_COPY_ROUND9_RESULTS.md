# 第九轮：独立增强分支、无应用 GLES 的软件最终窗口直写

**2026-09-09：本轮源码接线、目标构建、保数据安装与启动检查完成；不是实际远程窗口、整链零拷贝或高帧率验收声明。**

## 用户新增方向与分支

增强版优先极致性能、高帧率、低延迟和最短编解码/上屏路径；可去除或重构限帧设计，不要求保留应用 GLES 路线。必要资源寿命、fence、解码参考链、隐私与明确失败不因此取消。

三个权威仓库均创建 `perf/zero-copy-high-fps`，未提交或推送：

| 仓库 | 保持不变的 HEAD | 原分支 |
|---|---|---|
| Core | `4014999b9` | `feat/ohos-unified-core-flutter` |
| HAR | `64d39a8` | `main` |
| ArkTS | `9b7bf4a` | `main` |

切换前后 HEAD、porcelain 状态和已跟踪二进制 diff 哈希一致。原分支指针未变；**现有改动仍未提交，保留在当前工作树，并非已获得 commit 级隔离的版本快照**。没有自动把用户原有其他改动纳入提交。

## 本轮已实现的源代码

### Core

- `GoogleImage::to_into` 校验尺寸/格式、目标容量/实际 byte stride、源 plane 数量/空指针/stride、溢出与 libyuv 返回码。直接写借用目标，不构造伪 Vec 所有权或中间 RGB Vec；raw plane 实际 allocation length 仍依赖 decoder 合约。
- 新 `software_present.rs` 同步 object-safe target、实际 decoded 尺寸、提交/不可用原因、generation 注册与移除。锁内仅查找/clone Arc；转换、回调和旧 owner Drop 在锁外。
- OHOS VP8/VP9/AV1 增强输出无条件使用新 route；未注册/暂不可用/失败均不回退 RGB。其他平台保留原回调 API。所有参考链数据仍解码，仅最后输出进行必要色转；最终 packet view 必须在 flush 前消费，flush 有额外输出时可能再提交，不保留已失效指针来省这次处理。
- 客户端区分 decoded 与 submitted，绕过软件 on_rgba；录像使用实际解码尺寸。提交不等于物理显示，当前 decode_fps 计时仍包含同步目标等待，不能冒称纯 codec 吞吐。
- 能力报告不再把已移除的 PixelMap 中转写成当前事实，也不把 external allocator 列为该新路线必需；新的 decoder/窗口证据仍 unverified，未提升为达标。

### HAR

- `ohos_software_window.rs` 延迟在 frame worker 创建/复用最终 NativeWindow，必要时更新尺寸；CPU_WRITE、RGBA8888，Request timeout 请求1ms，fence 单次 poll1ms，无 frame 队列/sleep/线程。SDK声明不保证 FFI 硬实时。
- Map→同步独占 slice 回调→Unmap→Flush；成功 Request 的 fence 单次关闭，失败路径单次 Abort。没有套用 capture 的 Reference/Unreference 规则。
- 官方 NO_BUFFER=40601000、BUFFER_QUEUE_FULL=41209000 且错误出参未被改动时，只丢本次显示，下一解码帧可新 Request；EINTR 同样不永久锁死窗口，也不立即重 poll。未知/不一致错误仍失败锁定。
- 失败 Request 若改动 buffer/fence 出参，SDK未规定其所有权：不猜测 Abort/close，标 cleanup uncertain，保留有界隔离 owner/permit，可能保留资源至进程退出；不能说清理成功。
- 写入/提交采用明确 reservation 线性化；close 仅即时逻辑失效，已预留操作不能强杀，保持 ClosingInFlight。宽高以一颗 packed atomic 发布，避免用于输入的尺寸混代。
- `ohos_software_present_bridge.rs` 对接 Core trait，little-endian ABGR 输出 RGBA。单一生命周期 retirement worker + 有界 channel，16个 permit 约束 active/retiring/quarantined 的资源，不是 FPS 上限。最终 wrapper Drop 移交 owner，UI 不析构原生窗口；故障隔离使用预分配 Mutex<Vec>，不增加热路径锁或 unsafe 原始指针管理。
- Surface 相同重复绑定保持 generation；解绑/更换先失效旧 writer、精确移除注册，锁外 retirement。新 `sessionGetSoftwarePresentState` 仅低频安全元数据，无 surface ID、指针或像素。
- 停止编译应用 GLES probe/readback 模块；旧 NAPI probe 入口返回明确 disabled，保留源文件作为历史，不再链接该应用实现。不能据此宣称系统内部不使用 GPU/GLES。
- 修复采集早到首帧跳过 SetMaxVideoFrameRate 的 ordering，透传校验后的帧率请求、区分返回码与实测。授权/首帧超时不属于稳态帧率 cap，未盲删。

### ArkTS

- 完整移除视频 RGBA fetch→createPixelMap 链；未知 codec、metadata 错误也不复制兜底。保留已有 XComponent、原生 texture/Surface 路线和布局；H264/H265 名称本身不证明实际后端是硬件。
- 新 `SoftwarePresentState.ets` 从既有50ms事件循环中最多每100ms取一次元数据；它不泵送像素，不限制 Native FPS。成功绑定只 pin generation，不假报首帧；真正提交后才更新尺寸。
- 明确 H264/H265 优先于同 generation 的历史软件提交；已提交之后的 Busy/NoBuffer 保留画面/尺寸，不灰屏闪烁，不冒充新首帧。解绑/换代/关闭/失败不沿用背压状态。

## 平台能力与真实限帧点

本地官方镜像（2026-04-24更新）与本轮在线官方查询一致：`OH_AVScreenCapture_SetMaxVideoFrameRate` 当前最高60FPS，入参超过60仍按60处理。去应用 clamp 不证明超过60；更高采集率需要平台新能力。来源：[官方 API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-avscreen-capture-h)。

已定位但本轮未粗暴删除的后续重点：

1. Core `video_qos.rs` 默认30/最大120、多用户取最小预算，发送循环按 spf 补等待；INIT15仅首秒，不是永久cap。
2. `client/io_loop.rs` 的>120回落30、最慢显示解码反馈与0.9/0.8系数；应先拆解 decode 与 present-wait 计量，不把窗口背压误判为 codec 能力。
3. 发送端所有连接逐帧 barrier 可被慢端拖住；无显式 ACK 时通知在socket发送前出队阶段，不等同全部是网络ACK。需先建立每连接有界预算与epoch恢复，再解耦，不能单删等待放大队列。
4. owned VP9 当前仅验证单线程、row-mt/tiles关闭；OHOS VPX/AV1已lag0。多线程必须验证最终输入槽、上一source、取消与复用寿命，不是随手调线程数。

## 验证进度与尚未通过项

- 子任务实际宿主纯逻辑测试：writer2组＋bridge1组、ArkTS2组通过；源码层测试不是实际 NativeWindow/ArkTS设备运行。
- 本机 SDK aarch64 clang++ `-fsyntax-only` ABI 检查通过：枚举、结构尺寸/offset、函数签名、poll、错误码/EINTR；无链接或实际 FFI。
- Core 首次联编因新出现的 `native/ohos_bridge` 三个文件删除而缺 manifest，未进入编译。用户明确选择仅恢复三个 HEAD 文件；已执行并核对该目录无 diff，其他改动未恢复。随后完整 Core release lib-test 编译通过（1m05s）；**该步骤不运行 scrap 依赖中的 libyuv 测试**。
- Scrap release lib-test 单独编译通过（1m26s）。只在 `127.0.0.1:5555` 执行真实源码的 direct_conversion 2项和 capability_gate 3项，全部通过；核对实际test result数量而非只看hdc exit0。色转测试调用目标真实libyuv并验证5种原有格式/色度组合、奇数尺寸、padding/canary，不是纯mock；仍不是窗口或整链证明。
- Core→HAR release生产联编通过。使用本轮实际 command-line-tools SDK 再跑 aarch64 C++ ABI syntax probe，通过；新 `.so` 的 DT_NEEDED 不含 EGL/GLES，也没有未定义 `egl*`/`gl*` 导入，不能将此推广为系统内部没有 GPU/GLES。
- 源码仓和 APFS 安装镜像都经 `scripts/refresh-native-har.sh` 重建依赖；HAR hash、安装后声明/新getter/原生库匹配。14个变更 main 源文件逐字节与镜像一致，连同测试共同步19个文件。
- Java17、`hvigorw tasks --mode project`、App级 `assembleApp product=default buildMode=debug --no-daemon --no-incremental` 通过。临时签名目录使用 EXIT trap 清理。未改源码版本或本轮套用 CI 动态版本；APFS 安装镜像沿用设备原有较高版本以避免降级清数据。
- 仅向 `127.0.0.1:5555` 执行 `install -r`，明确返回成功；`aa start`成功，启动PID5857。安全UI白名单观察到 RustDesk/就绪/服务端/设置，不输出账号、设备ID或密码；本轮未启动录屏，也未改变隐私保护选项。
- 实际新包调用旧GLES诊断入口返回 `unsupported / disabled_enhanced_branch / terminal=true / workerMayStillBeRunning=false / elapsedMs=0`，验证它确已禁用，而不是启动GLES再失败。当前设备仍API26；安装信息为 `1.0.3.88 / 10322965 / debug=true / appProvisionType=debug`。目标测试程序及包含UI数据的临时layout文件已清理。

### 本轮产物

HAP：`/Volumes/RustDeskBuildCache/arkts-workspace/entry/build/default/outputs/default/entry-default-signed.hap`

| 产物 | SHA-256 |
|---|---|
| HAR `package.har` / App `rustdesk-ohrs.har` | `1fcdd694112fdea27b176c1585a07e9f2f242991e1f66cf0d8c42f6c3f5698c8` |
| HAR原生库 | `4d809f20aef743ebc6683193b78d6a40ea1ed02602919cf28af172199b46b5ab` |
| HAP内strip后原生库 | `93e163745f618ae2c9342504792f78d3d1fe504fdb942c8f9b252f2c6c6a01ec` |
| default/debug signed HAP | `3734c7156f75cfd3da15c03adcba1e25e175fbba24e22d2dffe7cfdfee074eb1` |

原生库整文件hash因strip不同；已核验全部23个SHF_ALLOC节的地址、类型、大小、内容一致。构建日志 `/tmp/resk-zero-copy-round9-native.log`、`/tmp/resk-zero-copy-round9-arkts.log`；禁用入口实际日志 `/tmp/resk-zero-copy-round9-gles-disabled.log`。签名材料不入库、不输出。

仍未验证完整 codec 内部/驱动/合成零拷贝，真实 Surface 提交/尺寸/解绑压力与软件↔硬件 codec 切换资源交接；编码侧普通跨帧 capture Release41210000 缺口仍保留。**没有整链达标或持续 FPS 数字。**
