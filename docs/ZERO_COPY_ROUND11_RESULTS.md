# R11：原生 Surface 解码计量与真机基线

**2026-09-09，进行中。只读计量、独立审查、联编和保数据安装已通过；按用户新授权切Windows被控端，动态基线尚未验证。**

## 范围

- 三仓继续 `perf/zero-copy-high-fps`，保留既有改动。
- 唯一有屏目标：用户授权的 `192.168.108.215:36237`，TGR-W10/API24。
- 当前已安装R10 HiDPI default/release HAP，协商H265，目标90已由UI及Core确认。R10的软件计数不覆盖此路径；不能把零计数当作H265的0FPS。前轮证据见 `ZERO_COPY_ROUND10_RESULTS.md`。
- 本轮只补计量、构建和有效动态图时间窗口，不改协议/codec选择/码率策略，不改变Mac系统显示模式，不增加任何像素读回、搬运或CPU fallback。
- 计量不证明硬件实现、物理上屏或整链零拷贝。`native_surface`描述接口路径，不是“硬件实现已验证”。

## 源码与API审查结论

Core `libs/scrap/src/common/ohos/avcodec.rs` 的实际事件须分开记录：

1. `OH_VideoDecoder_PushInputBuffer` 返回成功：原生输入接受，不是已解码。
2. `on_decoder_new_output_buffer`：异步输出回调；包括可能的EOS/config/未知输出，不无条件称作图像帧。
3. `OH_VideoDecoder_RenderOutputBuffer` 返回成功：归还输出并通知Surface渲染，不是物理呈现完成。

当前Surface worker不检查输出flags即Render。本轮只记录真实行为，不顺便改变其调度或错误处理。媒体输出口径单独分类：metadata有效、普通/SYNC flags可计媒体输出；EOS、CODEC_DATA、其他/未知及metadata失败分开。不能增加`size > 0`判断，也不能通过CPU地址判断Surface图像是否有效。

旧`take_surface_rendered_frame()`把多个render_count增量折为一次bool，且上层只在处理新输入批次时消费；异步worker本身不等下一输入。新计量必须累计真实事件并由独立周期读取，不能沿用bool作为实际输出帧数。

尺寸来自真实输出格式，优先`VIDEO_PIC_WIDTH/HEIGHT`（裁剪后可见尺寸）；配置width/height、stride、peer模式和XComponent矩形不得补成actual。`onStreamChanged`的format仅在回调内借用，复制标量但不Destroy；`GetOutputDescription`返回对象需要Destroy。格式通知与已排队输出逐帧的严格对应不保证，尺寸只称最新观察到的输出尺寸。

回调/worker不继承direct_render的TLS；decoder创建时捕获绑定代际，旧decoder/Surface的晚回调不能记入新scope。现有Stop/Destroy失败处理以及新旧decoder重叠销毁的系统风险没有因新增计量自动解决。

官方依据（本机SDK声明及已加载harmonyos资料核对）：

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/video-decoding
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-avcodec-videodecoder-h
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/capi-native-avbuffer-h

## 待验收

- [x] Core原生计数/代际隔离与最小边界测试（2个pure host tests）。
- [x] HAR薄getter和ArkTS白名单窗口，原生/软件口径分离（既有测试组2 tests/245 assertions及host strict检查）。
- [x] 标准HAR构建、源仓及镜像refresh脚本、default debug/release App构建、hash核对。
- [x] 同一真机保数据覆盖并启动，查询debug=false、appProvisionType=debug、1.0.3.88/10322965。
- [ ] 全任务周期唤醒维护、纯计量tag设置与采样结束后恢复。
- [ ] 日志与Mac合成动态图同一时间窗口的动态基线，真实输出尺寸/输出/提交分别报告。
- [ ] 采集/动态图/亮屏任务停止、临时身份数据清理，明确仍未验证的物理呈现和零拷贝范围。

## 联编产物

Core/HAR标准`scripts/build-har.sh`通过；新getter、声明、arm64-only及C++ runtime已核对。源仓与APFS镜像均执行refresh脚本重装依赖。App级default/debug及default/release通过，临时签名配置由EXIT trap清理。源仓App版本不改，APFS镜像保持既有保数据覆盖版本`1.0.3.88 / 10322965`，未套用CI版本算法。两份HAP内strip库的23个SHF_ALLOC节均与本轮HAR原生库一致。

| 产物 | SHA-256 |
|---|---|
| HAR | `e40993cd1a1c193fd607984976506de238a4ccbb326f5734e5f7033e536a2b15` |
| HAR native so | `d2b99a6d58c2ba61e2ad2ec56645d4946608e4f77b0268d24e0d2e6eb3ea3629` |
| `/tmp/resk-r11-debug.hap` | `b73bbc9242708f14575d3d75eeb4c79c27c47e70a965ebdf8e0683e08eead831` |
| default/release signed HAP | `7141a6cbf0fa70082cedb10ac03616975605342f0ff3240276737c1ebe9991f2` |

