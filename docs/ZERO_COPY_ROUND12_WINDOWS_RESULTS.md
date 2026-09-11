# 第十二轮：Windows硬件编码初始化FPS与独立构建

**进行中：源码修复与静态审查通过；Windows完整CI及运行验收尚未通过，不宣称90FPS或严格零拷贝达标。**

## 用户新授权及基线

- 用户确认Windows显示器180Hz，授权修改、构建Windows版本供其手动更新；不能把此前约60输出直接解释成显示器上限。
- 当前鸿蒙R11包已可信确认Windows唯一会话，H265、90请求、质量50；19:21:59–19:22:02（+08）原生媒体输出/Render接受约59–61每秒，PIC2560×1440、队列0、decoderErrors0。仍是短窗观察，没有确认源内容新present速率或完整动态条件。
- 用户允许Windows GitHub CI使用远端临时缓存及相应任务源码提交；本机缓存和最终下载产物仍放NAS。未授权市场发布、私密签名服务或自动替换Windows安装。
- NAS-backed APFS已核实：`/Volumes/dsh-rustdesk-build`来自`/Volumes/nas/raw/dsh-builds/rustdesk-ohos/dsh-rustdesk-build.sparsebundle`；`/Volumes/RustDeskBuildCache`来自`/Volumes/nas/BuildCache/RustDesk/RustDeskBuildCache.sparsebundle`。

## 已证实的问题与最终修复

本checkout `MAX_FPS=120`，没有全局锁60的证据。Windows采集、同步编码、发送及fetched等待串行运行；180Hz不保证桌面内容每秒180个不同present；发送端原RTT ABR也能降低调度FPS。此次没有把这些候选当成已确定瓶颈。

明确脱节：VRAM生产初始化`DynamicContext.framerate=30`、HWRAM生产初始化`EncodeContext.fps=DEFAULT_FPS30`，未消费连接FPS提示。能力探测中的60不是生产限速证据。

最终采用**init-only**：

- `VideoQoS::encoder_initial_fps_hint()`取各用户wire custom_fps或默认30的最小值，防御限幅1–120；没有用户默认30。
- VRAM/HWRAM配置新增fps字段，生产构造传该提示，后端实际初始化做正i32 checked转换；benchmark显式保持默认30，probe不动。
- 后端创建成功后仅记录存储路径、codec、configured_fps。这是传入配置，不是驱动读回或实际输出FPS。
- **初始化之后修改FPS需既有自然重建或重新连接**；安装新包时先设90再连接，再核对日志，不承诺连接内自动切90。

首版曾因custom变化触发SWITCH，独立review发现P2：legacy自动FPS也经同一个`OptionMessage.custom_fps`到达，无法区分显式用户意图。最终已删除全部新增运行期比较/SWITCH/helper，避免新增重建抖动。没有添加协议字段或debounce状态，没有改ABR、背压、参考链、PTS毫秒单位。

没有使用外部后端动态set_framerate：精确cached hwcodec提交`778df1f99597722473b29443bac22ae6c23946fe`中MFX不支持它，ffmpeg_vram导出还误调用set_bitrate。这是未修改的外部问题，不能用该API伪称安全动态生效。

## 限定提交与验证

Core提交`f13c00a42`，分支`perf/zero-copy-high-fps`，仅7个文件：4个此前干净FPS文件完整本轮diff、`src/server/video_service.rs`仅两行fps构造字段、两个新CI文件。该文件其余原有数百行dirty及其他已有改动/子模块websocket未提交。CI构建这个可复现提交，而非本机全部dirty的快照。

- 五个Rust文件rustfmt及git diff检查通过。
- NAS-backed独立`/Volumes/dsh-rustdesk-build/windows-high-fps/r12-tests`内用真实完整QoS模块加依赖shim运行唯一边界测试，1 passed/0 failed；覆盖默认/90/120/非法更新/限幅/多用户/同wire legacy变化。不是Windows硬件测试或完整Cargo通过声明。
- 独立Rust review的新增重建P2已按init-only移除；其余feature、构造点与锁/Drop静态检查未见新增确定缺陷。
- 首跑前完成CI Python/YAML/bash语法、隔离overlay与打包夹具检查，独立静态review无确定severity findings。随后首跑已实际通过原生依赖、overlay、FRB及完整应用编译；helper的MSBuild调用失败需重试，Windows启动/GPU验证仍未执行。

## 独立Windows CI交付链

