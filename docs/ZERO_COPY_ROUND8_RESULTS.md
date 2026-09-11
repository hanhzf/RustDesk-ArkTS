# 第八轮：映射后立即归还与安全能力快照

## 范围与当前结论

本轮延续第七轮的原生引用规则，以同 worker 的 B（Map→Unmap→立即 Release）对照 A（未映射立即 Release），不改前端布局、协议、采集授权、队列大小或 usage，不引入像素复制兜底。**最终 App 已观察到 A Release0 与 B Unmap0/Release0；普通映射 lease 的进程累计归还仍8/8失败。整链零拷贝尚未达标。**

## 实现

- HAR `ohos_capture_lease.rs`：正常采集和 B 共享 `acquire_mapped_lease`。B 取得唯一栈上 lease 后立即 finish，不调用 data、不发布 Core/observer、不新增帧 Arc 分配。正常 Arc Drop 与显式 finish 共用 `Option.take`，确保 Unmap/Release/引用清理只执行一次。Unmap 非零仍尝试归还，但不能判 B 通过。
- 返回 `MappedReturnReport` 保存本次实际 Unmap 码与可空 Release 码，不用全局计数差值推算。`native_calls_succeeded` 仅表示这两项调用成功，既不包含 Unreference 成功，也不证明 driver 释放。新增独立 `releaseMappedImmediateReturn` origin；前置失败归还也计此 origin，须结合实际报告解释，不能以计数单独证明完成了 Map。
- HAR `ohos_capture_input_probe.rs`：共用小状态顺序运行 A→B→原 owned 8 帧，控制帧预算为额外 2，不发布、不计编码目标。NoBuffer 仅重试当前阶段并等待通知；错误结束当前阶段，但允许下一对照继续。所有 FFI 在 State/Slot 锁外，同 owner/generation；控制调用仍未返回时不得提前报告 scopes 完成。取消/超时优先；passed 还必须满足 A Release0、B Unmap0/ReleaseSome0 及原编码条件。
- ArkTS `DecoderCandidateSnapshot.ets`、`NativeBufferDiagnosticService.ets`：仅在有效 debug Want 的进程锁存后、probe 计时前调用已有能力 getter。独立 `RustDeskDecoderCandidate` tag/`decoder_candidate` 前缀；严格投影 H264/H265 各一项三布尔值，推荐软件与硬件存在分别保留。仅状态 `observed` 表示拿到有效元数据，两项证明字段固定 false。缺失、重复、错类型、过大输入或异常统一 unavailable，不等同不支持。不输出名称、指针、原响应或异常；日志/查询失败不影响原 probe。

### 日志接线审查

ArkTS 只序列化 state/stage/terminal/workerMayStillBeRunning/elapsedMs/detail/probeKind 七字段。审查发现仅放在 native root 的 A/B 与 cleanup 元数据会被丢弃，已恢复到 detail；原 root 字段兼容保留，不扩大 ArkTS 任意透传。

`/tmp/resk-r8-control-unit/report_size_bound.py` 从实际 Rust 表达式和实际 ArkTS 七字段投影生成保守尺寸样本：native JSON 5964 bytes（不受日志限额约束），真正日志 2980 bytes≤3800。Python 与 Node 完整解析/重新序列化均通过；这是合成尺寸边界，不是 FFI 行为或性能证据。

## 已验证

- 真实生产纯 helper 及原测试逐段提取，父核对源哈希、字节范围和原文重建后交叉编译。在 `127.0.0.1:5555`：lease **9 passed/0 failed**（原7+新增2），A/B 控制 **2 passed/0 failed**（扩展原两组）。仅验证纯 helper，不是完整 HAR crate/FFI 执行。
- `DecoderCandidateSnapshot.test.ets` 两组实际源码和完整 Service 源码 mock 回归通过。脚本 `/tmp/round8-decoder-candidate-sourcecut.cjs` 直接读取完整生产源码，以 SDK transpileModule+VM 执行，只 mock 外部 HarmonyOS/HAR/timer/Hypium，不重写服务逻辑。覆盖投影隐私、歧义/边界、debug gate、并发一次、顺序、poll、销毁和异常隔离。已登记 List；不能冒充目标 ArkTS runtime 测试。
- HAR 完整 `cargo test --target aarch64-unknown-linux-ohos --release --locked --lib --no-run` 与 release build 成功，三个相关源码构建前后哈希一致。依照 R7 已知边界，不再次把 NAPI HAR 测试作为 bare-shell 程序启动；纯逻辑目标日志均核对实际 passed 行，不只看 HDC exit0。
- 源与 APFS 镜像通过 `refresh-native-har.sh` 刷新并重装依赖；仅同步审核的两个 main 诊断文件和两项测试登记，不改源 AppScope 版本及页面布局。