release路径：`/Volumes/RustDeskBuildCache/arkts-workspace/entry/build/default/outputs/default/entry-default-signed.hap`。构建日志：`/tmp/resk-r11-har-build.log`、`/tmp/resk-r11-debug.log`、`/tmp/resk-r11-release.log`。

## 用户纠正的亮屏生命周期

用户明确要求周期wakeup贯穿整个未完成联调任务，不能因阶段性回复、goal轮切换、编译或等待而停止；仅整体完成、取消、切目标或明确息屏/功耗测试时停用。此要求覆盖skill每次final前停止的默认规则。保持单个受管任务，期限临近及时续期，不改永久电源设置。

本轮重新启动10秒周期任务后，已通过`hidumper -s 3301 -a '-s'`确认AWAKE/SHELL及原有ScreenOffTime=600000ms。裸`hidumper -s 3301 -a`缺参数，即使HDC exit0也不是成功状态证据。前一轮按默认规则停了任务，本轮初始仅静态构建没有运行wakeup；没有把wakeup成功当作解锁/系统级常亮保证。

随后捕获到真实失败：原受管任务在HAP安装时段连续3次5秒HDC命令超时后按默认规则退出，exit1；安装本身成功。单独wakeup再次成功后，恢复唯一10秒周期任务，把单命令超时提高为15秒、期限7200秒。不把这次可观测超时失败继续解释成“只是上轮主动停止”。正在补宿主受管续期维护，不能借此更改永久设置或自动授权。

## 设备初步证据与目标切换

- 新包已实际输出`RustDeskNativeRate`：初始Mac正常连接期间，codec=h265，PIC实际尺寸为**5120×2880**，输入/合格媒体输出/Render成功约13–15每秒，queue=0、highWater=1、错误计数=0。只是静态/操作期间短窗，不是动态性能上限，也不证明独立视觉帧或物理上屏。
- UI正常设置90后曾显示AV1并回首页，随后又有远程页及H265输出；操作员未手动改codec。这段没有已验证的原因，不推断为原生计量异常或90FPS瓶颈。
- 准备期间的日志含多个连接/输出尺寸阶段，后段有2560×1440及约50–58输出/秒。必须结合当前连接目标与时间边界分别归属，**不能把整个缓存日志当单一Mac或Windows动态基线**。
- 用户新增授权：被控端可改用Windows `192.168.108.199`，鸿蒙HDC目标不变。正通过正常UI明确结束旧会话并核对新target，遇认证模态由用户处理，不复用Mac密码。
- 本轮尚未运行Mac合成动态图。`/tmp/resk-r11-benchmark.py`只用于它实际启动的本机Mac源，**不能拿该源给Windows验收造动态条件**；Windows需对应的运动内容与采样窗口。

额外只读核查：旧bool派生的墙钟UI FPS与处理耗时capacity是两个口径，后者在legacy模式确实可经custom_fps影响发送端；但当前OHOS有desired_fps时已门控旧auto-FPS并在wire边界裁定，所以不能直接把旧bool认定为90意图被覆盖的原因。旧capacity仍影响refresh阈值，作为未修改的诊断点；未发现旧bool直接写入TestDelay、ACK或码率字段。证据属于当前checkout，不冒称远端原版二进制已插桩。

### Windows归属确认后的观察

独立UI任务在19:18:53与19:21:47（+08）核对当前唯一会话副标题完整匹配授权Windows目标（text/originalText一致），因此采用“已经是Windows则保留”分支，未断开该会话，也不宣称刚完成新连接/密码提交。当前H265、目标90、质量50；二级画质面板关闭，远程前台，未改codec/系统分辨率。该UI任务的宿主/设备临时dump已清理。

`/tmp/resk-r11-windows-preflight.log`中19:21:59–19:22:02的四个原生窗口同时证实：H265、Core desiredFps=90、PIC实际2560×1440；媒体输出/原生Render接受为59.98、60.158、59.113、60.964每秒，decoderErrors=0、outputQueueDepth=0。**这是几秒现有画面的观察，不是稳定90、不证明物理显示或持续动态源。**下一步需确认Windows源刷新率和对应运动内容，不能把约60的观察值先认定为解码器上限。

### 全任务唤醒维护已启动

`/tmp/resk-awake-session.py`已创建并通过静态/参数检查；受管session38启动确认`adopt-monitoring; no-new-waker`，只监控本会话现有base session35/PID59352，没有第二个并发waker。旧base自然退出后，独立健康检查通过才续官方30分钟轮；短暂超时/离线退避重试，权限拒绝退出并报告，不自动授权/tconn。仅启动/adopt已验证，尚未实测完整到期交接/拒绝路径，不声称系统级常亮。

整体任务完成/取消等完整收尾边界才停；若仍在adopt阶段，需要同时通过session38及原session35托管句柄停止。wrapper不按裸数字PID杀adopt进程，避免PID复用；自己启动的子进程则负责定点清理。阶段汇报不停止维护。
