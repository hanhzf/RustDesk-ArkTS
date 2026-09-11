# 零拷贝实施：App 上下文诊断

本轮只验证合成 NativeBuffer 在真实 App 进程中的分配、映射与 CPU access 同步，不把结果扩展成 GPU 显示、真实 decoder reference 或整链零拷贝证明。原 UI、三仓依赖方向和源版本不变。

## 环境纠正

- 项目 `build-profile.json5` 的 target/compatible 仍为 `6.1.0(23)`；源码 `AppScope/app.json5` 为 `1.0.3 / 1000005`。
- 当前 command-line-tools 的 `ets/oh-uni-package.json` 与 `native/oh-uni-package.json` 均为 `apiVersion=26`、`version=26.0.0.32`、`releaseType=Beta2`。DevEco ETS 元数据亦为 26。
- 本轮精确目标命令 `hdc -t 127.0.0.1:5555 shell param get const.ohos.apiversion` 返回 `26`。
- 因此必须区分 API 23 **兼容目标/接口 since** 与 API 26 **实际编译、模拟器环境**。此前把目标号直接称为实际 API23 SDK/设备环境不严谨；本轮没有修改 SDK、模拟器或工程目标，也不据此声称 API23 设备验证通过。

## 独立程序 ELF 排查

- 前轮探针为 AArch64 PIE，动态依赖 `libnative_buffer.so`、`libnative_window.so`、`libEGL.so`、`libGLESv3.so`、`libc.so`；没有 RPATH/RUNPATH，Alloc 是未定义动态导入，不是被静态复制进可执行文件。
- 本地 SDK 的 Alloc 是链接 stub，唯一指令为 `ret`，不能独自解释观察到的 nanosleep。链接 SDK stub 不等于运行时使用 stub。
- 模拟器的系统目录查询返回权限拒绝，未尝试绕过权限或从其他命名空间读取库。实际运行时库及 Alloc 内部等待原因仍未核实。
- 已观察到 main 的 request 输出，故不能把原因归为尚未完成的普通启动构造函数；Alloc 内部的延迟初始化仍只是待验证假设。

## 诊断约束

- 仅显式 Want 字符串参数 `rustdesk.nativeBufferProbe=1` 且实际 `ApplicationInfo.debug=true` 时触发；正常启动不运行探针。
- HAR 内专用线程执行，NAPI 和 UI 不等待原生调用；每进程至多一次尝试，重复请求不产生并行工作线程。
- 10 秒为逻辑报告截止，不是强制取消 NativeBuffer 调用的保证。若调用不返回，状态须明确线程可能仍运行，晚到结果不能改写终态。
- 合成输入固定 128×16、RGBA8888=12、CPU_READ|CPU_WRITE|HW_TEXTURE=515；无屏幕、账号、设备身份或真实远程像素内容。
- 长期 Map，同方向 `DMA_BUF_IOCTL_SYNC START|RW / END|RW`，直接写入并再次读取合成图案；不关闭借用 fd，不引入 CPU 上传或复制降级。
- 本轮没有 GPU consumer；即使 CPU 探针通过，也不证明跨 CPU/GPU cache 可见性或 driver 内部没有 staging。

## 实施与验证

### 代码

- HAR `src/ohos_native_buffer_probe.rs`：一次性线程、粘性截止状态、NativeBuffer/窗口 wrapper/映射/CPU epoch 的 RAII 清理；原生失败先暂存，资源清理及析构返回后才发布完成。若清理卡住，仍可报告逻辑超时和线程存活。
- HAR `src/lib.rs`、`types/index.d.ts`、`package/index.ets`：对应导出 `runtimeStartNativeBufferProbe` / `runtimePollNativeBufferProbe`，没有增加 Cargo 依赖或修改 Core。
- ArkTS `NativeBufferDiagnosticService.ets`：严格字符串 Want guard、异步真实 debug 属性检查、每进程一次、300ms 轮询和约12秒本地停止界限，日志只投影安全诊断字段。
- `EntryAbility.ets` 仅增加 service 的导入、实例、onCreate/onNewWant 调用和 onDestroy 清理。保留现有 UI、隐私、传感器和窗口逻辑。

### 局部测试与构建