产物：HAR `5cc93b93e6e401508ed9ee2cbc808d97c966c5064f7232dc9323e5e9ea0d3c85`；原始 SO `6aecf769fdc667333af882c5b04b638082c62788efc34ae8fc5544c6cc30bcae`。

## Core 持有调查：事实与修复限制

`libs/scrap/src/common/ohos/mod.rs` 的全局 latest 在下一次成功 publish 才 replace/drop 旧 lease；HAR 的 Acquire/Map 在 publish 之前。因此无 viewer 也会跨下一 Acquire/Map 保留旧缓冲，静态无后续发布时可保留到 reset。Capturer 又 clone 到 current_lease；编码结束与无新帧的 WouldBlock 都不清它。同显示 viewer 通常共享 video service/encoder，不能把每个 viewer 当作独立源 reader；probe 另有 pending/processing 引用。

这些事实尚不能独立解释 41210000。若需改变交接，必须按实际 reader 明确源读取完成，不拿网络 ACK 当读取 ACK；不可简单 slot.take 抢走多消费者帧，亦不可提前 Release 后靠 Reference 保活继续读 map。还须处理静态首帧、service 重建、generation、取消与不能提前释放仍在编码的输入。**未实施猜测性 Core 补丁。**

既有 `/tmp/ohos-release-review-*` 三份候选源码进一步显示 BUFFER_NOT_INCACHE 来自 BufferQueue 查 sequence 未命中，不是 NativeImage EGL image cache；某些 detach/clear 路径可移除 cache，引用存活不保证 queue membership。Map/Unmap wrapper 仅委托 SurfaceBuffer，未显示直接修改 cache；未调查底层，且这些快照未钉住 commit，不能冒充当前 HarmonyOS API26 实现。即使 B 失败，也同时改变持有时长/调度窗口，不能单凭 A 成功 B 失败断言 Map 根因。

## App 构建、安装与实际对照

`assembleApp product=default buildMode=debug --no-daemon --no-incremental` 成功（8.846s）；不是 release 性能基准。源/APFS 13 个已改或未跟踪 main 文件逐字节一致，三份 HAR 一致，HAP 与原始 SO 的23个 SHF_ALLOC sections 全部一致。两处 oh_modules 的原生 SO 与 `libs/index.d.ts` 也核对一致（声明不在包根目录）。三仓 diff --check 通过，未 commit/push，构建后审核源码哈希未变。

| 产物 | SHA-256 |
|---|---|
| signed HAP | `f7909cf68fa117de6005071dccedf92bdfdf7e212f994321e5dcb64ea134cfb1` |
| HAP 内 strip SO | `a936b81bb82c423c09ec19ab467b3f02feff2cbed33f223c1e12f8bd9b0d4e9f` |

HAP 位于 `/Volumes/RustDeskBuildCache/arkts-workspace/entry/build/default/outputs/default/entry-default-signed.hap`。仅向 `127.0.0.1:5555` 执行 install -r 并收到成功；bm 核对 debug=true、appProvisionType=debug、`1.0.3.88 / 10322965`。沿用镜像已有高版本而非重新套 CI 算法，源仍为 `1.0.3 / 1000005`。未卸载或清数据，未改签名身份/包名/远端。

### 三次尝试分别记录，不能合并作通过

1. 首次出现系统选屏120秒超时：确认授权框后停留过久，之后点击已过期的坐标。UI 错误与 lib.rs 的固定超时文本一致；probe 返回 capture_not_active，A/B 各0次、计数全0。不是 Map 回归，亦不当作有效 A/B 样本。
2. 新进程及时授权并核对“停止服务端”可用后运行。A Release0；B 一次空队列，无实际 Map/Unmap/Release。页签切换未带来足够新缓冲，10秒超时。不能把 UI 操作次数当采集帧数，也不能把 B 的 null 当失败码或成功0。
3. 再次正常停服后新进程及时授权、确认就绪。用已核对的标题栏横向 swipe（1000px/s，位置往返、不变尺寸）供帧。最终三条完整 JSON：0ms check_capture_active；313ms A已返回、B待新帧；10000ms deadline_exceeded/cleanup_complete。

最终实际控制报告：

| 项目 | 返回/计数 | 范围 |
|---|---|---|
| A raw | attempts=1、Release=0、resultAvailable=true | 额外控制帧，不发布、不计编码 |
| B mapped-immediate | attempts=2（一次空队列＋一次实际报告），Unmap=0、Release=0 | 额外控制帧，不读像素、不发布 |
| B 独立 release origin | calls=1、failures=0 | 结合实际报告可知本次完成映射与归还 |
| 普通 mapped lease Drop | calls=8、failures=8、last/error=41210000 | **进程累计**，起始快照已有7次，不是8次全部发生在 probe 内 |
| Reference / Unmap | 11/0失败；9/0失败 | 进程累计 |
| Unreference | 18/0失败＝initial8＋external10 | 进程累计；不能由此认定 driver 完全清理 |
| 编码/包/解码 | 0/0/0，目标8 | 本轮未取得编码样本，不是8帧通过 |

