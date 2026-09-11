# R13：Windows更新后的低FPS读数与高画面延迟

2026-09-09，进行中。**尚未修复真实高延迟，也未验收稳定90FPS/严格零拷贝。**

## 用户反馈与交付基线

- 用户自行换上Windows `e3206221b`，反馈统计栏容易从55降至22，实际延迟也很高；“可能网络问题”是用户假设，不是已确认根因。
- 用户确认该读数来自鸿蒙远控统计栏；确认采样分钟内显示20–30且高延迟。
- Windows CI `34354593382`已全成功，artifact `10106516105`，RustDesk 1.4.9 / EXE 1.4.9.67。NAS交付的ZIP SHA-256为`c616d73a4dbcbaec337ffe2f57e92dd07362b291977c343dd8abd7668b901403`；完整性、94文件/16 AMD64 PE、源码/overlay摘要已校验。不是新一轮Windows构建，未重跑该CI。
- 该版本只改硬件编码器FPS初始化提示，没有改变发送端动态QoS/背压。用户称已更新；本轮未独立读取Windows实际加载模块的路径/哈希。

## 真机观察（不混淆口径）

仅读取授权真机的专用`RustDeskNativeRate`白名单，未改FPS/画质/分辨率/网络。当前原生路径为`native_surface`、H265、实际输出2560×1440、desiredFps=120；120是当前请求，不沿用前轮90，也不表示吞吐。

宿主65秒受管采集后保留末60个有效窗口：设备日志时间22:22:15.461–22:23:15.426。

| 指标（每秒） | 最小 | 最大 | 算术均值 |
|---|---:|---:|---:|
| 原生输入接受 | 43.350 | 74.803 | 59.840 |
| 媒体输出buffer | 50.246 | 63.976 | 59.840 |
| Render API接受 | 51.232 | 63.976 | 59.840 |
| 输入缓冲等待事件 | 0 | 16.782 | 13.367 |

- outputQueueDepth全部为0，高水位为4；decoderErrors/renderFailures/inputTimeouts全部为0。没有媒体输出低于40/s的窗口。
- 队列0不包括正在Render的buffer、Surface/compositor、AVCodec内部、压缩待解消息及传输缓冲；等待事件次数不等于等待毫秒。
- 以上既不是独立画面数，也不是物理呈现FPS。稳定吞吐不能排除固定旧帧积压。
- 白名单样本在`/Volumes/dsh-rustdesk-build/windows-high-fps/round13/native-rate-20260909-222315.jsonl`。只保存枚举/数值和日志时间，无身份、画面、原始PTS或完整事件。
- 后续UI layout在内存中只投影text/originalText的数值/单位，实际读到`H265`、`27 FPS`、`7 ms`；原始device临时layout已删除，未保存到NAS。它不是与上述每个1秒窗口严格同步的物理延迟测量。
- 真机到授权Windows的12个ICMP请求无回复。视频会话仍在运行，Windows可能过滤ICMP；**不能将其报告为RustDesk流100%丢包或网络根因**。
- `RustDeskNativeRate`临时I已恢复W；尝试`RustDeskFrameRate`无输出后也恢复W，全局级别未改。

## 已确认的统计缺陷，未作为性能修复

Core `codec_adapter`对一个EncodedVideoFrames中的全部packet提交后，仅检查一次`take_surface_rendered_frame()`。异步worker每次Render成功累加，但该getter将任意正增量折为一个bool；上层只加一次frame_count，再经QualityStatus、ArkTS qualityTelemetry进入统计栏。

因此这个native栏值是“输入消息驱动poll观察到至少一次Render进展的次数”，不是输出/Render数。多个异步输出会少计，最后输入之后才完成的异步输出也可能没有下一次poll补计。已有独立native快照不会因缺少下一输入而漏掉同代仍存活的输出。

不得通过重复video_callback补次数或直接换高数字宣称卡顿已修复。界面口径修正是独立问题，当前优先定位用户确认的真实高延迟。

## 剩余候选及最小下一步

