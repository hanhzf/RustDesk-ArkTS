# 性能优先与零拷贝架构规划

状态：2026-09-08 用户已授权实施；原规划保留作验收合同。实际代码、测试与未达标项见 `ZERO_COPY_IMPLEMENTATION_STATUS.md`，不能把接口接入等同于整链零拷贝通过。

## 1. 已确认的产品决策

1. 前端恢复至 ArkTS 仓库 `main / 9b7bf4a` 的已提交方案，不继续追求 Flutter 外观逐项对齐。
2. 效率与性能优先，允许替换 RustDesk 中拖累目标场景的实现；不要求保留每一种上游设计。
3. 官方原版只要求基本互通，不保证与原版互通时的性能，也不追求完整功能对等。
4. **零拷贝为硬性要求；优先让兼容模式和高性能模式都零拷贝。** 不把少拷贝、一次搬运或把拷贝移到 Native 当作达标，不预设兼容模式享有拷贝例外。
5. `Core -> HAR -> ArkTS` 依赖关系不变。认证、协议与会话在 Core；平台资源桥接在 HAR；页面、权限、输入采集与生命周期在 ArkTS。
6. 初版后端仅规划，后续用户明确要求直接实施。API 23 兼容目标、真实 `OH_AVScreenCapture`、禁止截图轮询、现有软件 codec 能力与用户授权边界继续有效。实际 SDK/模拟器版本必须另行核验，不能与兼容目标混称。
7. 用户进一步明确：为极致性能可以修改**编码端**，不把优化限制在解码/显示端。允许调整编码器内部输入接口与所有权，在保持基本 wire 兼容的前提下替换造成搬运的上游设计；发送侧和显示侧并行验收，不让显示可行性阻塞编码端工作。
8. 第九轮用户要求增强版独立开发分支，Core/HAR/ArkTS 已统一建立 `perf/zero-copy-high-fps`。增强版优先高帧率、低延迟和最短路径，允许去除/重构限制帧率的设计；不靠破坏参考链、取消资源同步、无界排队或虚报请求FPS来达标。原未提交改动保留，尚无commit级版本快照或远端推送。
9. **应用层 OpenGLES 不再作为必经路线。** 增强软件路径直接产出最终 NativeWindow RGBA，原生 codec 在设备支持时直接 Surface；GLES实验/readback不编入增强实现。系统 compositor/driver 内部实现必须另行验证，不能宣称所有GPU/GLES依赖都从系统消失。实际实现与已确认限帧点见 `ZERO_COPY_ROUND9_RESULTS.md`。

## 2. 零拷贝验收契约

### 2.1 范围与计账

本规划首先约束**我方维护的视频像素路径**：采集到编码输入、解码输出到显示，以及这些路径中的跨层交接。与官方端互通也使用同一约束；不能替未经修改的第三方官方进程保证其内部实现零拷贝。

- 帧交接仅传递句柄、引用和布局描述，不因跨 Core/HAR/ArkTS 或线程而复制像素。
- 禁止 CPU 整帧打包、重排垫片、`Vec` 深拷贝、RGBA NAPI 搬运、PixelMap 视频显示，以及先 GPU 回读再上传的旁路。
- 仅为转交帧而执行的 GPU blit 也应列为搬运，不能因为 CPU 未调用 memcpy 就漏计。
- 编码、解码、必要缩放/色彩转换是产生新表示的计算，单独记录读写与输出缓冲；应直接产生最终消费者可用的输出，不能用“转换”掩饰中间副本。
- 元数据复制、压缩码流封包、加密及 OS socket 内存流动单独计账。本规划不声称全进程或内核中不存在任何 memcpy。
- “调用了 Surface API”只证明接口接线，不足以证明驱动没有隐式搬运；需结合 buffer identity、分配记录与平台 trace，说明能验证和不能验证的边界。

硬门槛：已覆盖场景的应用层视频搬运字节数为 0、跨 NAPI 视频像素字节数为 0、无回读/重上传旁路。必要转换的临时缓冲同样纳入审计。

### 2.2 不达标怎么办

能力表必须区分 `supported / unsupported / unverified`。未知不能当已支持。

- 缺少某个硬编器不能直接判定被看端不可用，仍需验证 Core 软件编码器的借用输入路径。
- 软件路径存在复制也不能被自动认可；应列出外部分配器、布局、共享内存或同步能力缺口。
- 没有共同的已验证路径时，明确提示不支持该 codec/设备组合，不暗中回退到复制路径。
- 如确实要保留非零拷贝的兼容例外，必须另获用户确认；本规划不批准该例外。

