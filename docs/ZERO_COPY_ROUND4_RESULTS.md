# 零拷贝第四轮：OHOS 编码输入接线

本轮把第三轮的隔离 VP9 输入槽原型推进到版本化 OHOS 依赖、Core 私有输入租约和受限 App 合成编码验证。不把普通采集/显示路径或未测试设备标成零拷贝；不改原前端、不改源码版本、不改远端，不自动更改用户配置。

## 验收范围

1. 固定 patch/ABI/header/archive 的可复现构建与缓存失效，不能看到旧 libvpx.a 存在就跳过，也不能把头文件宏当库实现证明。
2. 显式 `VpxEncoder::new_owned_input` 与私有 RAII slot：完成元数据/最小 span/不重叠检查，转换借用结束后才 commit，错误按 token 消费状态处理；取消失败或 codec 已执行后失败均 poison，不回退旧复制路径。
3. 新 App 调试参数 `rustdesk.encoderInputProbe=1` 字符串，真实 debug 属性门控，与另外两种参数同时有效时拒绝。共享每进程一次锁存，异步工作、粘性10秒逻辑截止，不声称能取消原生调用。
4. 使用实际 Core owned 编码入口与普通 VP9 decoder 处理合成 BGRA/RGBA 帧，核对压缩消息、解码尺寸/帧数。测试输入分配及普通 decoder 的存储不是生产采集/显示零拷贝证明。
5. 生产发送端仅增加默认关闭的本地 `ohos-owned-input-strict=Y` 入口，不在本轮设置该选项或自动启用；strict 跳过 Frame::to，明确拒绝不兼容 codec/I444/错误，不吞错或重协商回 legacy。可用性及真实会话仍需后续验收。

## 采集路径复核

当前正常 ConsumerSurface 已经 `acquire_and_lease_frame → push_host_screen_frame_lease`，Core Capturer 保存 Arc 并借用真实像素/stride；旧 packed RGBA callback 仍在文件中，但不是当前 lib.rs 启动的 receiver。真实 capture 的 MapWaitFence/MapPlanes 生命周期与第二轮合成 persistent-map/ioctl EACCES 属于不同路径，不能相互推断失败。

实际 capture 映射、持帧占用、stop/reset generation、resize、截图分支和端到端仍需验证。已有截图转换不会因为 strict 编码入口存在就自动得到零拷贝豁免。

## 实施与验证

### 1. 生产 OHOS 依赖

HAR `scripts/build-libvpx-ohos.sh` 与新增 `scripts/verify-libvpx-owned-input.sh` 已接入第三轮冻结 patch。固定 upstream archive SHA、source manifest、patch、ABI、全部公开/私有头和实际静态库，验证 defined symbols 后才接受 receipt。缓存 identity 包含目标/配置、NDK/sysroot/clang 资源及工具内容、脚本哈希；库存在不再等于构建有效。

- 新源码/构建始终位于 `target/ohos-libvpx-owned-v1/<key>/attempt.../`，旧 vendor 源码/实验目录未回退或覆盖。先验证原始 archive/manifest，再 `patch --forward --fuzz=0`。
- 原生产 configure 保留 VP8/VP9、threading/SIMD defaults；没有把宿主实验单线程编译配置全局套入生产，也没有 `RD_VP9_OWNED_TEST` 计数器。
- OHOS clang 静态断言 ABI1、arm64 `sizeof(rd_vp9_owned_view_v1)=120`；llvm-nm 要求 acquire/cancel/commit_ex 与原有 VP8/VP9 cx/dx/encode/decode 均为 defined symbols。
- stage 构建/验证成功后按文件原子发布，receipt最后写。producer锁与 Core构建检查阻止并行发布期间链接。
- Core `libs/scrap/build.rs` 验证 root 与实际 vcpkg prefix 相同，避免验证A库却从全局搜索路径链接B库；验证成功后才 emit `ohos_vpx_owned_input`。`vpx_ffi.h` 按OHOS条件导入版本头，bindgen用真实target/sysroot生成rd/RD绑定，没有手写Rust ABI。

父实际生产库构建成功，再次调用命中已验证缓存且 archive/receipt 哈希不变：

