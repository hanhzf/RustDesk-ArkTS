# 零拷贝第三轮：编码端最终输入槽与 GLES 共享读取

用户进一步确认允许为极致性能修改编码端。本轮将发送侧优化与显示侧能力验证并行推进；不再以显示侧探针作为编码端工作的前置条件。原前端、源码版本、Core→HAR→ArkTS 方向及禁止静默复制降级不变。

## 两个独立验证面

### 编码端

- 现有 VP9 `lag=0` 并未消除 `vp9_lookahead_push` 的整帧输入复制，且 `Last_Source` 仍可能引用上一帧。不能通过借用普通输入指针然后在 encode 返回时释放来替代 owned pool。
- 隔离原型由编码器拥有最终 lookahead 槽，提供版本化 acquire/view/commit/cancel；调用者应直接向最终可见 planes 产生像素，commit 只保留必要的边缘扩展。
- 原型先限制固定 8bit I420/profile0、one-pass、lag0、非 SVC 等已核验条件；其他配置不自动回落旧复制路径。测试应覆盖循环槽、上一帧历史、取消及错误状态，并与同库 legacy 路径比较真实编码结果。
- Core 增量路线为独立 `encode_pixelbuffer_direct` 入口，默认 Unsupported；BGRA/RGBA 的必要转换直接写最终 I420 planes，不借 `Vec::from_raw_parts` 冒充拥有 vendor 内存。外部 I420→I420 槽搬运不算达标。
- 实验 vendor 源码/库与生产构建隔离。接线前还需要固定 patch/ABI/构建配置缓存键、版本化强链接验证、slot RAII 及明确的 strict 输入模式；没有启用生产路线就不能提升能力表。

### GLES 显示侧基础