## 3. 源码事实与目前缺口

以下行号为调研时快照，仅作定位；实施前复核工作树。源码结构不等同于性能测量。

| 环节 | 已核实事实 | 意义 |
|---|---|---|
| 生产采集 | HAR `src/lib.rs::controlled_consume_surface_frame`，1320–1455：ConsumerSurface acquire、MapWaitFence、逐像素构造 packed RGBA，再 resize 和推送 Core | 当前不满足零拷贝；`ohos_capture_receiver.rs` 只是诊断候选，不可当生产依据 |
| 同尺寸 resize | HAR `src/lib.rs::resize_controlled_rgba`，2306–2307：相同尺寸仍 `rgba.to_vec()` | 明确存在可定位的搬运，不能只优化缩放算法 |
| Core 帧交接 | `libs/scrap/src/common/ohos/mod.rs::push_screen_frame_rgba` 和 `Capturer::frame`，46–60、98–113：`extend_from_slice` 与 `clone_from` | 需要重做所有权交接，而不只增加一个“零拷贝”标签 |
| Surface 解码 | Core `libs/scrap/src/common/ohos/avcodec.rs` 的 SetSurface / RenderOutputBuffer，HAR `session_bind_surface` | 已有 H.264/H.265 Surface 接线；实际零搬运需验证，不代表所有 codec 已覆盖 |
| 软件解码 | Core `codec.rs::Decoder::new` 的 VP8/VP9/AV1 分支、`flutter.rs::on_rgba_soft_render`，HAR `session_take_rgba_frame`，ArkTS `consumePreviewRgbaFrame` | 当前软件显示路径仍经 RGBA/PixelMap；带反压，不可臆测其实际流量或 GC 耗时 |
| 视频调度 | Core `src/server/video_service.rs::VideoFrameController::try_wait_next` 使用 `#[tokio::main]`；主循环 890–902 按所有连接通知等待，预算约 3 秒 | 可验证重复 runtime 构建与慢连接耦合；不是每帧必然等 3 秒 |
| 视频队列 | Core `src/server/connection.rs:472,1040–1049,2757`：无界 tx_video；未要求 ACK 时出队先通知后 send；要求 ACK 时按协议反馈 | 需和现有等待反馈一起改；不能从 unbounded 一词直接推断实际积压规模 |

当前真实全桌面动态画面与持续远端会话仍有未验收项，参见 `REAL_CAPTURE_SOFTWARE_ENCODING.md`。不能把 `.87/.88` UI 构建或 NativeBuffer 非零采样当作视频基线通过。

## 4. 单一媒体链，两种兼容策略

建议复用**一套媒体资源、编解码调度和安全会话**，而不是复制两套 RustDesk 核心：

```text
ArkTS：页面、权限、输入事件、低频状态
                │ 元数据/命令；无视频像素
HAR：Surface / NativeBuffer / fence 的平台生命周期
                │ 句柄、FrameLease、布局描述
Core：认证、协议适配、编解码、拥塞与资源调度
        ├─ 官方协议适配：基本互通，性能允许受对端限制
        └─ 增强调度策略：双方能力允许时启用，不改变安全语义
```

以上为运行职责示意；代码依赖仍是 HAR 依赖 Core、ArkTS 依赖 HAR，Core 不导入 HAR 或 ArkUI。

### 4.1 建议的内部契约（设计名，非现有 API）

- `FrameLayout`：尺寸、像素格式、planes、stride、crop、时间戳、色彩信息。
- `FrameLease`：不可变帧资源引用、session/generation/sequence 和释放责任；禁止以 Vec clone 实现“共享”。
- `MediaPathCapability`：codec、profile、尺寸/帧率范围、输入/输出内存类型、是否已验证无搬运。
- native 平台所有权由 HAR 管理；Core 接收抽象 view/lease 或平台后端资源，不泄漏 ArkTS 对象，也不逆向依赖 HAR。
- 释放条件同时满足：编码/解码不再引用、显示提交完成且相应 fence 可释放、旧 generation 无待用引用。
- 最新帧覆盖的是引用，不能覆盖仍被 codec 用作参考帧或仍被 GPU 消费的内存。

## 5. 编解码零拷贝路线与闸门

### A. 采集 → 硬件编码

优先验证 `OH_VideoEncoder_GetSurface` 与 `OH_AVScreenCapture_StartScreenCaptureWithSurface` 的公开对接。输出压缩码流仍交 Core 的正常协商/加密/发包链。