终态 RustScopesDropped=true、workerMayStillBeRunning=false；driverCleanupProven/zeroCopyProven 均 false。独立采集计数快照 signals 8→11、published 8→9；这些计数在查询时读取，而 elapsedMs 可已冻结，**不能把差值等同严格10秒内的诊断采样数量或用于计算 FPS**。最终三条日志 JSON 为2053/2062/2087 bytes，均完整解析。

这证明至少该次 Map/Unmap＋立即归还能成功，不能再泛化为“映射必然导致失败”。普通跨帧路径仍失败；持有时长、下一 Acquire、异步 producer/queue detach/clear 仍需区分，未认定唯一根因。**没有强行清 latest/提前 Release，也没有修改队列大小、usage、10秒预算或静默重试失败的 Release。**

### 真实能力快照与收尾

最终进程独立 tag 只有一条安全快照：state=observed，H264 recommendedAvailable=true / recommendedIsHardware=false / hardwareAvailable=false；H265 三项false。仅表示当前设备查询到的候选元数据，不能据此推导软件 Surface 可用/不可用，不能把推荐软件冒称硬件。Surface binding 与 zeroCopy 证明仍false。

最终正常停服，UI核对“启动服务端”enabled=true；窗口恢复原 `[515,281][2605,1675]`，App仍存活、进程限定的fatal日志0行。全程保留屏幕隐私保护勾选；本轮15份明确创建的临时 UI 层级与两个设备纯测试程序已删除，保留的诊断日志不含像素/帧包/私密UI内容。清理时递归 glob 遇到无关 tmp-mount 权限错误，未升级、未触碰这些目录，改为只清理本会话已知文件名。

主要日志：`/tmp/resk-zero-copy-round8-final-capture.log`、`/tmp/resk-zero-copy-round8-final-decoder-candidates.log`；两次未满足采样前提的日志分别在 `round8-capture.log`、`round8-active-capture.log`，不能拿它们的缺测覆盖最终真实 B 结果。

## 下一实施候选：软件必要色转直接写最终窗口

不再预设零拷贝必须有 GLES3.1/SSBO/DMA-BUF import。已确认的计划第2节与第5B节允许必要色转直接产出最终消费者使用的新表示；Core capability_gate 同样明确此计算本身不违规，但 ownership 未验证仍 unverified。基于这个原规则，显式在计划§5D增列**独立候选**，不是把旧 external allocator 路线宣称通过，也不是授予兼容模式 copy 例外。

当前实际软件链：VideoHandler→codec VPX/AV1 last_frame.to(rgb)→GoogleImage::to 分配/resize RGB Vec→on_rgba→Flutter display_rgbas（Vec swap不是深拷贝）→session_take_rgba_frame **data.clone**→HAR Uint8Array→ArkTS createPixelMap/Image。HAR 没有生产软件 NativeWindow writer；shared_frame_display 仍是未接线原型。不能按想象中的呈现器接接口。

有界下一步：

1. Core GoogleImage 增受检 `to_into(&mut [u8], stride, format)`，复用内部 libyuv dst指针/stride能力，不伪造 Vec 所有权；验证宽高/溢出/容量/实际stride、字节序/色彩及返回码。
2. 在 decoder last_frame 仍有效、下一 decode/flush 前同步调用目标闭包。Core提供抽象访问接口、HAR实现窗口 writer，保持依赖方向；现有 direct target 只有surface ID/尺寸，须补 owner/generation，不能当作已有生命周期契约。
3. HAR新建 Request→fence→Map→独占可写slice闭包→Unmap/Flush；错误/解绑走Abort与单次清理，slice不逃逸/跨await，registry锁不跨等待/FFI。没有额外RGB临时帧或逐行同格式复制。
4. 返回“已呈现＋实际尺寸”而不是假装旧RGB成功；跳过RGBA clone/PixelMap，保留成功计数、录像尺寸和原协议ACK语义，以低频首帧/状态连接已有XComponent。呈现背压不跳过参考链解码。

需继续审计解码内部搬运、Map/Flush/合成隐式复制并做实际窗口验证；未经验证仍不达标，不启用静默 fallback。编码侧跨帧原生源寿命缺口仍独立保留，应围绕明确源读取完成及直接最终输入所有权解决，不用网络ACK代替读取完成。
