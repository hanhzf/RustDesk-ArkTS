# 零拷贝实施状态

2026-09-08 用户已授权按 `PERFORMANCE_FIRST_ZERO_COPY_PLAN.md` 实施。**本文件是进行中记录，不是零拷贝验收通过声明。**

**当前以最高轮次结果为准；下方首批与逐轮记录保留历史含义，不以旧包/旧缺口描述覆盖新证据。**

> 最新继续实施记录见 `ZERO_COPY_ROUND1_RESULTS.md`：共享帧快照、有界 ACK/early ACK 修复、OHOS lag=0 和能力诊断已构建安装；独立 NativeBuffer 探针在分配阶段未观察到返回，整链仍未达标。以下保留首批历史基线与当时的测试/包哈希，不把旧包当最新产物。

> 环境纠正：第二轮核验发现当前实际 SDK/模拟器为 API26，源码兼容目标仍为 API23；不能把目标号等同实测环境。详见 `ZERO_COPY_ROUND2_RESULTS.md`，前文 API23 表述不应理解为 API23 实际设备验收。

> 第二轮已构建安装：App 内 Alloc/Map 成功检查通过，首个 DMA-BUF START|RW 同步返回 EACCES(13)，线程结束；未运行图案写入或 GPU 阶段。最新包哈希与下一候选边界见第二轮记录，整链仍未达标。

> 第三轮最新记录 `ZERO_COPY_ROUND3_RESULTS.md`：用户允许编码端改造，隔离 VP9 最终输入槽原型通过 ASAN/UBSAN 与真实输出对照，已定位 lookahead copy 64→0；Core直写基础已交叉编译但未接线生产。App GLES探针实际context=3.0，在3.1门槛提前拒绝，未执行持久映射；新包已覆盖安装，整链仍未达标。

> 第四轮最新记录 `ZERO_COPY_ROUND4_RESULTS.md`：版本化OHOS补丁库、Core私有slot与默认关闭的strict发送分支已编译。App经真实owned入口编码/普通VP9解码64帧通过，两个短输入取消后均恢复；未开启真实strict会话，不把合成验证、17ms耗时或新编码入口当成全链零拷贝/性能证明。

> 第五轮最新记录 `ZERO_COPY_ROUND5_RESULTS.md`：已授权真实采集观察和清理健康计数已构建安装。未启动采集时拒绝通过；两次真实1920×1280 RGBA诊断分别完成2/1帧编解码后超时，8帧未通过，worker均退出。全局Release均失败、最后码41210000，来源未归因；服务端已正常停止。另确认strict永久错误仍被外层重试，暂停/恢复修复是下一优先级，整链仍未达标。

> 第六轮最新记录 `ZERO_COPY_ROUND6_RESULTS.md`：strict类型化永久失败暂停/事件恢复、非致命消息保留连接已落地；两个真实Core库测试在指定OHOS模拟器通过，Core/HAR/App构建和保数据安装通过。packed采集移除MapPlanes失败再Map的重试盲点；真实2帧后仍超时，Release7/7失败已定位均为映射lease正常Drop，拒绝/缺失owner路径0，回调/发布计数6→8。服务端正常停止；驱动归还和显示缺口未解决，整链不达标。

> 第七轮最新记录 `ZERO_COPY_ROUND7_RESULTS.md`：补齐SDK明确要求的外部Reference/四格清理账本；同worker raw未映射立即归还真实返回0，正常mapped Release仍7/7失败，不能再泛化为Acquire→Release普遍不可用。Reference9/0失败、Unref initial7+external8全成功；额外raw1帧不发布，随后仅1帧编解码并超时，worker已退出、服务端停止。完整HAR测试编译过但bare-shell缺NAPI运行环境；逐段核对的生产纯helper目标测试7+2通过。最终HAR/App构建和保数据安装通过，显示候选日志仍无目标快照，整链未达标。

> 第八轮最新记录 `ZERO_COPY_ROUND8_RESULTS.md`：同worker B与生产共用Map/清理代码，目标实际A Release0、B Unmap0/Release0；普通mapped Drop进程累计8/8失败（起始已有7），未认定根因。两控制之外0帧编解码并超时，8帧未通过；worker退出、服务正常停止、窗口复原。安全应用快照已取得：H264推荐软件、无硬件候选，H265三bool均false，仅元数据、不证明Surface。纯helper目标9+2通过，完整HAR测试编译与HAR/App构建、刷新及保数据覆盖通过。§5D显式增列必要色转直写最终NativeWindow的独立候选，未接线/验收，整链仍未达标。

## 基线与边界