这是按能力选择的路径，**不是再次强制 H.264**。只有目标设备上实际创建、格式匹配、启动、出帧和释放全部通过才可启用；无 `libavcenc_ohos.z.so` 等情况明确记录，不伪造支持。

### B. 采集 → Core 软件编码

保留 VP8/VP9/AV1 能力，验证：

1. 借用真实 NativeBuffer 的映射 view 与 stride，格式计算直接写 encoder 最终可消费的 YUV planes，不产生 packed RGBA 副本。
2. 若平台原生输出与 encoder 输入布局可直接一致，直接借用 planes，连额外颜色转换也无需做。
3. 不能仅为对齐而新建中间像素缓冲。row padding 本身不代表不支持，需核对转换器/codec 的真实 stride 能力。
4. acquire/release fence、CPU/GPU cache 一致性、映射生命周期、encoder 内部导入/复制都要审计。不能把一次 Map 调用当作没有隐式拷贝的证明。

这条路线是有条件的可行性任务，不提前承诺所有设备/codec 都能零拷贝。

第三轮开始并行推进**编码器拥有的最终输入槽**：VP9 的 `lag=0` 仍保留 lookahead 输入复制，不能用 `vpx_img_wrap` 冒充消除。先在隔离的 libvpx 实验构建中验证 acquire/转换直写/commit/cancel、上一帧 source 寿命、边缘扩展及槽位复用，再接 Core 的独立直写入口。BGRA/RGBA→最终 I420 planes 属于必要变换；外部 I420→槽的同格式搬运不因此得到豁免。实验补丁及未接线的接口不是生产达标证明。

### C. 硬件解码 → XComponent

复用现有 SetSurface/RenderOutputBuffer 接入并补齐资源租约验证。不能先解到 CPU 再复制至 NativeWindow。

允许扩展到目标 SDK/设备实际支持的其他原生 codec，但先做 capability 查询与出帧验证；不是看 MIME 常量存在就宣称硬解可用。

### D. 软件解码 → 共享缓冲 → 显示

这是最大待验证项，不能用“移到 Native 里 memcpy”充数。

- 调研当前 libvpx/libaom 的 external frame allocator：分别核验 VP8、VP9、AV1 的实际支持，不按库名一概推定。
- 若 decoder 能直接写 GPU 可导入的共享 YUV planes，则 GPU 采样显示；禁止 `glTexSubImage` 从普通 CPU 帧上传或再复制到 Window buffer。
- 需要证明 decoder 对齐/stride/参考帧数量与平台 NativeBuffer 布局、GPU import、fence/释放机制兼容。
- 外部分配器不能用时，明确该组合暂未达标；研究平台原生 Surface decoder 或针对性 codec allocator 改造。不为覆盖一个组合默认重写所有 codec。

本轮已直接核对构建缓存中的依赖源码：libvpx **v1.16.0** 的 `vpx/vpx_decoder.h:318–359` 明确说明 external frame buffer 接口当前只对 VP9 生效，未声明能力的 decoder 返回 `VPX_CODEC_INCAPABLE`；其 `vp8/vp8_dx_iface.c:729–730` 未宣告此能力。libaom **v3.12.1** 的 `aom/aom_decoder.h:221–249` 提供 AV1 的 get/release frame buffer 回调。当前 Core 包装尚未接入这些回调。

因此优先原型为 VP9/AV1 外部分配与共享显示；VP8 在**当前 libvpx 这条路线**有明确缺口，需另测原生 decoder 或替换/调整软件后端，不能外推为“VP8 协议永远不可能零拷贝”。解码参考资源池与呈现队列独立计账，容量从实际 codec 请求、参考帧与 GPU 在途使用计算，不臆定通用的 3/4/12/16 个缓冲。

**第八轮显式增列独立实现候选（尚未实现/验收）：**不把 GLES3.1/SSBO/DMA-BUF import 当作一切零拷贝路线的必要条件。可让 decoder 所有的 YUV view 在有效期内，经必要色彩转换**直接写最终 NativeWindow RGBA buffer**，不生成 Core 中间 RGB Vec，不走 `session_take_rgba_frame` 的 clone、Uint8Array/PixelMap，也不追加逐行同格式复制。这沿用第2节及第5B节“必要计算直接产出最终消费者新表示”的规则，不是兼容模式 copy 例外，亦不代表 external allocator 路线已通过。