1. Windows已交付QoS仍快速降低FPS、慢恢复，并有延时分档突变、未完成探测污染等候选；未采到其状态时间线，不能直接归因它。
2. 当前native路径已经设置desired=120；旧客户端auto-FPS发包分支按本地代码应被门控，软件安全cap也不能直接解释native路径。保留是否实际安装该源码的边界。
3. 普通压缩VideoFrame队列容量120；含关键帧消息直接走mpsc，当前group及其剩余packet也不在queueLen中。固定backlog允许输出持续60而画面始终落后。
4. HAR现有只读FrameRateSnapshot.queueLen在native路径仍更新，但此前ArkTS只把该快照作为intent，不在native日志投影队列。本轮已补nullable `lastPostHandleQueueLen`白名单字段：最近一次处理完成后的ArrayQueue消息数，采样年龄未知，不冒充实时队列/时延；不改控制策略、丢帧、Core/HAR或FPS显示。
5. 现有接口没有本地收消息→处理/Push的驻留耗时，更没有端到端画面年龄。若队列投影仍不能定位，再增加必要的本地聚合age；不能用当前合成每packet +1的微秒PTS反推网络时延或改为不明时基调度。

## 生命周期与范围

新宿主下旧任务句柄已不可用；仅投影自有脚本进程确认无存活唤醒器后，重新启动唯一受管maintenance（当前exec session1），每30分钟续官方10秒wakeup周期。阶段回复/构建/等待不停止；最终整体完成/取消/切目标/息屏测试才收尾，不改永久电源。其它已连接模拟器未操作。

三仓保持`perf/zero-copy-high-fps`，所有既有dirty保留；新增缓存/采集/构建产物NAS。纯诊断尚不构成性能修复、零拷贝或完成验收。

## 只读补丁、测试和安装

- 服务仅增加nullable字段、边界注释和running分支的一次安全投影；继续复用已有intent读取，不新增getter、setter、回调或像素操作。warmup、无效intent、断代、unavailable均为null；有效0和未知严格区分。
- 测试实际已在`entry/src/ohosTest/ets/test/FrameRateTelemetry.test.ets`，没有另建NativeDecoderTelemetry测试文件或新增测试组。子任务中断前已修改两文件；主会话收回后修正了换行`as`造成的TS1434，并重新验证。
- NAS `round13/host-tests`使用SDK TypeScript严格编译和最小Hypium断言宿主适配执行既有测试：**2 tests / 273 assertions通过**。这是pure host验证，不冒称真机Hypium执行。
- `assembleApp product=default buildMode=debug --no-daemon --no-incremental`通过（无签名编译检查，约9.9秒）；随后default/release签名App构建通过。日志为同NAS目录`arkts-debug-build.log`和`arkts-release-build.log`。
- 镜像只同步服务和测试两文件，源仓版本不改，镜像保留1.0.3.88/10322965供保数据覆盖；target/compatible均API23，Java17。源仓及镜像HAR均仍为`e40993cd1a1c193fd607984976506de238a4ccbb326f5734e5f7033e536a2b15`，无Core/HAR改动。
- Hvigor用户缓存、npm缓存、XDG缓存和TMP均明确置于已验证NAS-backed APFS；临时签名配置由标准prepare脚本生成，EXIT清理后已核对不存在，未输出材料内容。
- 新HAP：`/Volumes/dsh-rustdesk-build/windows-high-fps/round13/resk-r13-default-release.hap`，SHA-256 **`e5777f368c631dc0e67736bb8aaf7c1340cf61b5c488aeb445a57a5e44834848`**。时间戳、ZIP完整性及modules.abc中新增字段标记均已验证。
- 授权真机`install -r`明确返回`install bundle successfully`；`aa start`明确成功；随后bm白名单实际返回versionName=1.0.3.88、versionCode=10322965、debug=false、appProvisionType=debug。未卸载或清数据、未改Windows安装。
- **安装不是延迟修复。** 新队列样本见下。

## 新包120意图复测（2026-09-10）

