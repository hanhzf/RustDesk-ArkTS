# 第五轮：已授权采集观察与租约清理证据

本轮范围收敛为“真实已授权采集 → 既有帧租约 → owned VP9 输入”的有界诊断，不开启生产 `ohos-owned-input-strict`，不改变前端布局、协议、认证或录屏同意语义。**代码、构建和安装完成；未授权拒绝通过，真实采集仅局部帧成功，8 帧诊断未通过。全链零拷贝仍未达标。**

## 约束与实现边界

- 新 DEBUG Want `rustdesk.captureInputProbe=1` 与前三种诊断互斥；必须恰有一种参数为字符串 `1`。不会启动 runtime/host/capture、申请权限、修改 Config 或回放诊断启动前的历史帧。
- 正常采集入口是服务端 tab → `启动服务端` → 系统录屏确认；不要求先有 peer 连接。已有 `StartScreenCaptureWithSurface` 路线保留系统提示。
- 未处于正常已启动的 native capture 时诊断拒绝，不替用户开始录屏；所有像素和压缩数据仅在 App 内暂存，不写文件、不记录图像/指针/校验值、不发送给外部服务。
- 观察 hook 只能在既有合法 lease 取得之后运行；额外引用只 clone Arc，不另 Acquire、截图、复制或重排输入。
- handoff 容量 1，空槽才 try-offer，满槽/锁竞争跳过抽样，不替换旧槽。原因：最后一个 lease Drop 可能调用原生 Unmap/Release，不能让替换逻辑阻塞 UI/采集回调。worker 处理帧＋待处理最多 2 个；终止与排空的最后引用由 worker 释放。
- 只验证有限帧的编码/解码数量、尺寸和固定布局；不把抽样称作持续会话、最新帧策略、画质、性能或全链零拷贝证明。

## 已完成的租约清理窄修

`../R_RustDesk-Har/src/ohos_capture_lease.rs`：全部 11 个 Unmap 调用点原先忽略返回码，现通过单次 wrapper 记录结果；Release/Unreference 同样记录固定大小、饱和计数和最后错误码。`cleanup_health_snapshot()` 不调用 native、不持有像素、不输出指针、不重置计数；记录锁在 native 调用返回后才取得。没有增加失败重试或改变 fence 所有权。

计数是**进程内所有采集清理**的结果，不能把其变化全部归因于诊断，也不能把 Drop 已调用等同驱动释放成功。Map/Unmap/Release 仍可能阻塞或返回错误，计数不负责恢复。

父提取真实 `NativeCallHealth`/`CleanupHealthSnapshot` 与 `cleanup_tests` 经 `rustc --test` 执行 3 项通过：错误保留/饱和、并发记录、额外 Arc 延迟最后租约清理。最后一项是所有权模型，不调用 FFI，不证明真实驱动完成。

API 依据：[录屏基础流程](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avscreencapture-c-basic-process)。lease 子任务另核对官方 native_image/native_buffer 文档和本机 SDK 头：MapWaitFence 自 API23、成功才消费 fence；Release 消费 fence，失败后保持原先单次 Unreference 路径。没有引入高于源码目标 API23 的 API；当前实际 SDK 仍为 API26。

## 新确认但本轮尚未修复的 strict 服务问题

Core `src/server/video_service.rs` 的 strict 构造/提交错误虽退出当前 `run`，`src/server/service.rs` 外层仍在 active 且有订阅者时持续重试（最大退避约 1 秒）。持续非 VP9 协商/缺能力/提交失败会导致重复初始化与日志，并非整个服务的终止失败状态。**尚未发现静默像素复制降级；这是无限错误重试问题。**

下一优先修复已收敛到两个 Core 文件：类型化 strict fatal 错误 → 视频专用暂停 gate → 复用现有非致命 MessageBox 通知全部新旧订阅者。仅真实新订阅 epoch、strict 配置、codec 或 I444 变化恢复；同值配置/QoS 波动不恢复。普通 SWITCH 和 legacy 不改，不增加协议或 Retry UI。需单独测试并验收，不把本轮方案当已实现。

## 构建、目标验证与产物

### 代码与测试

新增 `../R_RustDesk-Har/src/ohos_capture_input_probe.rs`，`src/lib.rs` 仅增加模块、三条 NAPI、合法 lease 后的观察 hook 和 owner 关闭后的原子取消通知；`package/index.ets`、`types/index.d.ts` 导出三条匹配接口。没有更改 capture 启停语义、Core codec 或生产 strict 选项。