- 新调试参数为 `rustdesk.glesBufferProbe=1` 字符串；仍须真实 debug App。与旧 NativeBuffer 参数同时有效时拒绝，不能在异步 debug 查询期间切换 kind；共用每进程一次的 ArkTS 锁存。
- GLES 是自己的 buffer/context/surface，不重试被拒的 NativeBuffer fd/ioctl。先验证实际 GLES 版本、persistent-buffer 扩展、入口和 shader 容量，缺失则停止；不以普通 map、PBO 上传或 texture upload 替代。
- 候选测试在同一 persistent/coherent CPU 映射上完成两轮生成、GPU SSBO 直接读取、fence 等待、仅用于测试的逐字节回读比较。即使通过，也不是 driver 无 staging 或真实 codec/显示链的证明。
- App 的默认 EGL display 可能被 ArkUI 或其他 renderer 共享，探针不得调用 `eglTerminate`；只清理自己创建的 GL 对象、pbuffer 和 context。Khronos 明确说明 terminate 会把该 display 关联的所有 EGL 资源标记删除，不能按“本线程的 display”误解：[eglTerminate](https://registry.khronos.org/EGL/sdk/docs/man/html/eglTerminate.xhtml)。

## 验证记录

### 1. 编码器隔离原型：真实 C 执行通过，未替换生产库

HAR `tools/encoder_input_probe/` 交付版本化头文件、实现片段、可重建 patch/script、C fixture、依赖 manifest、README 与 RESULTS。最终 patch：

```text
libvpx-1.16.0-owned-input-v1.patch
SHA256 2689e2273caaac3e5ef9848e577bad5f3f53bcacda51866733630247e0c43cd3
```

- `rd_vp9_owned_v1_acquire` 返回编码器拥有的 visible planes/stride、最小合法 `span_bytes[3]` 和 context-local token；取消不推进环。C 层先证明各 span 在 allocation 内且互不重叠。
- `rd_vp9_owned_v1_commit_ex` 明确输出 submitted token 的 `NOT_CURRENT / STILL_PENDING / CONSUMED`；进入 codec 后即使失败也已消费并 poison，不能 cancel/retry。保留旧五参数 commit 的调用 ABI，新 Rust 接线必须使用 commit_ex。
- 固定 8bit/profile0/I420、单线程、16..4096、one-pass/lag0/non-SVC。首次 acquire 后冻结 config 与62个控制入口；不支持的配置明确拒绝。当前单线程限制是原型安全边界，不是最终极限性能选择。
- ring 仍由 libvpx 分配/释放，容量2，沿用 `peek(-1)` 历史和160 allocation border；边缘扩展共用原实现的尺寸数学，只去掉 visible-row memcpy。luma stride32对齐，UV stride是其一半，不能把32误施加到全部 planes。

最终真实 C plain 与 ASAN+UBSAN 两轮分别通过下列相同结果：

| 输入测试 | 尺寸 | 每条路径帧数 | 压缩字节数 | legacy/direct 已定位 lookahead copy 次数 |
|---|---|---:|---:|---|
| 生成 I420 | 80×48 | 64 | 74534 | 64 / 0 |
| 生成 I420 | 81×49 | 64 | 80050 | 64 / 0 |
| 生成 I420 | 127×71 | 64 | 91711 | 64 / 0 |
| BGRA→最终 I420 | 80×48 | 64 | 67251 | 64 / 0 |
| BGRA→最终 I420 | 81×49 | 64 | 69418 | 64 / 0 |
| RGBA→最终 I420 | 80×48 | 64 | 67251 | 64 / 0 |
| RGBA→最终 I420 | 81×49 | 64 | 69418 | 64 / 0 |

同一 patched 库的两条路径比较了 packet 的全部字节、大小、flags、pts、duration、数量；全 allocation padding/border 对照每尺寸64轮也通过。包括 scene change、强制 keyframe、取消/重复获取/陈旧和重复提交、span篡改、配置冻结、真实 lower queue-full、错误消费/poison 和 pending destroy 边界。RGBA/BGRA 使用独立编译的**libvpx 随附旧 libyuv**，直接转换入 acquired planes，无 I420 staging。

宿主 Darwin arm64 / Apple clang17，generic C CPU-only、O1/debug/assertions；ASAN/UBSAN 覆盖 codec、libyuv、fixture。无运行时 sanitizer 错误；有一个 libyuv 非致命向量化 warning，macOS 禁用 LSan。没有执行 OHOS/SIMD/真实采集/吞吐测试，也没有排除所有 codec 算法内部复制。

父会话读回两个最终 transcript，并核对最终 patch 哈希。原生产 vendor 的源文件与依赖哈希未被修改。详细命令及限制见 HAR `tools/encoder_input_probe/RESULTS.md`，最终日志目录：

```text
/Volumes/RustDeskBuildCache/zero-copy-encoder-lab/host-asan-contract-final/
/Volumes/RustDeskBuildCache/zero-copy-encoder-lab/host-plain-contract-final/
```

### 2. Core 直写基础：已交叉编译，但没有生产调用者

- `libs/scrap/src/common/encoder_input.rs`：三块独立短借用 slice + stride 的 `I420PlanesMut`；`convert_to_i420_planes` 直接调用现有 ARGBToI420（BGRA）/ABGRToI420（RGBA）。先完整检查全部平面、最小跨度、奇数 UV、尺寸和 c_int/双行 stride 溢出，再执行任意 FFI 写入。
- `common/mod.rs` 只挂模块和导出；`common/codec.rs::EncoderApi::encode_pixelbuffer_direct` 默认返回 Unsupported，没有旧路径 fallback。本轮没有修改 VpxEncoder/server 调用链。
- 父会话把最终模块通过 `#[path]` 纳入独立 rustc harness，并链接**生产 pin b56492... 的真实 libyuv 宿主库**（源目录只读，构建另放 APFS）。错误类型/trait定义为隔离适配，FFI非mock。3个源码测试 + 1个真实3×3最小span/非紧stride/padding验证通过。
- 首次红色测试发现 V 实际为239，不是旧随附版本的240；核验生产 pin `row_common.cc` 的 `(112*255+32768)>>8=239` 后，将跨libyuv版本的源码 sentinel 接受239/240，仍严格检验通道顺序、Y/U和padding；生产pin的3×3对照固定239。没有篡改转换算法去迎合旧测试。此最后调整仅在 `#[cfg(test)]` 内，晚于 App 构建，不改变安装二进制。
- 测试命令/fixture `/tmp/resk-r3-encoder-input-tests.rs`，宿主库 `/Volumes/RustDeskBuildCache/zero-copy-libyuv-tests/libyuv.a`。不据此声称目标机执行已验证。

### 3. GLES 探针与 App 实测

HAR 新 `src/ohos_gles_buffer_probe.rs`，对应两项 NAPI/package/type 导出；ArkTS 仅扩展现有 `NativeBufferDiagnosticService.ets`，EntryAbility/UI未再修改。严格 gate、专用 thread、10秒粘性逻辑截止、仅自身 EGL 资源清理，`zeroCopyProven=false` 始终不变。worker只在观察 JoinHandle 已结束后报告 false。

父审查补充：若 EGL≥1.5，显式请求 GLES3.1 minor；旧 EGL 使用现有 ES3 请求，再查询真实 GL 版本。数字 gate 证据投影到安全 detail，终态时冻结，避免晚到 metadata 改写结果；不打印句柄/fd或设备标识。独立 State 3项测试通过，ArkTS源码提取 mock 回归覆盖 kind路由、含糊请求拒绝、异步期间切换/销毁、一次性锁存、安全日志和异常保守报告（agent执行，不是设备自动化测试）。

本轮唯一设备目标 `127.0.0.1:5555`，先保数据 `install -r` 并正常启动，再显式热启动：

```text
hdc -t 127.0.0.1:5555 shell "aa start -b top.frankhan.resk -m entry -a EntryAbility --ps rustdesk.glesBufferProbe 1"
```

App PID9464，安全诊断终态97ms：

```text
state=failed; stage=glGetError; terminal=true; workerMayStillBeRunning=false
GL=3.0; RGBA=[8,8,8,8]; epochs=0
actual context is below GLES 3.1; cleanup error detail empty
```

**只确定本次 context 报告3.0**；日志未投影 EGL 版本/实际使用的 context attributes，因此不声称所有配置或真机的最高能力都是3.0。版本 gate 提前拒绝，未查询 persistent扩展/入口/SSBO容量（仍为unknown），没有 buffer allocation/map/shader/draw/readback。没有旧 NativeBuffer ioctl 调用，没有提权/上传降级，没有挂起 worker，无需重启App。25秒有界单tag日志采集结束且已收取；采集日志 `/tmp/resk-zero-copy-round3-app-gles.log`。

安装信息仍为 `1.0.3.88 / 10322965`、debug=true、debug Profile（镜像旧版本保留，源版本未变）；事后 UI hierarchy 能取得，`RustDesk / 服务端 / 设置` 标签存在。源码target/compatible仍API23；实际SDK/模拟器为此前核验的API26。

### 4. 构建与产物

- `hvigorw tasks --mode project --no-daemon` 确认 assembleApp 存在，当前项目级列表未提供 test task；未杜撰执行设备测试命令。
- Core/HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked` 通过，2m33s；构建期间7个生产相关源文件SHA前后一致。没有把宿主实验 libvpx 替换进此构建。
- 源仓和镜像均通过 refresh-native-har.sh 刷新 HAR/oh_modules；新 service 镜像与源逐字节一致。
- `assembleApp product=default buildMode=debug --no-daemon --no-incremental` 通过，12.512s；临时签名目录清理完成。baseline warnings仍存在。

| 产物 | SHA-256 |
|---|---|
| package.har | `2b8baa7f1000048c801cccf8ce3e8aba4b301343184d1ff6f28dca773ddffbb5` |
| 原始 SO | `7a33ac31a227b64e8e13d4ed6eeee8d39eb0539081475088a2aaf082f25f2a31` |
| signed HAP | `23e6812d664e15bf25cd9d7c468e3f95fd9298fe3ea226da9710b3230481565e` |
| HAP stripped SO | `967afeb1ae3e14c2777c671e824903c5154ad508b35b989b9fb6d4e9d815243b` |

原始与打包SO的23个可加载 section 属性/地址/大小/内容一致。原生/ArkTS日志分别为 `/tmp/resk-zero-copy-round3-native.log`、`...-arkts.log`；三仓 diff--check通过。全部相关父/子后台任务已收取，无残留采集或浏览器。

## 下一轮收敛验收

优先把编码端原型变成可复现的 OHOS 版本化依赖：固定patch/cache key/ABI符号→生成绑定→私有Rust slot guard→BGRA/RGBA最终槽转换→真实目标编码对照。不得仅改头文件就复用旧静态库，不得 silently ignore Unsupported；原型单线程/冻结配置等限制必须明确，不默认套到所有codec/运行配置。真实采集租约仍须接入；显示端保留本次 GLES3.0 与前轮 ioctl EACCES 两个独立缺口。

**本轮消除了隔离编码实验中已定位的 lookahead 输入复制，尚未完成生产整链零拷贝、官方互通验收或性能测量。目标继续，未标完成或blocked。**