用户确认重新连接Windows并保持动态图后，受管65秒采样丢弃初始2秒缓存，得到**62个live running窗口**，设备时间00:09:53.276–00:10:54.954。仍为H265、实际2560×1440、desired120。

- 原生媒体输出/Render接受平均49.177/s，最低7.913，最高65.347；输入平均49.366/s。不是此前稳定60的窗口，不应用前轮数据覆盖本轮真实低吞吐。
- 新增`lastPostHandleQueueLen`最高**117**、均值21.532；62窗有25窗大于零。native outputQueue仍全0、highWater1、无timeout/error/render failure。
- 00:10:29–36，处理后压缩队列依次3、19、35、54、67、83、101、117，而输出约60/s；00:10:37归0，随后重复增长/归0。证明曾有大量待解消息，但不把117消息直接换算成秒，也不把归0认定为解码追平。
- 早段输出约8→10→12→14…，约每秒增加2，队列为0；到约60之后积压出现。与发送端既有QoS慢恢复形状一致，未采其状态，不能认定逐点因果。
- 数据：`/Volumes/dsh-rustdesk-build/windows-high-fps/round13/queue-rate-20260910-001055.jsonl`，脚本`sample-native-queue.py`。采样结束tag恢复W。

独立只读源码复核：普通队列full仅force_push丢一个旧group并请求refresh，不会直接清零；发refresh会置discard_queue，worker丢弃已排队interframe直到处理keyframe恢复。另有legacy容量估计触发的周期refresh，desired优先只门控旧FPS写入、未门控这段refresh。因此锯齿与refresh/discard机制兼容，但没有reset事件，不能证明每次归0的具体触发。TestDelay由IO线程回传，绕过视频worker，所以低控制RTT不约束此队列时延。

原生侧已有LOW_LATENCY=1，但不支持的codec可能无错误地用普通模式；Configure成功不证明低延迟生效。decoder没有FRAME_RATE设置，而encoder有；缺省锁60未获官方证据。NativeWindow没有文档支持的SET_FRAME_RATE操作，也没有公开operatingRate可随意加入。输入等待及Render目前只有次数，没有耗时/in-flight；native queue在调用Render之前已pop，0不排除正在阻塞的Render或Surface/fence持有缓冲。

另一次DMS只读数字投影得到2800×1840及一处refreshRate60；未分类为当前属性/支持模式前不作为显示瓶颈证明，未改系统显示模式。后续此类命令必须内存白名单，因为DMS help也会先打印非任务相关进程信息；未把该原始输出保存到文档或NAS。

### 临时60对照完成，已恢复120

用户明确允许一分钟120→60对照，不作为降规格验收。自动化未读到滑块时没有盲点旧坐标，由用户在既有UI设60并确认收起面板/保持同类动态图；不改分辨率、画质、系统刷新率或参考帧处理策略。

同一脚本取得62个live running窗（00:24:52.284–00:25:53.943）：desired全部60，H265/2560×1440不变。原生输入/输出/Render接受平均58.381/s，媒体输出最小50.445、最大66.206；**lastPostHandleQueueLen、inputWaits及所有错误/超时均全0**。输入平均737471bytes/s，高于此前120样本；仍不把不同时间/图案的字节率作严格网络因果试验。数据为`queue-rate-20260910-002554.jsonl`。

用户随后恢复120，主会话实际读取最后三个native窗desired120、输出59.524/60.277/58.185，队列**72/120/14**，确认不是只口头恢复，且积压重新出现。此恢复检查只是三窗，不冒称第三个完整一分钟样本。用户回答“没留意延迟差异”，因此只能说队列和等待指标明显改善，**不能声称主观/端到端延迟已改善**。临时I已再次恢复W，全部UI临时layout已删除。

### 能力查询未执行成功及下一步

在NAS编译了15KB ARM64 PIE只读`codec-capability-probe.c`，仅查询系统推荐能力、1440p帧率范围、60/90/120支持和低延迟能力，不创建decoder/Surface、不送媒体或读像素；所用接口官方起始API10/12。编译工具链的default headers是API26，不能冒充已验证API23 SDK实装；这里只使用已核对的早期公开接口，未改变App的API23产品配置。