ArkTS `NativeBufferDiagnosticService.ets` 增加第四种诊断，destroy/本地 deadline/异常只请求一次诊断取消，不停止用户采集。capture 的逻辑 terminal 与 worker 仍在运行可以同时成立：UI 在原有 12 秒/40 次上限内继续 poll；超限后不能伪造清理完成。安全 detail 只输出固定尺寸、计数与全局 cleanupHealth，不输出像素、码流、指针或输入内容。

- lease 清理统计与共享 Arc 模型：父提取实际源码，3 项通过。
- capture probe 的实际 State/Handoff/原有测试：子任务提取原样源码，宿主 rustc 3 项通过。未覆盖全部实际原子竞争/FFI。
- ArkTS 实际 ETS 经 Node TS stripping + VM mock 的 3 组回归通过：四 kind 全部 16 组合、40 个非法参数值、debug 异步门控/重复/销毁、异常/截止、terminal worker=true 继续等待、worker=false 收尾；其他三种诊断行为保持。脚本 `/tmp/capture-input-review-20260819.cjs`，不是设备 Hypium 或 ArkTS 类型编译。
- 独立只读复核未发现新增 UI/采集回调最后 lease 析构、停后遗留 pending、提前报告 worker 完成等高置信度问题。短 metadata mutex 不跨 native 调用；原有采集生命周期仍可能包含 native 阻塞，不能把 observer 的约束扩张为整个系统的实时保证。

### 构建与安装