```text
cache_key: 0c9c5da7e1d6ab53940e776eeb05c0b47c46719c758398e330d9e82d1f213a3e
libvpx.a: 0c0d2389bdba053ce939e29eba48a80f16b05e5d692b59e4c5ff7c0614a4603f
receipt:  e74ffd071457d54b2b307a155b3f4f431232dda1eb03bffe17ef4524b4ec18ba
```

日志 `/tmp/resk-zero-copy-round4-libvpx.log`、`...-cache-hit.log`。Agent另执行了隔离的 manifest/patch二次应用拒绝、缺receipt、过期ABI、头/库变更、符号缺失等负向校验；这些与父真实生产构建分开计账。

### 2. Core 私有租约和 strict 发送分支

- 新 `common/vpx_owned_input.rs` 作为 `vpxcodec.rs` 的私有子模块；显式 `new_owned_input(VpxEncoderConfig)`，独立配置固定尺寸/profile0/I4208/one-pass/lag0/单线程，控制项在首次 acquire 之前完成。通过首次 acquire/cancel 验证能力后才返回。
- slot借用整个ctx+state且不可Send/Sync/Clone，先核对 ABI/120bytes/token代数、luma32/chroma16对齐、stride、每plane最小span、地址溢出与交叠，再构造短借用slice。foreign provenance/初始化依赖已审查C owned pool：`yv12config.c`首次/扩容分配后清零整个allocation；没有Rust每帧额外清零。
- 必要BGRA/RGBA转换直接写最终槽。转换失败/early return/unwind取消；消费后的codec错误不再取消且poison；NOT_CURRENT/未知结果不取消其他槽而poison。取消失败同样poison。
- owned对象拒绝旧 encode/flush/set_quality；普通对象拒绝 direct，不自动升级。压缩packet仍进入既有VP9消息封装，压缩码流复制不计作像素搬运。
- `common/codec.rs::Encoder::new_owned_input`拒绝I444/非VP9；`server/video_service.rs`新增每run冻结的本地option，strict setup不retry/不重协商、不强改I444。借PixelBuffer跳过Frame::to；保持subscriber snapshot在转换/编码前。direct错误不进入legacy吞错分支，不重复发送旧yuv。
- strict的质量固定并打印一次说明，不调用被禁止的QoS set_quality；仍保留pacing、record检查及统计。截图旧逻辑没有修改，明确可能搬运；**该option是最终编码输入约束，不是全链零拷贝开关**。本轮没有设置Config值或触发真实strict会话。
- Core `src/platform/ohos.rs::encoder_input_probe_support`只做窄类型重导出，HAR没有新增scrap依赖/另写协议；三仓方向保持。

### 3. 测试层级

- 父用**本轮真正生成的rd绑定**、生产 `validate_view/commit_outcome` 与同文件测试进行独立rustc测试：3项通过。仅检查元数据和消费状态，不解引用fixture地址、不假装执行原生取消。
- HAR诊断State独立3项通过：一次性、清理期间截止、截止后不能变成成功。此探针的`deadline_exceeded`在codec作用域退出之前仍`terminal=false`，UI另有约12秒/40次轮询上限；这与“超时等于已清理”明确区分。
- ArkTS最终源码提取的mock回归通过：三种kind所有8种组合、严格字符串值、重复/异步切换、销毁/debug guard与匹配的start/poll路由。SDK/NAPI/timer均mock；真实ArkTS编译另见下节。
- 新增1个 `Encoder::new_owned_input` 多codec/I444构造拒绝测试留在Core源码，**未执行**。父尝试从HAR运行 `cargo test -p scrap --target ... --release --locked --lib --no-run` 被Cargo明确拒绝：scrap需要dev-dependencies且不是当前workspace member，未进入编译。没有因此改workspace、添加开发依赖或把它说成测试通过。
- 三仓diff--check通过；新owned/诊断文件格式检查通过。旧整文件格式不为本轮改造而重排。

### 4. App 真实目标编码验证

只向 `127.0.0.1:5555` 保数据 `install -r`，正常启动后用显式热启动参数：