探针送到授权真机后被shell明确`Permission denied`拒绝执行（HDC仍exit0），**没有取得任何能力结果**。未改系统执行策略、未换loader/路径绕过，自己的临时设备可执行文件已删除。NAS保留源码和编译产物，不把编译成功当成查询成功。

当前尚不足以安全改性能策略：120比60多出的输入会形成明显排队，但native消费约60的具体限速位置未量到。下一步仅在正式Core计量路径补真实condvar wait、PushInputBuffer、RenderOutputBuffer的累计调用/耗时、代内高水位和render-in-flight，再经既有HAR/ArkTS白名单投影；不改timeout、锁、参考帧/refresh、codec配置或FPS策略。已给agent `96bcaea4-4585-4a6d-8240-1f144fa5ab84`限定Core实现权限，尚未完成、联编或部署该下一步。**R13安装包仍是前述只读队列版本，实际性能问题未宣称修复。**

## R14 原生调用耗时定位（2026-09-10）

Core `native_decoder_metrics.rs`和`avcodec.rs`为真实阻塞wait、`PushInputBuffer`及`RenderOutputBuffer`增加generation/lease隔离的单调耗时：completed calls/ns饱和累计（失败返回也计），maxNs是decoder代内高水位，renderInFlight是0/1 gauge。立即取得已有input buffer不算wait；不改timeout/predicate/锁、错误传播、PTS、参考帧、像素或零拷贝Surface路径。

HAR getter显式投影10个独立snapshot字段，不能错误地依赖旧17项counter zip；后者保持17项有限白名单。ArkTS对全部新字段做非负safe-integer验证，renderInFlight额外限制0/1；窗口日志给completed/avg/high-water，明确跨窗调用在完成窗记全部耗时，不能叫busy百分比、严格窗口占用或帧龄。producer→getter→consumer真实宿主投影和原两组测试均通过；后者为**2 tests / 703 assertions**，证据在`/Volumes/dsh-rustdesk-build/windows-high-fps/round14/host-tests/`。

完整标准OHOS release HAR交叉编译在NAS镜像成功，第一次offline因Git子模块不完整失败，第二次网络遇GitHub SSL中断；精确导入本机已存在的libpng固定commit到NAS Cargo object cache后第三次成功（7m19s），不是通过关闭校验或换revision。HAR `/Volumes/dsh-rustdesk-build/windows-high-fps/round14/rustdesk-ohrs-r14.har` SHA-256 `0a56d1efa710f5702ab903df73914b2e08abb6f864f84f7d0ecdc6bf907311b3`；标准refresh脚本重建根/entry依赖，已核验oh_modules中的native so与HAR内so同为`0cda82c8c67c4e3f3399d99cf1fd21c3aea730807cb1f63d8a4fe2ea283bfeea`。

镜像保留1.0.3.88/10322965与API23；NAS缓存运行`assembleApp default/debug`无签名编译检查及default/release调试Profile签名构建均成功，临时签名目录已清理。HAP `/Volumes/dsh-rustdesk-build/windows-high-fps/round14/resk-r14-default-release.hap` SHA-256 `c81f04fc27441ffd8ad063814b89e329221e48fe2286c1616dd408c16b2bb80b`，ZIP完整性、新native JSON键与ArkTS ABC投影标记均验证。授权真机保数据install-r、Ability启动成功，bm白名单核对versionName=1.0.3.88、versionCode=10322965、debug=false、appProvisionType=debug；未卸载或清数据。

安装后用户授权由主会话代点连接；只点击已保留授权Windows目标的enabled连接按钮，不重写目标/模式。R14脚本取得**63个live running窗口**（01:57:29.898–01:58:32.592），全部desired120、H265、实际2560×1440：