- 父会话抽取最终 Rust 生产 State 模型及同文件测试：3 项通过，包含并发一次性注册、清理期超时、终态不被晚到结果改写；不包含 FFI/NAPI 执行。
- 父会话对最终 ArkTS service 原始源码执行 Node 类型擦除测试：5 组 guard/生命周期场景通过，涵盖非字符串/非debug拒绝、异步返回前销毁、重复 Want/跨实例锁存、终态停止，以及已尝试 native start 后异常不谎报线程已停止。SDK、NAPI、timer 均为 mock，不替代设备测试。
- Core/HAR `cargo build --target aarch64-unknown-linux-ohos --release --locked` 通过（1m47s）；随后用最终四个 HAR 源文件的前后 SHA-256 校验冻结状态，再次构建通过（8.17s），确认原生库哈希没有变化。日志 `/tmp/resk-zero-copy-round2-native.log` 与 `...-native-final.log`。
- 两个 ArkTS 文件同步到镜像前，确认镜像旧 EntryAbility 与源仓 HEAD 一致，未覆盖镜像额外改动。源仓与镜像均使用刷新脚本重装 HAR/oh_modules。
- 镜像 `assembleApp product=default buildMode=debug --no-daemon --no-incremental` 成功，10.847s；签名临时目录已清理，剩余数为0。日志 `/tmp/resk-zero-copy-round2-arkts.log`。有 baseline warnings，不声称零 warnings。

| 产物 | SHA-256 |
|---|---|
| HAR package.har | `dc5b719adc1142c4b352747ad1f89f7839888374d8c1e47c82d5c7998b8aca9b` |
| 原始 SO | `8b76aa7ff0bca68361d6fd89f7c3053455eae6c0e964f1abefc3b6d14e24ec0c` |
| signed HAP | `4724a783431936168df6bc84aaa263522f280d5b38827dbe7ff21c23eaab6521` |
| HAP 内 stripped SO | `de80b17803b1b71bdaefa65f2431422b6441f65690b8c0d62a3c1eb64e1d43be` |

原始与打包 SO 的23个可加载 ELF section 属性、地址、大小及内容一致；两个镜像诊断源文件亦与源仓逐字节一致。

### 实际 App 结果

只向 `127.0.0.1:5555` 保数据 `install -r`，返回安装成功。先正常启动，再用热启动 Want 触发：

```text
hdc -t 127.0.0.1:5555 shell "aa start -b top.frankhan.resk -m entry -a EntryAbility --ps rustdesk.nativeBufferProbe 1"
```

实际 App PID 为5283，安装信息 `1.0.3.88 / 10322965`、debug=true、debug Profile。只采集 `RustDeskZeroCopyProbe` tag，采集进程由设备 timeout 限制25秒，已结束收取。原始日志 `/tmp/resk-zero-copy-round2-app-probe.log` 的安全状态投影为：

```json
{"state":"failed","stage":"write_sync_start_rw","terminal":true,"workerMayStillBeRunning":false,"elapsedMs":25,"detail":"write_sync_start_rw failed; errno=13; attempts=1"}
```

**已确定**：真实 App 路径越过 Alloc、config/handle 布局与容量检查、非空 Map 成功检查；第一次 `DMA_BUF_IOCTL_SYNC START|RW` 返回 EACCES(13)。原生清理函数及析构已返回，线程已结束，所以没有执行预备的超时重启。后续 UI hierarchy 仍可获取，主页面标签存在。

**未确定/未运行**：拒绝来自哪一层尚未定位，不推断为驱动永久不支持、缺某个可申请权限或参数错误。没有重试该拒绝调用、提权或跳过同步。图案写入、第二 epoch 比较及全部 GPU 阶段均未执行；25ms 不是帧率/编码性能测量。日志投影未包含 `cleanupDetail`，不据“线程结束”额外保证每个清理返回码成功或驱动资源已完全回收。冷启动携带参数、release包与销毁场景未做设备测试，只有相应源码/mock边界检查。

## 下一轮的受限候选

当前 NativeBuffer＋直接 DMA-BUF ioctl 的持久映射路线，在上述 App 身份/配置下不能进入 CPU epoch；不把 Unmap 当稳定映射同步来规避它。可独立核验 **GL 自有持久映射 buffer**，它不复用已拒绝的 NativeBuffer fd/ioctl：

1. App 内先查询 GLES≥3.1、`GL_EXT_buffer_storage`、真实入口及 shader容量；SDK 头文件有声明不等于运行支持。
2. `glBufferStorageEXT`＋`glMapBufferRange` 使用 READ/WRITE/PERSISTENT/COHERENT；按公开规范保持映射期间 GPU 可以使用同一 buffer。普通 map 或 PBO→texture 上传不属于候选。
3. shader 经 SSBO 或另行验证的 texture-buffer 直接读取字节，不走 CPU 上传。coherent 不替代执行互斥；CPU完成交接、GPU读完 fence成功、codec reference释放三者要明确排序。
4. 若采用非coherent合法变体，CPU写必须显式 flush所有脏范围，不能用client barrier冒充CPU写flush；本轮没有实现或验证任何变体。
5. 最小验收为同一指针两轮读/写＋GPU采样＋有界fence＋逐字节验证（回读仅用于测试），再检查真实codec租约。即使通过，也不单独证明driver没有shadow/staging。

公开合同来源：[EXT_buffer_storage](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_buffer_storage.txt)、[EXT_texture_buffer](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_texture_buffer.txt)。本轮仅完成合同核验，**没有启用此候选，也没有完成整链零拷贝或严格协商门控**。