- Core/HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked` 通过，2m36s；7 个相关源码在构建前后 SHA 完全相同。首次检查仅因父新增 detail 的格式换行失败，修正后才进入这次成功的 Cargo 构建。
- 原有版本化 VP9 验证保持，未重做或换用实验库。源仓和 APFS 镜像均通过 refresh 脚本重装依赖。
- 镜像 service 与源仓差异核对只包含本轮改动，更新后两份 SHA 都为 `4f69003ae332213f015721a7c2525026b7c765bfe3f4dc18adeab9f7e3a33ee0`。
- `hvigorw tasks --mode project --no-daemon` 确认 App 级 assembleApp；项目级列表未显示 test 任务。`assembleApp product=default buildMode=debug --no-daemon --no-incremental` 通过，9.018s。保留已有 warnings，未声称零告警；临时签名目录已清理。
- 仅 `127.0.0.1:5555` 使用 `install -r` 成功。安装查询 `1.0.3.88 / 10322965`、debug=true、debug Profile；源版本仍 `1.0.3 / 1000005`。

| 产物 | SHA-256 |
|---|---|
| package.har | `297e5605834fb5f5985b62b8db0bd4945b0265294e8d048a1eff58858ecb9b14` |
| 原始 HAR SO | `eecc96e1206c34bc67f499b606000de810986d1d62b386a4b901d9be29ce876a` |
| signed HAP | `b853114f4562a260254027750720e3bf69e9601c1d3f68bbdab388d9edfc6d20` |
| HAP stripped SO | `47d6e22d0b8fb96f8d7bd5105d5b1950707da4d3e65fc3ae6f39f2ed0fff5fe0` |

原始 SO 与打包 stripped SO 的 23 个可加载 section 属性/地址/大小/内容一致。构建日志：`/tmp/resk-zero-copy-round5-native.log`、`...-arkts.log`。

### 目标端结果：明确区分拒绝与部分成功

用户经本会话确认允许本次模拟器验证；两次真实测试均走正常“启动服务端”及系统“允许 Resk 使用你的屏幕”弹窗，保留已选的屏幕隐私保护。没有改权限/隐私配置。两次测试完成后均通过正常按钮停止服务端；最后 hierarchy 已确认恢复为“启动服务端”。为隔离 once-per-process，另使用了正常 `aa force-stop` / `aa start` 重新启动 App，没有卸载、清数据或重置偏好。

| 测试进程 | 场景 | 输入 / 结果 | 结束证据 |
|---|---|---|---|
| PID26589 | 已授权采集，诊断期间页面基本静止 | 1920×1280 RGBA，stride7680；2 编码 / 2 packet / 2 解码，未到目标8帧 | `deadline_exceeded`，10038ms，worker=false，RustScopesDropped=true |
| PID28517 | 新进程未启动采集，直接诊断 Want | `capture_not_active`，0 帧，cleanup 各调用数0 | terminal=true，worker=false，0ms；没有自动录屏 |
| PID1932 | 新进程正常授权，触发后尝试4次首页/服务端切换 | 同尺寸/格式；1 编码 / 1 packet / 1 解码，未到目标8帧 | `deadline_exceeded`，10024ms，worker=false，RustScopesDropped=true |

第二次切 tab 按用户要求逐条执行设备命令，**没有保证 0.5 秒周期或每次点击均落在诊断窗口内**，不能当作受控持续变化的基准，更不能据此排除静态/低变化采集假设。源码只说明 callback 依赖新 buffer 通知，Core latest-slot 不等待远端 peer；实际缺帧仍不能归因于 dirty-only、采样跳过、生产端停帧或 buffer 回收背压中的某一项。

有效日志：`/tmp/resk-zero-copy-round5-app-capture.log`、`...-inactive-final.log`、`...-motion.log`。inactive 初次 15 秒流式采集未覆盖到新记录，随后使用设备 help 确认的 `hilog -x` 非阻塞读取取得 PID28517 新记录；旧 PID 历史行不当作新结果。最后 motion 日志按 PID1932 和单 tag 过滤。

三个真实输入帧确实经过真实 capture lease → 新 Core owned 输入 → 普通 VP9 解码；**这不是8帧通过、持续会话、停启/旋转完整验收、逐像素正确性、驱动零搬运或FPS证明**。系统录屏本身仍包括正常系统音频能力，但诊断不额外消费/保存音频。

### 实际暴露的 Release 失败：尚未归因

首轮结束的全局累计：Unmap 7次/失败0；Release 7次/失败7/最后码41210000；Unreference 7次/失败0。第二次最终快照：Unmap 8/0、Release 8/8/最后码41210000、Unreference 7/0。后者是并行采集活动的瞬时累计快照，不保证三类调用同一时刻完成配对。

计数只证明全部已记录的 Release 均失败且**最后一次**为41210000；不能证明每次错误码相同，也不能把全局7/8次归给 probe 的2/1帧。先前口头“每次均为41210000”的表述已纠正。Unmap/Unreference 成功不证明 buffer 已归还队列。

只读核对发现 caller 从 Acquire 保存到 Drop 的原始 window_buffer 与 owner 配对未被转换/映射替换；失败后才额外单次 Unreference，没有成功后重复释放的证据。[华为契约](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-image-h#oh_nativeimage_releasenativewindowbuffer)和 [OpenHarmony SurfaceImage 参考实现](https://github.com/openharmony/graphic_graphic_2d/blob/master/frameworks/surfaceimage/src/surface_image.cpp)均支持 Release 成功才内部 Unreference、失败需 caller 补一次。

[OpenHarmony BufferQueue 参考实现](https://github.com/openharmony/graphic_graphic_surface/blob/master/surface/src/buffer_queue.cpp)中，按 sequence 查 cache 缺失会返回 NOT_IN_CACHE，尚未标 RELEASED/放回 freeList；ClearLocked/CleanCache/GoBackground 可清除 cache。因此 Arc 保活不等于队列成员资格仍存在。但这些是官方 master 参考，不是当前设备实现或逐帧事件，**不能据此判定这次设备确实清过缓存、是设备 bug，或解释两次超时**。

[native_buffer 参考实现](https://github.com/openharmony/graphic_graphic_surface/blob/master/surface/src/native_buffer.cpp)还显示 MapPlanes 可能先 Map 成功、再 GetPlanesInfo 失败；现有 Map fallback 不区分这种部分成功。这是已知映射状态盲点，不是已证实的 Release cache miss 根因，本轮未借机增加重试或像素复制。

## 下一轮优先级

1. 先实现上文两文件 strict 永久错误暂停/事件恢复，避免无限重建；不新增协议、全局回退或更改前端布局。
2. 针对当前设备追踪 capture buffer 回收及已停止 owner 的队列成员资格，诊断必须区分清理调用成功、scope退出、队列归还；不能通过补引用/忽略错误/CPU复制猜测修复。
3. 真实持续帧、尺寸变化与显示路线仍须验证；此前 DMA-BUF EACCES 与 GLES3.0 拒绝结论不变。长期目标保持 active，不标完成或 blocked。