- 输入接受均59.693/s，媒体输出均59.647/s，Render接受均59.647/s；无timeout、decoder error或Render failure。
- 压缩队列53/63窗非零，最高120、均49.349；native outputQueue始终0、high-water2。
- 真正input-buffer wait平均累计**737.225ms/窗**，单次wait平均**56.778ms**、代内高水**89.732ms**；旧`inputWaits`平均12.479/s。
- `PushInputBuffer`累计86.124ms/窗、单次平均1.427ms、高水11.582ms；`RenderOutputBuffer`累计75.692ms/窗、单次平均1.254ms、高水11.875ms；renderInFlight仅4/63个采样窗为1。

数据`/Volumes/dsh-rustdesk-build/windows-high-fps/round14/native-timing-20260910-015832.jsonl`。这些是调用完成窗口统计，不是physical FPS、presentation时间或端到端帧龄。证据已将主瓶颈收敛为**AVCodec归还可复用输入buffer的节奏**，不是Rust worker在Push或Render FFI调用本身长时间阻塞。

下一步限定为公开decoder Configure `OH_MD_KEY_FRAME_RATE`的最小A/B：将Core已有、已验证1..=120的session desired FPS，经HAR唯一owner/direct-render lookup传入decoder；只有Some时在Configure前用double设置，key缺失或setter false继续原路径，并记录无身份config结果。禁止默认为120、SetParameter/私有operatingRate、VRR、NativeWindow/空VSync、系统显示模式、PTS/timeout/队列/参考帧/像素改动。该A/B尚在实现，**本节R14仍是诊断包，不是性能修复完成**。

A/B结果判定在构建前固定：必须先由init日志证实requested=120且公开key setter返回true，并取得至少40个同条件running窗、0 timeout/error/render failure。仅“配置成功”不算性能修复；至少要让媒体输出均值从R14的59.647/s升至**70/s以上**，同时input wait完成耗时或压缩队列均值有实质下降，才保留为有效性能改进。若仍约60且积压相当，则按无效假设处理，不用配置返回成功冒充修复，也不声称physical 70/120FPS。

### FRAME_RATE A/B结果：否决并精确回退

最小A/B只临时改Core `DirectRenderTarget`/decoder Configure和HAR唯一owner lookup，不改ArkTS、运行时SetParameter、像素/PTS/队列/参考帧；完整OHOS HAR联编、标准refresh和default/release签名构建成功。临时HAR SHA-256 `f6450e1d1c5475a8f4d4f76ba9fdb7c0e5625658dc7c62ebab5bcec86cb8b302`，HAP `/Volumes/dsh-rustdesk-build/windows-high-fps/round14/resk-fps-hint-default-release.hap` SHA-256 `5358b0e328784efe8e79133e1eaf4aeaecce6e6b2266a930ae741e1d336983eb`。真机保数据安装后，主会话按fresh layout确认授权目标和enabled连接按钮再点击；没有盲点旧坐标。

由于原`RustDeskNative`阈值没有保留INFO，临时设I后用正确`aa force-stop <bundle>`重建decoder（先误用`-b`被设备明确拒绝，未造成stop或数据变化）；配置日志实际为H265 2560×1440、`frame_rate_requested=Some(120)`、`frame_rate_key_available=true`、`frame_rate_set=true`、原low-latency key/set也true。随后tag恢复W。setter成功只证明format接受。

同一65秒脚本取得63个running窗（02:21:25.335–02:22:28.032），desired全120：媒体输出59.820/s、input wait累计728.260ms/窗、单次56.881ms、压缩队列均53.032/max120；无timeout/error/render failure。预先固定的比较脚本给出：输出仅**+0.291%**，wait累计-1.216%、wait单次+0.182%、队列均值反而**+7.462%**，`accepted=false`并以非零退出。数据`native-timing-20260910-022227.jsonl`、判定脚本`compare-fps-hint.py`。