首次[Windows CI #34349275543](https://github.com/FrankHan052176/rustdesk4ohos/actions/runs/34349275543)，SHA=`f13c00a42077e39d9786af840d73193a21279ea2`，已完成但结论failure。**原生依赖、Flutter兼容overlay、FRB生成、Core及完整Flutter应用构建通过**；12:50:43Z的失败日志明确为后续隐私窗口helper的`msbuild: command not found`，exit127，不是Core或helper C++编译错误。未上传完整包，不能拿缺DLL目录交付。

随后只提交workflow一步修复`e3206221b5b2c03e8be0fdc2a082e0d7a2048272`：helper改用PowerShell，通过安装器目录的vswhere定位绝对MSBuild.exe，逐命令检查exitcode，保持固定helper SHA和x64目标、存在/非空/PE校验；不依赖Bash/PATH，未改业务源码。YAML/窄权限/触发路径及bash语法检查通过，独立PowerShell静态review无findings，真正执行待CI。[第二次CI #34354593382](https://github.com/FrankHan052176/rustdesk4ohos/actions/runs/34354593382)已由该push启动；未重复dispatch。

两个本地`gh run watch`曾因API连接重置退出，不是CI失败；没有因此重复dispatch。NAS上的`windows-high-fps/ci/watch-ci.py`每60秒读取状态，分开transport失败与远端结论；首次monitor已实际收取failure，第二次唯一monitor为session51。日志分存在`/Volumes/dsh-rustdesk-build/windows-high-fps/ci/<run-id>/`，第二次增加UTC检查时间与5分钟心跳。最终下载目标为`/Volumes/nas/BuildCache/RustDesk/WindowsHighFps/<commit-sha>/`，需完整产物通过后才给下载/hash交付声明。

新入口`.github/workflows/windows-high-fps.yml`仅Windows 2022 x64，精确分支guard，push.paths仅上述7文件并支持手动触发；首次一次push，不重复dispatch。不改master/生产workflow；concurrency只取消自身同分支旧run。权限contents:read，checkout不保留凭据，无secret/签名/Release/市场动作。

复用真实Flutter/Core/virtual_display构建，并构建固定TopMostWindow辅助库。Rust1.95、Flutter3.24.5及生产patched engine、LLVM15.0.6、FRB1.80.1、固定vcpkg baseline和hwcodec+vram。原OHOS Flutter API在标准Windows SDK不兼容，helper仅在隔离CI副本及固定PUB_CACHE文件精确移除不可用的空平台case/恢复主题类型，次数漂移失败，每项记录前后hash；不改本地Flutter源码或依赖版本。

预期产物是完整unsigned运行目录ZIP，不是只有Core DLL的stub。打包检查runner/Core/engine/插件/ICU/AOT/assets、virtual_display和WindowInjection、AMD64/PE32+、本轮Core hash、ZIP CRC及SHA256；不代表实际启动或GPU验收。可选USB虚拟屏及printer驱动缺省，不偷偷调用签名服务。engine来自既有浮动release URL，记录hash可追溯但不是独立内容固定保证。

## 严格零拷贝仍未达标

精确hwcodec源码审定发现：原生NVENC有CopyResource到自有输入池；AMF包装后Duplicate；MFX及FFmpeg三厂路径有额外BGRA→NV12输出纹理。无CPU回读不等于严格零拷贝。当前只可证明未旋转DXGI到Core texture到FFI入口没有本层像素搬运，**不能证明任一现成完整backend零拷贝**。

用户已明确显卡厂商为**NVIDIA**，具体型号未提供。严格候选为同设备未旋转BGRA的原生NVENC外部纹理注册，配合DXGI acquired-frame lease与编码完成后注销/释放；厂商信息不代表设备/编码能力已通过。AddRef、提交返回、低延迟参数或一次空输出都不能替代消费完成证明。AMF需对应surface-release observer；不合格路径须明确能力缺口，不能静默回GDI/RAM/软件或其他GPU复制路径。未启动该依赖实现。

已在NAS准备`acceptance/NVENC_EXTERNAL_INPUT_PLAN.md`：建议独立外部输入状态及token/generation账本，不修改SDK旧环索引；submit/poll/drain方法与Core lease/窄FFI/fail-closed接入范围。SDK要求销毁前flush，**没有找到DestroyEncoder即安全取消契约**；异常drain与设备丢失回收仍是产品化缺口，不以永久泄漏作完成方案。仅静态设计，未编译/运行/证明零拷贝。

此包只修初始化FPS参数与构建交付链，原发送端ABR和旧fallback未改，不是完整FPS优先慢降质量策略，也不是严格零拷贝最终交付。

## 设备维护

原生纯计量tag已恢复W，全局日志等级未改。用户明确完整任务结束前不断周期wakeup，编译/等待/阶段汇报继续保持。base session35/bash412两小时自然到期exit0，已收取；maintenance session38/bash542检测退出后记录`health=ok`、`base-round=1; interval=10s; limit=1800s`及command-monitoring。**自动续期已实际观察，不再只是未测方案**；未另开并发waker，当前仍由该单一maintenance管理。完整任务收尾时停止仍运行的托管句柄，不裸PID/进程组kill，不改永久电源设置。

## NAS手动验收材料

`/Volumes/nas/BuildCache/RustDesk/WindowsHighFps/`内新增：

- `MANUAL_UPDATE_AND_ACCEPTANCE.md`：整组文件校验/手动更新/回退与分段读数；提醒旧安装/服务可能被复用，不只看新EXE窗口，不自动停止服务、不导出认证。
- `acceptance/high-refresh-source.html`及`acceptance/README.md`：自包含离线WebGL2动态源，单fullscreen triangle，无pixel上传/readback/CPU绘图fallback；rAF及5秒窗口、可见性/像素尺寸/DPR与帧条。node语法及基础HTML检查通过；未运行浏览器、GLSL、Windows180Hz或实际链路，不把rAF当呈现FPS。
- `acceptance/NVENC_EXTERNAL_INPUT_PLAN.md`：上述静态所有权方案。

NAS自动生成的`._`元数据旁文件不是运行依赖。所有材料均不包含连接目标、凭据、设备标识或完整日志；没有启动本地服务器/浏览器或修改显示模式。