```text
hdc -t 127.0.0.1:5555 shell "aa start -b top.frankhan.resk -m entry -a EntryAbility --ps rustdesk.encoderInputProbe 1"
```

App PID2567返回 `passed_encoder_probe / terminal=true / workerMayStillBeRunning=false`，codec scopes清理完成。四个case结果：

| 尺寸/输入 | 编码帧 / packet / 解码帧 | NV12前置拒绝 | acquired槽后短输入拒绝 | 拒绝后同encoder成功帧 |
|---|---|---:|---:|---:|
| 80×48 BGRA | 16 / 16 / 16 | 1 | 1 | 16 |
| 80×48 RGBA | 16 / 16 / 16 | 1 | 0 | — |
| 81×49 BGRA | 16 / 16 / 16 | 1 | 1 | 16 |
| 81×49 RGBA | 16 / 16 / 16 | 1 | 0 | — |

短输入保留正常格式/尺寸/stride，只把同一TEST Vec的可见slice缩为1字节；格式/dim前置检查通过，失败落到acquired slot的转换bounds检查。恢复完整slice后同encoder各成功16帧，验证取消与恢复。NV12在acquire前拒绝，**不能单独作为RAII取消证据**。

所有压缩消息检查为VP9、packet非空，普通VP9 decoder确认每帧尺寸与总数。输入为测试分配、最小span和非紧stride，普通decoder并非新共享显示路线；未做目标端逐像素画质/legacy packet parity/复制计数/生产会话测试。日志中的17ms只是该合成诊断耗时，不是FPS或极限吞吐。

有界25秒单tag采集已结束并收取，`/tmp/resk-zero-copy-round4-app-encoder.log` 含旧GLES历史行；只使用PID2567且probeKind=encoder_input的新两行作为本轮证据，没有触发旧GLES/NativeBuffer探针。事后PID仍存活，hierarchy中的 `RustDesk / 服务端 / 设置` 存在。

### 5. 构建安装产物

- Core/HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked` 成功，2m24s；9个相关源文件SHA在构建前后完全一致。
- 源仓与APFS镜像均通过refresh脚本重装HAR/oh_modules。替换镜像service前核对了第三轮冻结SHA，没有覆盖未知镜像修改。
- `hvigorw tasks --mode project`确认assembleApp，项目级列表没有test任务。`assembleApp product=default buildMode=debug --no-daemon --no-incremental` 成功，8.927s；临时签名目录已清理，仍有baseline warnings。

| 产物 | SHA-256 |
|---|---|
| package.har | `ea0031d045f55c463afd016784fa70a969f247df3cee23aa4ceee626da3ae17d` |
| 原始HAR SO | `7085bfb61d0342c15d711461ab8679b400f370adcea2c6d13fd145e178a7b43d` |
| signed HAP | `e4317dbf59f921a94a87720ea4183e77fbee2fd60641b86ca2358ccff30f8b6c` |
| HAP stripped SO | `1a319bc950073e95ba924d1c34f934f763bc3c306c3cc84d80b54589b99ec0c4` |

原始与打包SO的23个可加载section属性/地址/大小/内容一致。安装查询 `1.0.3.88 / 10322965`、debug=true、debug Profile；源版本 `1.0.3 / 1000005` 不变。兼容目标API23不变，SDK/模拟器仍按此前核验的API26环境计账，不当作API23设备验收。构建日志 `/tmp/resk-zero-copy-round4-native.log`、`...-arkts.log`。

## 下一轮的收敛目标

编码输入已从“宿主实验”推进到**目标App真实Core执行**，strict发送分支已编入但未启用。下一步优先验证真实captured lease→strict输入的格式/stride/尺寸及生命周期，在不改变认证/协议和不静默回退的条件下验证持续会话、stop/reset与订阅变化。需要明确strict协商的VP9/I420范围；不能用该局部编码结果覆盖截图、driver隐式搬运或显示端缺口。

显示端仍保留第二轮特定ioctl EACCES与第三轮context GLES3.0两个独立事实。本轮没有修改这些拒绝路线，也没有证明生产整链零拷贝、官方互通或极限性能。长期目标保持active，未标complete或blocked。