因此公开FRAME_RATE hint对该设备本路径**无可测吞吐效果**，未达到70/s门槛，不是修复。三个临时产品源码hunk已按A/B前备份逐字`cmp`相等确认回退，Core/HAR `diff --check`通过；不把该helper/test留进产品。真机随后保数据覆盖恢复本节前的纯R14计量HAP并成功启动，`RustDeskNativeRate`与`RustDeskNative`均恢复W，临时layout清理。临时A/B包和数据只作为否定证据保存在NAS，不作为交付或当前安装基线。

剩余结论更窄：当前公开decoder配置已不能解除约60/s的输入buffer回收节奏。NativeXComponent确有API11 `OH_NativeXComponent_SetExpectedFrameRateRange`，但当前HAR仅持有SurfaceId而没有`OH_NativeXComponent*`，文档也没有证明range-only、不注册frame callback就会投票，或它会改变AVCodec buffer回收；不能把SurfaceId/NativeWindow强转成组件指针，也不能加空回调假驱动。下一轮若继续，应优先在合法XComponent句柄桥接/帧率投票与Surface消费边界上做可撤销验证，或取得平台能力/trace证据；不能再重复FRAME_RATE配置，也不能用降到60或周期discard掩盖积压。

## R15/最终轮：XComponent NodeHandle期望帧率A/B预注册

最新官方API20路径消除了上一段“只有SurfaceId”的前提：声明式XComponent可在`.onAttach`中通过`UIContext.getAttachedFrameNodeById`取得ArkTS `FrameNode`，Native侧用`OH_ArkUI_GetNodeHandleFromNapiValue`合法取得`ArkUI_NodeHandle`，再调用独立的`OH_ArkUI_XComponent_SetExpectedFrameRateRange`。两个符号均在API23 NDK `libace_ndk.z.so`实符号中；接口与后续`RegisterOnFrameCallback`是分立API，不需要添加空帧回调、VSync/DisplaySync或接管Surface生命周期，也不需要持久化句柄。官方XComponent指南明确说明Surface消费链为系统渲染侧Acquire/Release，因而该投票是当前唯一直接针对Surface/XComponent调度边界、同时不接触像素的最小可撤销假设。

A/B改动边界预先固定：HAR只把当前attached `FrameNode`同步转换成handle并调用一次range setter，输入限定1..=120、min<=expected<=max，handle不保存；ArkTS只在custom质量且已有1..=120的持久desired时请求`min=max=expected`，当前条件应为120，不默认120。SurfaceId/controller/session binding、decoder、PTS、队列、参考帧、像素和零拷贝路径不变。验证必须先见`handleCode=0,setCode=0,expected=120`，然后同脚本至少40个running窗、0错误；继续沿用已登记门槛：媒体输出>70/s，并且input wait累计或压缩队列均值低于R14基线75%。setter成功但仍约60时仍按无效假设精确回退，不作为修复保留。

### XComponent期望帧率A/B结果：接口未接受，否决并回退

完整HAR联编、ArkTS default/debug检查和default/release调试Profile签名构建均成功；所有尝试都只操作frame-rate range元数据，不注册frame callback、不接触Surface像素、不增加readback/转换或fallback。第一条API20路径从声明式XComponent的attached `FrameNode`取得handle实际返回`handleCode=0`，但`OH_ArkUI_XComponent_SetExpectedFrameRateRange`对`120/120/120`和Surface创建后的`0/120/120`均返回401。RenderService只读投影同时确认设备同分辨率支持60/30/90/120/144，当前active为60，因此不能把401归因于物理面板只支持60。

随后验证声明式XComponent的API11指针路径：`XComponentController.getXComponentContext()`直接传NAPI时`napi_unwrap`返回2；增加`libraryname/onLoad`后可得到`unwrapCode=0`。后续源码复核纠正：unwrap成功不验证返回指针类型，因此不足以证明拿到了合法的`OH_NativeXComponent*`。在onLoad及Surface/context双方就绪门控后调用`OH_NativeXComponent_SetExpectedFrameRateRange(0/120/120)`仍返回`OH_NATIVEXCOMPONENT_RESULT_BAD_PARAMETER=-1`。没有任何setter成功证据，不能进入“accepted treatment”的性能归因，也不能由此推导平台拒绝所有合法调用入口。