> **第九轮最新记录 `ZERO_COPY_ROUND9_RESULTS.md`**：三仓独立建立 `perf/zero-copy-high-fps`，原分支HEAD/远端不变，保留未提交改动。增强VPX/AV1同步借用YUV、必要色转直写最终NativeWindow，页面移除RGBA/PixelMap视频中转，仅≤10Hz元数据；应用GLES实现不编译，ELF无直接EGL/GLES依赖/导入，安装包旧诊断入口实际返回disabled。修复早到帧跳过采集FPS设置，去软件60截断，但官方平台目前仍最多60FPS。目标真实libyuv2项+能力门控3项通过，Core/HAR与App构建、HAR刷新/23节一致性、指定模拟器保数据覆盖和就绪启动通过。真实远程窗口/换代与codec切换压力、持续FPS、驱动/codec隐式搬运、普通mapped capture Release41210000及30/120反馈/pacer缺口未验收；整链仍不达标。详见本轮产物hash与边界，不以历史PixelMap路线描述替代新实现。

- 三仓原工作树补丁、status、HEAD 已保存在 `/tmp/resk-zero-copy-baseline.u8yi5u/`。原有音频/软件编码调整和格式变化不是本批删除，不得据 HEAD diff 擅自恢复。
- ArkTS 保持 `9b7bf4a` 原 UI，只改非布局接口。本批已打包 `.88`；设备结果见下方构建记录。
- 只允许 `127.0.0.1:5555`，不清数据；测试版本只改 `/Volumes/RustDeskBuildCache/arkts-workspace/`。

## 第一批实际改动（历史基线）

| 项目 | 当前证据 | 尚需完成 |
|---|---|---|
| Core 捕获帧租约 | `scrap/common/ohos/host_frame.rs`、`ohos/mod.rs` 与 `platform/ohos.rs` 增加 layout/Arc buffer API，帧交接借用原指针，锁外 Drop；旧 Capturer 跨代永久返回 Interrupted，非法布局先拦截再配置屏幕 | 设备实际采集、重启与持续压力验证 |
| HAR 采集交接 | `src/ohos_capture_lease.rs` 接 ConsumerSurface，锁保护 image API，最后租约释放才 unmap/release；真实 BufferHandle.size 校验范围，bounded fence poll，publication 锁隔离已停止 worker | 驱动同步/停止超时实测；不等于编码器内部零拷贝 |
| 鼠标数值桥 | Core `flutter_ffi.rs::session_send_mouse_event`，HAR NAPI、`types/index.d.ts`、`package/index.ets` 四层导出，ArkTS `RustDeskMouseTransport.ets`；保留 closed/view-only 和相对鼠标 marker 语义；HAR 已刷新且 ArkTS 编译通过 | 真实远程会话输入验证 |
| 外部分配解码 | `external_frame_buffer.rs`、VP9/AV1 `new_with_allocator`；codec 与多份 render lease 双计数、有界池、注册失败清理，VP8 明确拒绝 external allocator | 尚未在生产 decoder 构造处启用；NativeBuffer allocator、稳定图像元数据快照、GPU import/fence 与显示接线均未完成 |
| 视频调度 | `video_frame_controller.rs` 以 std mpsc recv_timeout 替代每次等待创建 Tokio runtime；run 级 notifier 重建配对、ACK 集合过滤、drain 批次/耗时上限 | ACK 通道仍为无界通道；有界网络队列与慢连接隔离尚未实施，不能宣称已解决 |

## 已运行的局部测试

- ArkTS 鼠标桥 2 个边界用例通过 Node 26 类型擦除运行，源码为仓库实际测试；不是 ArkTS 编译或设备 Hypium。
- Core 数值鼠标 mask/marker 2 个真实源码提取测试经 Rust 1.95 编译通过；不是完整 Core 构建或远程输入验收。
- Core 租约 agent 的真实源码提取测试 6 项通过：含指针身份、Drop、布局、reset 有/无新帧、旧代永久 Interrupted。不是驱动测试。
- 父会话独立运行 `rustc --test external_frame_buffer.rs`：7 项通过（包含多 lease、注册上下文寿命、错误 allocator、按实际分配大小拒绝超限）。
- 父会话独立运行 `rustc --test video_frame_controller.rs`：6 项通过（包含重建 ACK、无关 ACK 过滤与排空预算）。
- HAR publication/锁序由子 agent 以 `/tmp/test_capture_lease_isolation.rs`、`/tmp/test_lock_order.rs` 模拟测试；这是模型测试，不是直接 NativeBuffer/驱动执行证明。
- 完成一次 API 23 `aarch64-unknown-linux-ohos --release --locked` Core+HAR 全链编译，耗时 2m44s；随后对外部分配器完整零化和实际容量上限修正，再进行最终构建/打包。构建有未使用代码等 warnings，不以零 warnings 冒称结果。

## 本批构建与包对应关系

