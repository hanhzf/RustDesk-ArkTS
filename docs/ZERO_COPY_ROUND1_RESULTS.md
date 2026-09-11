# 零拷贝实施：第一轮继续验证

本轮承接 `ZERO_COPY_IMPLEMENTATION_STATUS.md` 的首批安装基线。**尚未完成整链零拷贝，兼容模式没有获得复制例外。** 源版本仍为 `1.0.3 / 1000005`；只允许模拟器 `127.0.0.1:5555`。

## 本轮代码

### 1. 可脱离 codec 描述符的共享帧

Core `external_frame_buffer.rs`、`vpxcodec.rs`、`aom.rs` 增加 `DecodedFrame` 与 `DecodedFrameMetadata`。

- 在 `DecodeFrames::next`、codec 描述符仍有效时缓存尺寸、crop、Y/U/V offset/stride、位深与带 codec 标签的色彩信息。
- `Image::into_shared_frame` 只移动缓存元数据和 `FrameRenderLease`，不再解引用已失效的 codec 描述符，不复制像素。
- 首版仅接受 8-bit I420；负 stride、非法 plane、越界布局和缺少租约明确报错。奇数尺寸使用向上取整的色度宽高；未知色彩信息不伪造默认矩阵。
- 去掉对 decoder 借出图像描述符的 `*_img_free`。本地 vendor 源码证明它们属于 codec context；旧 raw `inner()`/GoogleImage API 仍有 codec 生命周期约束，本轮不把整个旧 API 宣称为 lifetime-safe。
- `FrameRenderLease` 的 Send/Sync 是 backing 生命周期与只读/不复用契约，**不自动维护 CPU/GPU cache、不自动等待渲染 fence**。

### 2. ACK 存储有界化与发送竞态

Core `video_frame_controller.rs` 用 keyed pending ACK + Condvar 替代无界 mpsc：每个活跃目标最多一项待处理 ACK，重复通知合并，不按通知次数增长。register/remove 隔离 run generation，关闭唤醒 waiter。

父审查发现发送早于 `set_send`：`Subscriber::send` 入队后，连接可能立即通知。仅在 `set_send` 登记路由会丢合法 early ACK。修复在 `service.rs::send_video_frame_shared`：

1. 同一 subscribers 写锁内收集真实 `s.id()`；
2. VideoFrame 在任何入队之前调用 `begin_send`，登记准确目标并剪枝；
3. 释放 ACK 锁后才发送；后置 `set_send` 保留 early ACK。

未知 ID 不进入存储；不伪造 ACK。仍保留原版 readiness/timestamp 语义与 all-target 等待预算，**没有新增协议级 frame-sequence ACK 保证**。`tx_video` 网络队列仍无界，慢连接隔离/背压未完成。

### 3. OHOS VP9 显式关闭前视延迟

在 OHOS 编码配置显式设置 `g_lag_in_frames = 0`。本地 libvpx v1.16 默认 VP9 lag 为 25，REALTIME 不自动清零；lookahead 槽数从默认公式的 26 降至 2（含前源历史）。这是配置/源码事实，不是实测延迟或帧率提升数字。

**lag=0 仍会执行 `vp9_copy_and_extend_frame`**，不能列为零拷贝完成。若消除该纯输入搬运，需要 vendor acquire/commit/release 输入缓冲接口，由转换器直接写最终 encoder planes，并保留上一源的真实寿命；不能仅换指针，也不能在 encode 返回时直接归还上一源。

### 4. 能力诊断不是已启用的协商门控

新增 Core `ohos/capability_gate.rs`，由 `platform::ohos` 向 HAR 导出。现有 `runtimeGetDecoderCapabilities` JSON 增加 `zeroCopy`：

- `kind=implementation_audit_snapshot`，`runtimeProbe=false`；
- 区分 host/viewer、compatibility/performance、软件路径/硬件候选；两个 profile 均无复制豁免；
- 明确 known_copy、unverified、unsupported、仅应用交接 identity 的证据范围；
- `enforcedInNegotiation=false`、`allPathsVerified=false`；当前没有完整路径可宣称符合要求。

必要色彩转换产生新表示，不能仅因为有输出写入就算纯搬运；其最终输出所有权尚未审计，记 unverified。已确认的 VP9 lookahead 输入复制、RGBA/PixelMap 交接记 known_copy。

## 原生共享图集探针

HAR 新增 `tools/zero_copy_probe/`，直接用 API 23 SDK 头文件构建 AArch64 独立程序。设计路径是 NativeBuffer RGBA 字节图集 → EGLImage → GLES3 texelFetch，**不调用 CPU 上传**；`glReadPixels` 仅属于测试结果核对，绝非生产显示旁路。