为防止短样本误判，仍保存了末65个running窗口：desired120、H265、2560×1440，媒体输出均59.885/s，input wait累计均738.305ms/窗、单次均57.636ms，处理后压缩队列均56.662、最高120，Render/decoder错误均0。相对纯R14基线分别为输出+0.400%、wait累计+0.146%、队列+14.818%；既未超过70/s，也没有任一等待/队列指标下降25%，固定性能门失败。

失败实验源码已从Core/HAR/ArkTS产品路径精确移除，三仓`diff --check`通过；NAS镜像用标准refresh脚本恢复`rustdesk-ohrs-r14.har`。授权真机保数据覆盖恢复纯R14计量HAP并成功启动，当前版本仍为1.0.3.88/10322965、debug=false、appProvisionType=debug。R14 HAP SHA-256仍为`c81f04fc27441ffd8ad063814b89e329221e48fe2286c1616dd408c16b2bb80b`。

否定证据位于`/Volumes/dsh-rustdesk-build/windows-high-fps/round14/xcomponent-rate-vote/`：`result-summary.json`、`rejected-vote-live-windows.json`、`render-service-rate-projection.json`、各HAR/HAP/构建日志及`final-attempt-combined.patch`。这些包仅供否定复现，不是当前安装基线。

剩余最小高价值判别不再是重复decoder/XComponent hint：设备明确支持120/144但active mode为60，而AVCodec输入buffer回收节奏仍约60。下一步应在不改系统设置的前提下先取得平台调度/trace证据，或由用户手动把系统屏幕刷新率切至高刷新后，以纯R14包做同样65窗对照；若只改变active display mode就使input wait/output跨过门槛，才能确认系统显示策略是buffer回收上限。Agent不得擅自修改永久显示设置，也不能用降到60、丢帧、空frame callback或伪统计代替严格零拷贝高帧率验收。

### 用户手动高刷新对照：active未保持120，性能门仍失败

用户按提示手动把系统屏幕刷新率切到高刷新；Agent没有写系统设置。RenderService在采样前实际确认active mode从60变为120，支持档仍为60/30/90/120/144。随后使用已恢复的纯R14包、同一Windows目标和custom120采样62个running窗；采样后再次查询时active mode已经被系统动态回落到60，因此该段不是恒定120Hz处理，不能把全段归因于高刷新。

该62窗仍为H265、2560×1440、desired120：输入接受均51.693/s，媒体输出/Render接受均51.693/s，input wait累计均438.964ms/窗，处理后压缩队列均25.339、最高112；无timeout、decoder error或Render failure。相对纯R14，wait累计下降40.457%、队列下降48.654%，但输入本身也下降13.401%，媒体输出下降13.335%且只有51.693/s，未达到>70/s硬门槛。只能说“系统短时120期间曾出现更低wait/queue”的相关性，不能宣称吞吐或真实延迟已修复。

数据为`/Volumes/dsh-rustdesk-build/windows-high-fps/round14/xcomponent-rate-vote/r14-system-high-refresh-sample.jsonl`，SHA-256 `796135b2bf85ad05f1b5321c5542ba025e84c397ae958495c686e6c2d6d86207`；`result-summary.json`已纳入采样前120/采样后60的模式边界。为补齐NativeXComponent正数min边界，复用既有min=1实验HAP做了干净进程检查，但没有产生新投票日志；会话本身正常running/desired120，未调用不等于setter成功或失败，未据此改写API结论。真机最后再次保数据恢复纯R14 HAP并启动。

更窄的后续方向是：记录display active-mode切换和native窗口指标的同步时间线，确认wait下降是否只出现在active120窗口；同时从平台侧确认声明式XComponent合法的frame-rate scene/vote入口为何拒绝当前公开setter。除非能形成持续active120且媒体输出>70/s，否则不能保留任何投票改动，也不能把用户系统高刷设置本身当作产品修复。