- 最终 Core/HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked` 通过，2m30s；日志 `/tmp/resk-zero-copy-native-final-build.log`。
- `ohrs artifact` 打包通过；源码仓和 APFS 镜像均运行 `scripts/refresh-native-har.sh`，重建 oh_modules，核验入口、声明与 `.so`。
- 先运行 `hvigorw tasks --mode project` 确认 assembleApp；最终 `assembleApp -p product=default -p buildMode=debug --no-daemon --no-incremental` 通过，13.25s；日志 `/tmp/resk-zero-copy-arkts-build.log`。有资源重复与 API deprecated 等 warnings。
- 本轮临时 `/tmp/resk-zero-copy-signing.*` 使用 EXIT trap 清理，完成后剩余目录数为 0；源码版本仍为 `1.0.3 / 1000005`。
- HAP：`/Volumes/RustDeskBuildCache/arkts-workspace/entry/build/default/outputs/default/entry-default-signed.hap`，镜像版本 `1.0.3.88 / 10322965`，default debug 签名。

| 产物 | SHA-256 |
|---|---|
| `R_RustDesk-Har/package.har` / App `rustdesk-ohrs.har` | `eaedaf1c0b2af3b0a9e66a19e781b293371a461524503777a03123b396a52d2c` |
| HAR 内原生 `.so` | `452a7ce74d6556d22e3032aea565488ef536300bb92b819f09f5df3c3e21ebe9` |
| HAP 内 strip 后 `.so` | `d4536be4ffe3ed9cc8b130068f33b6750580fb38f31c507e9edb2437e4eb6ee7` |
| 本轮 signed HAP | `26e3d86b311ddf8ef7b5fa42d94526320aae713e94c623be0fdf9f60d2b3c643` |

HAP 与 HAR 的原生库整文件 hash 因 Hvigor StripNativeLibs 不同。已逐个比较 ELF 的 23 个 SHF_ALLOC 节（含 `.text/.rodata/.data`、动态链接数据与重定位），地址、长度、内容一致，排除旧库混入；该 ELF 没有 GNU build-id，不以不存在的标记作为验证依据。

### 模拟器结果与验收边界

- 对 `127.0.0.1:5555` 执行本轮 signed HAP 的 `hdc install -r`，返回 `install bundle successfully`。未卸载、未清数据，未连接其他设备。
- `aa start -b top.frankhan.resk -m entry -a EntryAbility` 返回成功；进程 PID 2619。
- 安装后 `bm dump` 确认 `1.0.3.88 / 10322965`、`debug=true`、`appProvisionType=debug`。
- UI dump 确认活动窗口是 `top.frankhan.resk / pages/RustDeskIndex`，主页面连接提示与“就绪”可见；不是仅凭 aa 命令返回判定启动成功。
- 本次进程日志有 `Main page loaded`。系统隐私状态仍为 `accepted=false`，重力传感器保持 disabled，没有擅自放开隐私门控。状态栏保活不可用而回落数据传输任务的 warning 仍存在，未在本批处理。
- 本次没有完成真实远程会话、屏幕采集授权/首帧、停止重启压力、codec/GPU 内部搬运追踪和性能数字验收；以上均不能从启动成功推导。设备 Hypium 未执行，Node/rustc 局部测试不可替代。
- 三仓 `git diff --check` 通过；没有 commit/push，没有改源版本或远端。

## 不能省略的零拷贝缺口

1. 采集交接没有像素复制，不代表软件编码器内部没有复制。已定位本地 libvpx v1.16.0 `vp9/encoder/vp9_lookahead.c:154` 的 `vp9_copy_and_extend_frame`；需要审计当前编码调用链并处理或明确能力不达标。
2. 现有 VP8/VP9/AV1 RGBA/PixelMap 显示路径不满足零拷贝；external allocator 挂钩本身也不是 GPU 共享显示的证明。
3. `OH_NativeImage` 的 acquire/release/destroy 为非线程安全 API，跨线程释放必须串行保护同一个 image；Core 的 Arc 不能替代此锁。
4. API 23 MapWaitFence 成功消耗 fd、失败不消耗；负 fd 不能传该 API。ReleaseNativeWindowBuffer 消耗其传入的 release fence，不能二次 close。映射/停止超时、最后 lease 与 image owner 的销毁顺序均需验证。
5. 模拟器正确性通过也不能替真实设备证明驱动内部零搬运或持续性能。当前模拟器查询版本为 `emulator 7.0.0.23(SP41DEVC00E45R1P3)`，应用编译 target/compatible 仍为 API 23。
6. `src/ohos_shared_frame_display.rs` 是未挂入 HAR 的独立 FFI 原型，不是已完成的显示实现；枚举值已纠正为 RGBA8888=12、I420=28，原审查中误把头文件行号当数值的结论已废弃。
7. 下一步可验证候选是 RGBA NativeBuffer 作为 raw byte atlas，由 shader 按实际 Y/U/V offset/stride 取字节；要求紧密 row stride、正确非 sRGB 采样、CPU/GPU cache 同步和 fence。此路线尚未编码闭环，不许用 glTexImage/upload、CPU 中转或未经验证的 EGL 导入冒充完成。
8. 严格零拷贝协商门控和状态上报尚未接线；本批是基础设施开发构建，**没有可宣称达标的兼容/高性能模式**。不能把现有软编/PixelMap 路径列为用户允许的例外。
