# 第十轮：本机90FPS目标、分段计量与安全限压

**2026-09-09，进行中：实现、目标测试、HiDPI修复及构建通过；已按用户授权转入真机，动态90FPS和整链零拷贝尚未验收。**

## 实测环境

- 三仓保持 `perf/zero-copy-high-fps` 和既有 dirty，未提交、推送或覆盖已安装 Mac App。
- Mac M4，arm64 RustDesk 1.4.9 (67)。主屏 `CGDisplayPixelsWide/High=2560×1440`、mode size/points=`2560×1440`、backingScaleFactor=2、mode pixels=`5120×2880`、165Hz；第二屏同样有2倍后备像素，60Hz。先前把 `system_profiler.spdisplays_resolution` 当作无歧义像素尺寸不准确，已用CoreGraphics/NSScreen实值纠正。
- 唯一目标 `127.0.0.1:5555`，API26；DMS活动模式 `3120×2080@60Hz`、RefreshRate=60。
- Emulator 26.0.0.300公开CLI/官方屏幕配置没有已确认的90/120Hz入口。90次解码/提交不等于90次实际显示。
- 旧安装包已完成正常本机认证，收到 `peer_info`/success，`remember=false`。凭据不进入源码、文档或记忆。
- 旧包曾显示 AV1、5 FPS；不是受控动态源，不能当作性能上限。

官方参考：[模拟器CLI](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)、[屏幕配置](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-customize-screen-configuration)、[期望帧率限制](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/displaysync-overview)。

## 实现范围

### Core

主要文件：`src/client/frame_rate_controller.rs`、`src/client.rs`、`src/client/io_loop.rs`、`src/ui_session_interface.rs`、`src/platform/ohos.rs`、`libs/scrap/src/common/codec.rs`、`libs/scrap/src/common/ohos/software_present.rs`。

- 既有显式FPS入口记录当前session的独立 `desired_fps`，不全局默认90。非custom质量不隐式改30；登录和排队中的正FPS消息按当前意图裁定；quality-only FPS=0不改写。
- 独立review发现首版撤掉持续解码过载限压的P1，已补 `safety_fps_cap`。用户意图90与安全上限分开，不伪保90。
- cap仅用纯decode/flush耗时、实际decoder outputs和持续队列：至少3个有效1–2.5秒窗口，窗内全部完成解码后的队列样本>1且能力不足才收紧，留10%余量，至少5秒冷却。连续10秒队列<=1且下一档有10%能力余量，每步最多+5FPS恢复。
- target/conversion/Busy/RTT不冒充纯codec耗时。缺测、静态、单尖峰不贸然限压。session取活动display最小cap；用户新FPS、旧代、结束有隔离。
- 保留有界队列、关键帧恢复、ACK和预测参考链处理，不伪造探测回复。

### 慢降质量仍为被动建议

纯控制器连续3个有效拥塞窗后建议每步<=5%下降，至少5秒冷却，稳定10秒缓升至用户质量上限。延迟判据是启发式，不是带宽实测。

**建议仅metadata，`qualityRecommendationApplied=false`，不发Mac、不保存质量配置。** 原版Mac独立ABR未修改，仍可自行降低FPS/ratio。本轮不是完整慢降码率策略部署。

`custom_fps`是请求上限；`custom_image_quality`间接影响码率/量化，不是精确kbps；`TestDelay.target_bitrate`是服务端遥测。

### HAR / ArkTS

- Core getter：`platform::ohos::session_frame_rate_snapshot(SessionID, display)`。
- HAR `sessionGetFrameRateSnapshot(sessionId, display):string` 使用Core session ID；释放HAR注册表锁后只读typed快照，无窗口FFI/像素/身份输出。
- 新 `FrameRateTelemetry.ets` 在活动、连接、可见、绑定匹配时最多每秒读一次。代次/意图变化、缺失、时间/计数倒退和过长缺测重建基线。
- `RustDeskFrameRate`仅记录白名单的期望/cap、窗口毫秒、差分速率、分段均值、队列、固定状态及未应用建议，无逐帧JSON或身份/像素。
- receivedPackets=交给软件decoder的压缩packet；decodedFrames=实际decoder输出，不证明独立源帧；submittedFrames=成功NativeWindow提交，不是物理显示。
- decode排除呈现/转换，但含输出枚举及lease元数据；targetNs含conversion，差值不能全叫fence。
- 主要覆盖VP8/VP9/AV1软件路径，硬件Surface不伪填软件计数；Stable不表示实测90。
- 不增加布局、RGB/PixelMap中转或像素轮询；R9路径保留。

## 已完成验证

- 独立review确认计时、计数、epoch/getter锁边界，过载P1已修复。
- 原两组Core host测试通过；同一完整生产纯模块交叉编译OHOS，在指定模拟器实际运行 **2 passed / 0 failed**。核对test result，目标程序已移除。
- ArkTS仅新增一组host边界测试，覆盖epoch/缺测/回退/速率/隐私/cap，不是设备ArkTS测试声明。
- 最终Core→HAR release联编通过；源码仓/APFS镜像均通过刷新脚本重装HAR，同步5个ArkTS相关文件。
- 最终App级 `assembleApp product=default buildMode=debug` 与 `default/release` 均通过；临时签名配置EXIT trap清理。
- 源码版本不改；镜像沿用 `1.0.3.88 / 10322965`。HAP strip库与本轮so全部23个SHF_ALLOC节一致。