当前独立 shell 进程请求 128×16、RGBA8888=12、usage=515 时，`OH_NativeBuffer_Alloc` 长时间不返回。原始运行由精确 PID SIGTERM 回收；分配没有返回错误码，不能称“权限拒绝”。后续 Map、dma-buf ioctl、EGL、shader 和比较均未运行。

随后实现 `--persistent-map` 的双图案、长期映射、CPU/GPU 串行 epochs 探针，并由设备 `timeout` 限制 TERM 30 秒、再过 5 秒 KILL。该次受限运行仍未观察到分配返回；结束后 `pidof raw_byte_atlas_probe` 为空。HDC 传输 exit 0 没有暴露远端退出码，不能把它当探针成功，也不猜具体 timeout 返回码。两次运行均未到达 GPU 或 ioctl。

该证据只属于**独立 shell 进程上下文**；不能推断 App 进程一定失败，也不能断言设备不支持 RGBA 导入。原始记录为 `R_RustDesk-Har/tools/zero_copy_probe/result.json`，长期映射受限重跑记录为 `persistent-result.json`。输出目录 `out/` 已忽略，探针不链接到生产 HAR。

## 同步合同与下一落点

API23 公开 NativeBuffer 没有独立 CPU begin/end/flush API。Unmap 会撤销 CPU 访问，不保证重 Map 地址相同；codec 仍保留 reference plane 指针时不能拿 Unmap 当 flush。

条件式候选：长期 Map，同一 backing fd 支持 `DMA_BUF_IOCTL_SYNC` START/END，codec worker 的 CPU epoch 与 renderer 完成 fence 严格排序。ioctl 同步不等于互斥，fence 不等于 CPU cache flush，exporter 也可能有内部 staging，均需设备验证。当前探针未到达这些 API。

下一步优先核验 App 进程上下文中的分配/同步，而不是根据 shell 分配不返回就强推或否定显示方案；未验证路径不得接成默认复制降级。

## 验证记录

- 父会话独立 `rustc --test external_frame_buffer.rs`：9 项通过（包含布局、奇数色度及跨线程生命周期模型）。
- 父会话独立 `rustc --test capability_gate.rs`：3 项通过。
- 父会话独立 `rustc --test video_frame_controller.rs`：9 项通过（含 early ACK、重复通知有界、关闭换代）；另有子 agent 实际发送方法抽取的确定性验证。
- codec 描述符销毁测试使用实际 wrapper 方法 + mock descriptor，不等于真实 libvpx/libaom ABI/驱动运行证明。
- 最终 Core/HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked` 通过，2m45s；日志 `/tmp/resk-zero-copy-round1-native.log`。本轮仍有 baseline warnings，不称零警告构建。
- `ohrs artifact` 成功，源码仓和镜像分别用刷新脚本重装 HAR/oh_modules；本轮 HAR SHA-256 为 `6d0c127fcb5641470623671cbd2e2cac79e3db0878cfd17f2b60db24b1da298a`，原始 SO 为 `16f5eb8430194fbae772e68e9471aa47364b496484a84aebe208c97cb4d772e5`。
- 镜像 `assembleApp -p product=default -p buildMode=debug --no-daemon --no-incremental` 成功，10.256s；日志 `/tmp/resk-zero-copy-round1-arkts.log`。临时签名目录在退出 trap 清理，检查剩余数为 0。
- signed HAP SHA-256：`8185d85c4348b147f37005ed6c228a46c8d1dacc9c01d81691c05ef93eb8f2f3`。
- HAP 内 SO SHA-256：`b781aac476354a45e623960f64cf4ec7948ca028e5e9cf22cdecad8d6a402fe7`。原始 HAR 与打包 SO 的 23 个 SHF_ALLOC ELF section 名称、属性、地址、尺寸与内容完全一致；整文件哈希差异来自 native stripping，不是以旧库顶替。
- 仅向 `127.0.0.1:5555` 执行 `install -r`，返回 `install bundle successfully`；未卸载或清应用数据。`aa start` 成功，启动后 PID `1043`；安装信息为 `1.0.3.88 / 10322965`、debug Profile。源码 `AppScope/app.json5` 仍为 `1.0.3 / 1000005`。
- UI hierarchy 可解析，检出 RustDesk、服务端、设置主页面标签；这是安装/启动冒烟检查，不是远控、采集、输入或共享显示验收。日志收集流在获取窗口后主动停止，未据此宣称全部日志无错误。
