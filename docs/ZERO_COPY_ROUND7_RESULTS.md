# 第七轮：原生引用契约与未映射归还对照

本轮不重复 strict 暂停设计，不改变前端布局、协议或采集授权。聚焦第六轮已成功映射 lease 的 Release 失败，并安全核对独立解码 Surface 候选。**实现、审查、构建及目标对照完成；raw立即归还成功，但正常mapped归还仍失败，8帧和整链零拷贝未通过。**

## 审查纠正：外部原生引用不能被 Rust Arc 替代

初次只读审查“未发现 caller 契约缺口”过强，已纠正：实际 SDK `native_image.h:277–280` 和[官方 Acquire 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-image-h#oh_nativeimage_acquirenativewindowbuffer)明确要求使用者额外 Reference/Unreference。内部实现 Acquire 的初始 Reference 不豁免公共使用者契约，Rust `Arc<CaptureSurfaceOwner>` 只保活 owner。

HAR `ohos_capture_lease.rs` 补齐该独立引用账本：只有实际 Reference 成功才产生 external 释放义务；失败不重试。mapped/rejected/raw 共用清理，两个 Unreference 对应两个持有引用，不是重试。

| 外部 Reference | 实际 Release | caller 的 Unreference 义务 |
|---|---|---|
| 成功 | 成功，系统消耗 initial | external 一次 |
| 成功 | 失败，系统未消耗 initial | initial 一次、external 一次 |
| 失败 | 成功 | 无额外义务 |
| 失败 | 失败 | initial 一次 |

image 不存在时不得合成 Release 码，按已有引用清理并在未提交给系统时关闭 fence。正常 Release 的 fence 规则不改。Reference/Release 各仅首次实际失败记固定日志，后续累计计数；不输出地址、不增加 retry。新增 reference/raw-release/initial-unref/external-unref 计数，原 aggregate 保留。

这证明公共契约需要修正，**尚不证明 under-reference 是41210000的根因**。

## raw A 对照：保留同一生产端、同一 worker

既有 capture_input 诊断先请求一个 raw control frame：在原 capture worker、同一 owner 成功 Acquire 并取得规定引用后，立即把原 window_buffer 和原 acquire fence 归还。该帧不 GetHandle/From/Map、不创建帧租约、不发布给 Core、不编码，额外消耗1帧，明确不计入8帧目标。此诊断不再是完全无数据流影响的被动观察；常规未触发诊断的路径不消费该对照帧。

raw 与后续正常映射路径使用同一新版引用契约，不同时调整 usage/queueSize。只记录实际 Release 码；无 buffer、提前失败和未观测到返回不能伪造0。claim/state 锁不跨 FFI，UI只arm/cancel。逻辑 deadline/cancel 与 raw 原生调用仍在运行必须分离，不能由编码 worker 单独退出就宣告全部 scopes 完成。

判别边界：raw 也失败，可排除该帧的 From/Map/lease/codec 是必要前提，但不能直接定罪驱动；raw成功、mapped失败也可能是持有时长/队列时序，而非必然Map错误。参考 OpenHarmony master 的 NOT_IN_CACHE 来自 BufferQueue 按 sequence 查缓存，不是纹理/EGL cache；master不能代替当前设备实现。

曾评估独立 C++ ConsumerSurface/NativeWindow producer。Create可以不依赖EGL，但 Flush契约要求生产好内容，未找到允许未初始化 allocation 空提交的明确保证；Region空列表并非空像素区。因此本轮不执行空Flush，不制造假GPU写入或把其当零拷贝证明。

## 独立显示候选

Core 已接 H264/HEVC decoder→Surface 的候选路线（SetSurface→RenderOutputBuffer，`pixelbuffer=false`不回调RGBA），它不依赖此前被GLES3.1/SSBO限制的实验路线。无Surface时仍存在复制输出分支，当前codec能力公布不等于strict显示门控。

本轮复用已有 `runtimeGetDecoderCapabilities`，把内部 capability 地址日志改为安全结构化候选信息，并明确 `surfaceBindingVerified=false`、`zeroCopyProven=false`。推荐实现类别与仅存在硬件能力分开；不创建解码器、不绑定Surface、不执行解码、不改协商策略。

## 测试与目标验证

### 已完成的构建和纯逻辑验证

- HAR 工作区 `cargo test --target aarch64-unknown-linux-ohos --release --locked --lib --no-run`：1m11s成功，3个修改源码构建前后SHA一致。
- 实际测试程序 `rustdesk_native_har-511708900a4b30f8` SHA `c7ab6186a812d52879c56df72d33b1c0abf47ccd89a0c2724c77a29816bed8de`。设备bare-shell启动失败，`libace_napi.z.so` 的Panda/JS引擎符号不能解析，测试没有执行。HDC本身返回0不是被启动程序成功；没有预加载猜测、移除真实NAPI依赖或伪造stub。测试程序已从设备移除。
- 另交叉编译真实生产纯helper及原测试，父按当前源码逐段/逐函数核验（raw提取包装仅多一个末尾空行）。指定OHOS设备执行：lease **7 passed / 0 failed**；raw控制 **2 passed / 0 failed**。本轮新增分别2组，其余沿用。不是完整HAR crate执行，不覆盖原生FFI、真实线程竞争或驱动资源归还。
- lease提取及逐段来源清单：`/tmp/resk-r7-lease-unit/{lease_unit.rs,manifest.json,extract.py}`；raw提取：`/tmp/r7-raw-final-status.WvnFEi/helpers.rs`。目标日志：`/tmp/resk-zero-copy-round7-lease-target.log`、`...-raw-target.log`；目标上的两份纯逻辑程序已移除。
- HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked`：2m22s成功，3个修改源码前后SHA一致。刷新源和APFS镜像HAR并重装依赖；12个修改/未跟踪main源码与镜像一致。
- `hvigorw tasks --mode project --no-daemon`确认assembleApp，未显示项目级test任务；default/debug `assembleApp --no-daemon --no-incremental`：8.275s成功，保留既有warnings。临时签名配置自动清理，未改源版本。

| 产物 | SHA-256 |
|---|---|
| package.har（源、镜像一致） | `dea9f4a91de57944cb095635eb5cc19b8a9999e33b9ea004fa8eef577f4f7e47` |
| 原始SO | `40bf42788417150a0e75b97fa5a6ed737a77ecf6d9cd315bf369f39b83ed97da` |
| signed HAP | `79b253f163add1893d382772965a0b4db8692894abd4584b6c908a84891b5a03` |
| HAP stripped SO | `c77c0ce5c0fd62d765c128637c4ca2efad3299fa84d8ee8e2a6ec6808bdeb3a7` |

原始和stripped SO的23个可加载section属性与内容一致。构建日志均为 `/tmp/resk-zero-copy-round7-*.log`。只在 `127.0.0.1:5555` 操作；安装仍为保数据 default/debug 本轮签名包。不得以本轮对照或能力查询冒充完整零搬运、像素正确性、FPS或远端会话验证。

### App目标结果

仅向 `127.0.0.1:5555` `install -r` 成功；查询 `1.0.3.88 / 10322965`、debug=true、debug Profile。源仍 `1.0.3 / 1000005`，没有清数据、卸载或改远端。进程PID17288，正常点击启动服务端和系统允许，屏幕隐私保护始终勾选。

有效日志 `/tmp/resk-zero-copy-round7-capture.log` 的5条记录全部通过完整JSON解析（read工具的单行显示截断不是文件截断）：

| 观察点 | 真实结果 |
|---|---|
| 开始 | callbacks/published=7/7，Reference7/0失败，mapped Release6/6失败 |
| 300ms | rawAttempts=1、实际rawReleaseCode=0，rawPending/inFlight=false；callbacks/published=8/7，明确多消费的1帧未发布 |
| 3322ms | 下一mapped输入1920×1280 RGBA/stride7680，callbacks/published=9/8 |
| 最终10017ms | 1编码/1packet/1解码，8目标未达到；deadline_exceeded，worker=false，RustScopesDropped=true，driverCleanupProven=false |

最终全局累计：Reference **9次/0失败**；Release **8次/7失败**，其中 raw **1次/0失败**、mapped **7次/7失败**、rejected=0；mapped最后码41210000。Unmap7/0失败；Unreference合计 **15次/0失败**，initial7、external8；orphan=0。raw成功由系统消耗initial，仅需caller external1；mapped失败各需caller initial+external，两者计数与四格账本一致。此快照取于停止采集之前，不能把尚未归还的最新映射缓冲或累计差额径直判定为泄漏；也未证明stop之后驱动全部释放。

**关键收敛：在同一新版引用契约、同一进程、同一capture worker，raw立即归还能成功，因此不支持“原生Acquire→Release普遍不可用”。外部Reference全部成功仍未消除mapped失败；下一步应区分From/Map/Unmap本身与租约持有时长/跨帧队列时序。单样本不证明raw路径普遍正常，也不单独证明Map有错。**

为供帧，执行一次短距标题栏拖动及反向拖动；窗口2090×1394尺寸不变，最终回到接近原位（左上由515,281到506,274）。只有第一次拖动位于诊断窗口内，反向还原在诊断结束后。回调增量仅2，分别对应raw控制和1个mapped输入；没有得到受控连续帧率，不把拖动命令或速度参数当FPS证据。正常点击停止后，最终hierarchy明确显示“启动服务端”。本轮未截图；临时hierarchy在核对后清理。

显示候选：指定PID+固定候选前缀的日志查询（有/无tag两种范围）均未取得记录，因此**目标H264/HEVC能力仍未观测到**；空日志既不代表支持，也不代表不支持。本轮只是把已存在getter的源码日志改成安全候选投影，不宣称完成运行时能力、解码器创建、Surface绑定或显示验收。

## 下一步边界

1. 优先同worker、同引用契约的 **Map→Unmap→立即归还** 小对照，先区分映射操作和跨帧持有，再决定是否调整帧交接；不能看到raw成功就随意提前Release仍在被读的帧。
2. 安全取得已有解码能力getter的应用内结果，再评估独立H26x Surface候选。GLES3.0/SSBO3.1与DMA-BUF EACCES缺口不因此消失。
3. 只读核对了可选的直接encoder Surface路线：SDK GetSurface在Configure后/Prepare前、App负责窗口生命周期；现Core `OhosVideoEncoder`仍为CPU YUV输入，缺Surface owner/独立输出drain与采集接线，已有H26x封包可复用。这不是本轮实现，更不能在未确认硬件能力时把H264硬编码设为必需，或重建先前被移除的未验收专用链。
4. 旧AcquireVideoBuffer显式租约、新DataCallback内同步借用虽有API契约候选，但旧路线历史上曾无视频通知，不能凭新一轮纸面核对冒充可用。DataCallback返回即失效，NativeBuffer引用保活不延长队列租约；禁止裸指针跨回调保留。没有实施替代采集或复制兜底。

长期目标仍active。本轮结果不是驱动零搬运、像素正确性、持续帧、完整strict远端会话或兼容性验收。