## 首个R10计量版产物（已用于模拟器基线）

| 产物 | SHA-256 |
|---|---|
| HAR | `f2509d0a2a9e344178781e2389868c7896c70942d980a5627b028049ed495983` |
| HAR so | `92357e5eb44744dec339f04f99b9bce725b40a4fd5a5de39b7b3239204092671` |
| HAP内strip so | `dfe58647cef1aad541cc291e3d87dfbeb5f753d2437ba2b27c415ef0c919c46a` |
| default/debug HAP | `3ade1e5d9e0e403b517c3701ee1cb5e35e32a0f0cd8f1dce355a3b9a2287c12c` |
| default/release HAP | `f7c7198fa73b3db7fbf95d11c8ada6a88d763a8a0b939191602f4dd1b856865d` |

release HAP：`/Volumes/RustDeskBuildCache/arkts-workspace/entry/build/default/outputs/default/entry-default-signed.hap`；debug副本：`/tmp/resk-90-final-debug.hap`。

日志：`/tmp/resk-90-native-final.log`、`/tmp/resk-90-arkts-final-debug.log`、`/tmp/resk-90-arkts-final-release.log`。

## 首次动态图基线与分辨率纠正

已准备 `/tmp/resk-90-pattern/main.swift` 和 `resk-90-pattern`：主屏CVDisplayLink驱动图案/计数器，有界运行并合并积压。callback/layer update仅是测试源统计，不是RustDesk捕获或物理显示次数。

- 本轮 default/release HAP 已 `install -r` 成功并启动；查询 `debug=false`、`appProvisionType=debug`、`1.0.3.88/10322965`。重新正常认证成功，未记住密码。
- 已通过当前会话画质滑块请求90，Core日志确认 `desiredFps=90`，不是只看UI草稿。没有改变Mac显示模式。
- 动态源显式选主屏，CVDisplayLink callback/layer update大多约135–138次/秒；不是捕获/物理显示证明。有界程序已退出，exit0。
- 已保留 `/tmp/resk-90-av1-dynamic.log` 中启动10秒后94个有效窗口。AV1、4:2:0：decoded/submitted平均窗口值 **12.016 FPS**，范围7.722–13.592；decode每调用平均窗口值17.557ms、conversion每调用15.188ms、target含conversion每调用17.950ms；queue平均0.011，范围0–1；NoBuffer/Busy均0，安全cap均null。
- 上述耗时是**窗口均值再平均**，decode单位是decode/flush调用而非源帧；不能直接把它与target均值相加冒充端到端单帧延迟。后续日志新增按实际decoder output摊销的decode/target耗时，保留原单位。
- 后续延迟回读hilog时环形缓存已经覆盖早期窗口，因此没有宣称完整180秒全窗口统计；94窗原始分段日志仍保留。后续采用有界实时流式采集。
- 目前只能证明系统后备模式5K，尚不能据此推定原版二进制实际传输/解码尺寸。后续从既有software-present snapshot独立记录实际提交尺寸，不使用XComponent尺寸冒充。

### 用户纠正与Flutter对照

用户要求按实际显示分辨率，macOS HiDPI的最大后备像素不能直接当验收基线；先对照Flutter适配，未授权随意改变Mac系统显示模式。

只读核对当前Core checkout的Flutter链：`src/flutter.rs:613–636`同时投影原width、original_width、scaled_width；`model.dart`恢复远端scale，显示原始模式时比较 `width=originalWidth*scale`。viewport/DPR和input inverse是本地显示/坐标变换，`sessionSetSize`只改本地renderer。没有发现自动关闭Retina或capture-only缩小输出；Original/Fit local菜单是用户点击后发送真实系统分辨率命令。以上源码结论不冒称对已安装原版二进制做过插桩。

已继续核对OHOS生产路径：`platform/ohos.rs`实际创建同一`Session<FlutterHandler>`并原样转发同一JSON；不是只从HAR透传推断。`peer_info/sync_peer_info` helper只发 `scaled_width`，不发scaled_height或原始scale；高度需使用同一已确认比例推导。`switch_display`不带scale，Flutter保留该display既有scale。这不是OHOS专用adapter漏投影。

ArkTS确认需修：显示徽标/模式匹配混用原像素范围、无匹配假选第0项、切屏重建对象漏scaled字段、软件提交尺寸回写peer几何。HAR已透传scaled字段，不需新增native接口。修正保持实际显示、原像素范围、软件提交尺寸独立，不靠修改显示数字宣称降负载。

## HiDPI修复版与真机切换