该候选需新建生产窗口 writer 与同步受检 dst-slice/实际stride接口，保持 Core→HAR→ArkTS边界。源 view/目标window owner及generation覆盖整个转换，slice不逃逸；Request/fence/Map/Unmap/Flush/失败Abort正确配对，保留原解码参考链、实际尺寸及协议ACK语义。必须继续审计解码内部与平台Map/合成隐式搬运并做实际窗口验证，未通过前仍 unverified；硬件缺失不触发静默copy fallback，也不据此宣称软件路线达到高性能目标。当前真实路径、最小改面与证据见 `ZERO_COPY_ROUND8_RESULTS.md`。

## 6. 调度、输入与前端减负

### 6.1 背压不破坏图像参考链

- 原始待编码帧队列仅保留最新 lease，建议初始容量 1–2 个引用；参考帧与驱动必需缓冲不计入此队列，另设内存预算。
- 编码前可丢过期 raw frame；编码后不可随意丢一个 P 帧。按 codec 的依赖链/关键帧 epoch 恢复，必要时丢弃受影响链并请求新关键帧，限制关键帧风暴。
- 发包按每连接的字节与时龄预算调度；元数据和关键控制不能被视频流长期饿死。
- 拆除所有消费者共同阻塞采集的耦合，但不能简单删除等待后继续保留无界生产。
- 官方连接保留正确的 ACK 语义，不用“低性能兼容”解释协议错误。
- 先改现有 TCP/KCP 路径的调度，不在本阶段另造 QUIC 或媒体协议；实测证明传输阻塞仍占主导时再评估。

### 6.2 跨层事件与输入

- 用有界、合并的 native 事件替代无变化也持续拉取全量状态的轮询；保留显式恢复快照与低频健康检查。
- 输入热路径改为类型明确的数值命令；冷路径配置可继续 JSON，不为追求口号重做所有接口。
- 移动事件可以合并；键/按钮 down-up、wheel 顺序与拖拽生命周期不能丢，generation 防止旧会话命令误投。
- 状态变化只更新所需子组件，光标/统计不驱动整个主页面。统计 UI 初始预算为 2–4Hz，属于规划值，后续按测量调整。
- native 异步事件本身也必须有容量限制、注销和旧 generation 过滤，不能把无界堆积从轮询搬进回调。

## 7. 最小官方兼容范围（建议，待产品确认）

| 功能 | 建议承诺 |
|---|---|
| 身份与连接 | 官方格式 ID / 直连地址、所选服务器/中继基本连接，保留 Core 的解析和握手 |
| 安全 | 保留密码、2FA、信任/拒绝、录屏权限及非安全连接确认语义；不借性能重写认证 |
| HarmonyOS 作主控 | 基本视频显示、键鼠输入；具体 codec 必须有已验证零拷贝组合 |
| HarmonyOS 被看 | API 23 真实屏幕与内音；不承诺当前 view-only 实现没有的系统输入注入 |
| 基础附属功能 | 建议保留文本剪贴板、普通文件传输，但按需启动，不争抢媒体资源 |
| 不承诺全面对齐 | 官方所有平台/版本、所有 codec/多屏排列、高级桌面功能和 UI 一致性 |

可裁剪候选优先采用按需加载/编译 feature：未用诊断路径、重复桥接、仅为桌面兼容加载的服务、后台不必要扫描及高频日志。是否删除终端、复杂多屏、接续、文件剪贴板等用户功能，需要实际依赖分析与确认，不因“累赘”二字擅自砍掉。

协议字段不得复用 tag 或改变既有 wire type。未知字段按 protobuf 规范容错；对不支持的业务请求显式拒绝/不宣告能力，不能一概静默 no-op 导致对端永久等待。

## 8. 分阶段交付与退出门槛

| 阶段 | 交付物 | 退出门槛 |
|---|---|---|
| P0-A 正确性与能力基线 | 真实完整动态采集、codec/Surface/共享缓冲能力表、各段 copy ledger | 当前画面正确；不能用稀疏采样或 UI 截图代替远端视频证据 |
| P0-B 所有权接口与采集零拷贝 | FrameLease/布局/fence 契约；按能力选择硬件或软件输入 | 已覆盖采集送编组合搬运计数为 0；取消、旋转、关闭均无泄漏/旧帧 |
| P0-C 解码零拷贝 | Surface 解码直显；软件 external allocator/import 可行性原型 | 展示帧无 RGBA/PixelMap/NAPI 搬运，引用帧与 GPU 生命周期正确 |
| P1 有界调度与事件桥 | 每连接背压、输入轻量 API、合并事件 | 慢连接不拖垮快连接，无花屏/按键卡住/旧会话误投 |
| P2 兼容与可选减负 | 固定官方版本矩阵、能力拒绝、按需功能 | 两种模式复用已验证零拷贝链，官方基础功能正确 |

