# 真实录屏与 Core 软件编码验证

## 设计纠正

系统 H.264 encoder 不可用不等于服务端无法编码。Core 已包含：

- `VpxEncoder`：VP8 / VP9；
- `AomEncoder`：AV1；
- `OhosVideoEncoder`：运行时可用时的原生 H.264 / H.265。

编码和解码是两端不同的工作。被看端将真实录屏的 raw frame 交给 Core
标准 `video_service`，由已有的 capability / peer preference / `AV1_TEST`
逻辑决定编码器。不强制 H.264，也不在 HAR 复制协议、编码或发包。

```text
OH_AVScreenCapture_StartScreenCaptureWithSurface
 -> OH_ConsumerSurface
 -> OH_NativeImage_AcquireNativeWindowBuffer + acquire fence
 -> OH_NativeBuffer_MapWaitFence
 -> stride-aware owned RGBA copy
 -> ohos::push_host_screen_frame_rgba
 -> scrap::ohos::Capturer
 -> Core video_service / VP8, VP9, AV1 或可用原生编码
 -> 官方 RustDesk 客户端
```

禁止截图 / PixelMap 轮询兜底。外部 `snapshot_display` 只用于确认系统 UI，
不进入产品录屏链。

## 本轮代码

- Core 移除了此前未验收的 `HostH264SurfaceEncoder`、其专用队列、platform
  wrappers 和 `run_ohos_surface_encoded`；恢复标准视频服务的 QoS / 录像 / 发包。
- Core `libs/scrap/src/common/codec.rs` 不再忽略 OHOS 的软件 codec 偏好，
  不再将 VP9 固定为唯一软件 Auto 路径。
- HAR `src/lib.rs` 的当前生产路径使用公开 ConsumerSurface / NativeImage API。
  NativeBuffer 通过 acquire fence 映射，按 stride 复制到 owned RGBA；停止时先停
  AVScreenCapture producer，再 join consumer worker 并释放 NativeImage/window。
- `src/ohos_capture_receiver.rs` 保留为 ImageReceiver 诊断候选，不是当前生产路径。
- HAR 只在 native STARTED 且真实 raw frame 被 Core 接收后启动 host。
  授权选择最多等待 120 秒，授权后的首帧另有 30 秒预算，不能混为一个计时器。

## 2026-09-05 的实际证据

### DNS

用户配置 Fake-IP 绕过后，本轮 macOS `dscacheutil` / `dig` 和指定模拟器
`ping` 均把 `rs-ny.rustdesk.com` 解析为真实地址 `209.250.254.15`。
旧 `198.18.0.40` Fake-IP 阻塞不再适用。

DNS 修正不等于已经完成加密握手或持续视频验收，后两者仍需真实会话证据。

### ImageReceiver / ConsumerSurface 布局

`.73` 收到图像，但组件 `pixelStride=1` 被误当像素步长而拒绝。
`.74` 的 ImageReceiver 确认实际 NativeBuffer：RGBA8888（format 12）、1920×1280、stride 7680。

公开 OpenHarmony ImageFramework 源码解释了该值：
`CreateCombineComponent` 为匹配 SurfaceBuffer format 的合并组件设置
`pixelStride=1`，这是组件字节流语义。真正 packed RGBA 的布局应依据
`OH_NativeBuffer_GetConfig`，并用 image component 的 buffer size 校验访问边界。

`.74` 第一张全零 allocation 被立即判错；这不能证明后续录屏一直失败。
ConsumerSurface 路径随后取得了 acquire fence；`.80/.83` 真实运行中得到
1920×1280、stride 7680、format 12，但内容采样仍稀疏。

### 授权窗口与计时

`.75` 指定屏幕模式弹出 `com.huawei.hmos.screenrecorder/SelectWindowAbility`，
不是旧“允许”对话框。其窗口需要选择“屏幕 1”，再点击“开始共享”。
不能沿用旧授权坐标，也不能把未完成选择造成的无回调当作采集 API 故障。

实际一次日志：

- 18:00:33.439：StartScreenCaptureWithSurface 返回 0；
- 18:01:02.216：系统 STARTED；
- 18:01:02.257：收到 3120×2080、stride 12480、format 12、usage 9 的图像；
- 随后观察到启动全零帧；
- 18:01:03.445：旧总计 30 秒预算耗尽，实际只给了约 1 秒采集时间。

这次结果不足以证明持续录屏失败，也没有可见远端画面证据。

### 同步与消费边界

检查的公开 ImageFramework 源码 `ReadLastImage` 没有使用 AcquireBuffer
返回的 fence，并在 drain 中未显式释放被跳过的 buffer。它是源码层面的风险，
不是已经证明当前商业模拟器黑帧由它引起。

ImageReceiver 路径不再作为当前生产方案：其公开封装丢弃 acquire fence，
`OH_NativeBuffer_Map` 本身也不提供 GPU fence 等待。当前生产方案使用
ConsumerSurface 的 fence 和 `MapWaitFence`，但模拟器内容仍未证明是完整桌面。

## 验证状态

- Core/HAR OHOS arm64 release 交叉构建：`.73` 到 `.84` 的相关版本成功。
- ArkTS default/debug `assembleApp`：上述版本成功。
- 三个提取自实际布局检查函数的回归用例通过：padded rows / last-pixel bounds、
  invalid geometry/stride/allocation、checked arithmetic overflow。
  这不是整仓 native runtime 测试。
- macOS `cargo check` 仍受本机缺失 Homebrew libyuv 限制。
- `MapWaitFence` + `CPU_READ | MEM_MMZ_CACHE` 的 `.84` 已安装并启动；
  指定模拟器的授权未完成，尚无完整帧证据。
- **官方 macOS 客户端可见变化画面和至少 2 分钟持续会话：尚未验收。**

## 联调约束

所有设备操作显式 `-t 127.0.0.1:5555`。不安装真机、不卸载、不清数据、不改包名。
源版本保持 `1.0.3 / 1000005`；仅 APFS 构建镜像递增测试版本以允许覆盖安装。
原生更改后必须运行 HAR 构建和 ArkTS `refresh-native-har.sh`，核对依赖原生库哈希。
不修改任何远端 Git 分支、PR 或 workflow。

后续验收需独立确认远端窗口归属和变化内容，不能把本地模拟器窗口、回调次数、
非零字节或编译成功当成远端视频通过。