HiDPI修复已完成：`RustDeskViewportModel.ets`中的纯函数消费width-only scaled_width，并在稀疏switch事件保留已知比例；`DisplaySelectorSheet.ets`分列显示尺寸/原像素范围，无匹配不假选首项；新增两条base字符串资源。软件提交尺寸使用独立只读model槽，切屏、peer更新、Surface/route失效及reset清理，不覆盖peer模式或fit/input。父在既有`RustDeskFrameRate`一秒日志新增lastSoftwareSubmittedWidth/Height以及按decoder output摊销的decode/target工作量，未知返回null。

原两组model/controller host测试18/18通过（其中新增6个边界case）；FrameRateTelemetry原一组host测试1/1通过。最终default/debug、default/release App级构建均通过，8个相关源文件同步并核对APFS镜像。Core/HAR未再改，HAR hash及HAP内原生库仍匹配上述最终原生build。

| HiDPI修复版 | SHA-256 |
|---|---|
| default/debug `/tmp/resk-90-hidpi-debug.hap` | `a15faadae1fe93765d4925c4889543ee68b58d17bf3dfee25a5319d11e97bb69` |
| default/release signed HAP | `4ac2bbd521221558e3dcaa73cb9dd10bb81104185180999d1e804dc4dd1a7053` |

构建日志：`/tmp/resk-90-hidpi-debug.log`、`/tmp/resk-90-hidpi-release.log`。安装路径仍为APFS镜像 `entry/build/default/outputs/default/entry-default-signed.hap`。

用户随后授权改用真机 `192.168.108.215:36237`：

- 模拟器本轮RustDesk进程已正常force-stop，旧亮屏任务已停止并确认进程退出，避免双客户端影响基线；未操作另一个模拟器。
- 新目标tconn成功，设备型号TGR-W10、API24，DMS当前约2800×1840、60Hz；这是当前模式，不宣称是硬件上限。
- 原版本1.0.3.25/10322902；HiDPI release HAP已保数据`install -r`成功、启动成功；复核为1.0.3.88/10322965、debug=false、appProvisionType=debug。未卸载、清数据、降级或绕签名。
- 使用已加载harmonyos skill的托管有限时wakeup，显式目标、10秒间隔、30分钟期限，按期结束后才重新启动。唤醒不是解锁/系统级常亮保证，最终回复前必须停止。
- HDC访问新设备经Mac的utun路由；不沿用模拟器连接的网络假设。真机未提供`ip`命令，HDC虽然exit0但输出not found，没有将其当作路由查询成功。
- 已核对目标框完整匹配本机地址，再通过正常UI连接。之后进入本包全屏XComponent及远程工具栏；没有出现密码模态，本次未输入或保存密码。不能从此推定发生了新的remember=false/ok=true提交，也没有读取既存凭据。

### 真机实际观测与计量缺口

- 远程工具栏协商codec为 **H265**；已通过现有滑块把目标120改为90，标签及Slider=90.000000，画质保持50，未改codec或Mac模式。之后Core一秒日志也出现208个desiredFps=90窗口，证明不只是UI草稿。
- 初次/设置时工具栏显示过6/2FPS、面板显示8FPS。这些是静态/单次UI值且口径不一致，**不是稳定动态图性能结论**，不能拿它们与模拟器AV1的连续动态12FPS直接比较。
- 真机`hilog.loggable.global=W`，先前INFO计量被过滤。仅对RustDeskFrameRate临时启用I，全局W未改；采集结束将该tag有效级别恢复W（保留一个非持久的显式W覆盖），未开启全局或身份日志。
- 使用`hdc ... shell hilog`进行有界实时采集，`/tmp/resk-90-real-hidpi-stream.log`共277个窗口（含开始读取的缓存窗口），desiredFps为120/90。所有software received/decoded/submitted计数为0，软件提交尺寸为null，状态missing_samples/observing。**这不是H265真实0FPS，而是R10详细计量未覆盖该路径。** 已核对Core `src/client.rs:3145–3160` 只把`take_software_frame_metrics()`结果记入该状态机。
- Mac动态图正常运行120秒，CVDisplayLink回调窗口均值约131.83Hz、范围127.35–143.98Hz；图案日志 `/tmp/resk-90-real-pattern.log`，最终写入时间18:15:18.799。不是捕获或物理呈现FPS。
- 后续UI dump时间18:16:14.968，**晚于动态图退出**。其工具栏0FPS、面板8FPS不得标为动态图期间采样；子任务报告中的“动态图期间”已在主验收更正。未得出真机动态FPS或真实视频像素尺寸。
- 当前主要缺口收敛为：H265异步解码实际输出、原生提交、输出格式/尺寸和硬件呈现分别计量；不得把enqueue耗时、包计数、软件计量的空样本或UI瞬时值当成硬解性能。先补这个可验收缺口，再优化或比较codec。
- 有界动态图和采集进程已正常退出，所有本轮亮屏任务已停止；本次父/子创建的真机及宿主UI dump已清理，保留仅含安全计量的日志。未主动熄屏或修改永久电源设置。

**尚无持续90或整链零拷贝达标声明。** 原版Mac内部复制、系统驱动/合成仍未验证，也未改变Mac系统显示模式。