阶段可按独占文件并行，但不能在新路径验证前删除旧路径并宣布完成。代码中保留旧实现用于开发对照，不代表发布时允许其静默成为零拷贝路径的后备。

## 9. 测量与验收

- 基线记录三个仓库 revision + dirty patch + HAR/HAP hash，避免测的不是改的代码。
- 本次允许操作的设备仍只有 `127.0.0.1:5555`。模拟器用于正确性、生命周期和有界队列测试；硬件带宽、持续帧率/功耗结论需未来获授权的真实目标设备。
- 性能 A/B 用 `default/release`，同设备、同 codec/分辨率/画面/网络/温度；本轮 `default/debug` 只证明 UI 回退编译与交互。
- 覆盖静态桌面、滚动、动态内容、分辨率切换、断连重连、一个快端加一个慢端、限速/抖动。
- 度量 capture/convert/encode/send/decode/present 分段耗时、P50/P95/P99、队列年龄和字节、帧租约数、CPU/RSS/功耗；不能把官方 RTT/FPS 当作端到端显示延迟。
- 跨设备时钟未同步时不直接相减。Surface 提交不等于物理屏幕呈现，需平台 present trace 或外部观测。
- 零搬运先过硬门槛，再评估性能。1080p60 可作为待确认的目标档，16.7ms 是其帧周期预算，不是已经实现的端到端延迟保证。
- 不承诺未经测量的倍数、500MB/s 堆分配、零延迟或固定工期。先跑可行性原型再估工作量。

只为所有权/fence、取消换代、丢帧参考链、协议能力协商这些复杂边界补测试，不铺设无价值的 UI 单元测试。

## 10. 本轮前端回退与验证

- 8 个组件与 `9b7bf4a` 精确一致：ConnectTab、DeviceDirectoryPanel、PeerCard、FloatingSurface、SessionToolbar、SettingsTab、ViewedHostCard、ViewedHostPage。
- `RustDeskIndex.ets` 只恢复 UI 布局/导航/组件参数，保留 EasyTier generation、预检、取消和会话衔接。
- 原修改备份：`/tmp/resk-frontend-before-revert.MshEhP/tracked-before.patch` 与 `tracked-files-before.tar.gz`。
- 主页面 UI 区域与 Git 基线逐字比较；此前 6 个非页面跟踪修改文件与备份逐字一致。
- `default/debug assembleApp` 成功；EasyTier 控制器 4/4 确定性用例通过（Node 类型擦除运行，不是设备 Hypium 或真实 VPN 验收）。
- `.88 / 10322965` 已覆盖安装并启动于指定模拟器。源版本仍为 `1.0.3 / 1000005`；未卸载、未清数据、未改包名。
- 宽窗导航/连接表单、约 390vp 四 Tab 与设置页已截图检查。未重新做远控、浅色主题或性能验收。
- 临时截图证据：`/tmp/resk-ui88-restored-wide.jpeg`、`/tmp/resk-ui88-restored-compact.jpeg`、`/tmp/resk-ui88-restored-settings.jpeg`；安装元数据为 `/tmp/resk-ui88-metadata.json`。
- HAP：`/Volumes/RustDeskBuildCache/arkts-workspace/entry/build/default/outputs/default/entry-default-signed.hap`。
- HAP SHA-256：`72a827d95c95fbdd68cd020d62a48902240fd235ea87832475340848828bc99c`。
- 依赖输入 SO（源与镜像）均为 `d0bdbf0fafec43e44af24de48b9ae84eb7140b6754eb0bd6493dc58be5b0485a`；HAP 内打包 SO 为 `abd721655bf8553d923e5fec16ac189c1de8d474ce757b37a0e9a8f59a3b559e`。区分构建输入与打包产物，不混用 hash。
- 本轮未重建或修改 Core/HAR，未 commit/push。只读研究时 Core HEAD 为 `4014999b954a5e4c0e8d4b7633c59551d850d537`，HAR HEAD 为 `64d39a853e1f0e017d81f915834a6d5c6e5d17fd`；两仓另有既存工作树改动，不能当纯 HEAD 源码。

## 11. 官方资料

- [Surface 模式视频编码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/video-encoding-surface)
- [C API 屏幕录制](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avscreencapture-screen-recording-c)
- [AVScreenCapture C API](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-avscreen-capture-h)
- [AVCodec Kit 概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avcodec-kit-intro)
- [编解码格式支持](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/avcodec-support-formats)

这些资料证明公开接口和能力查询方式，**不证明指定模拟器/任意设备实现了全部硬件能力或零隐式复制**；以 API 23 声明和目标设备验证为准。
