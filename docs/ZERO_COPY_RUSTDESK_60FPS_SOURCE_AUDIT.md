# RustDesk底层60FPS平台：生效路径复核

## 结论与版本边界

用户怀疑RustDesk底层限制后，按发送端、客户端反馈、OHOS提交三条链交叉核对。**已证实RustDesk存在主动动态降帧，未证实固定60常量锁或当前唯一根因。** input-buffer wait只定位阻塞点，不能据此定罪操作系统。

发送端按用户报告已安装的`e3206221b`提交树核对，本轮未独立验证Windows进程加载模块哈希；客户端按当前R14来源工作树核对。Core主工作树有大量既有dirty，不能把未提交的controller当Windows已部署代码。以下行号相对Core；Windows条目按e320提交。

## 1. 确实生效：Windows旧QoS决定实际节拍

- `src/server/video_qos.rs:31-34`：默认30、最高120、首秒15，没有最高60常量。
- `:391-410`：单用户custom和auto_adjust取较小，再跨用户取最小。custom=120、auto=120时允许上限120。
- `:246-329`：TestDelay样本使实际FPS快降慢升；平均延迟>=150ms进入下降分支。`:336-341,521-545`还有响应超过2秒时降到2FPS的分支。
- `src/server/video_service.rs:677-685,739,905-910`：实际循环取QoS的spf传给采集，再补sleep。这是真正的调度，不是显示标签。
- `f13c00a42`在video_service只有两个创建参数增量，把`encoder_initial_fps_hint()`传给VRAM/HWRAM；没有替换旧QoS。创建后set_quality只改码率，没有runtime FPS reconfigure。

所以请求120、硬编初始化120、实际发送120是三个不同事实。已有`hardware encoder initialized ... configured_fps=`日志应核对，不能从desired推断。ArkTS在peer_info后applyQuality存在初始化时序边界，但Core也可能从持久配置带入正确FPS，不能仅凭UI调用顺序断言提示错误。

本地`video_frame_controller.rs`主要处理通知和生命周期，不等于已经实现了另一套Windows帧率优先QoS。

## 2. 排除：当前OHOS连接不是呈现ACK锁帧

客户端未设置LoginRequest.video_ack_required=true，也不构造Misc.VideoReceived；默认false。Windows `connection.rs:1040-1049`在发送任务取出视频后、stream.send之前按display立即notify，不等待客户端解码/呈现。

旧controller虽逐帧等待通知（`video_service.rs:890-903`），但默认false路径用unbounded channel；reset/set_send不清channel，先到通知不会丢，try_wait_next还会drain已排队通知（`:65-93,134-191`）。没有16ms轮询。ACK-required=true的by_conn_id映射竞态可能造成300ms/3s级等待，但不适用于当前默认false的单OHOS连接。

## 3. 排除：single-display native H265的软件安全帽

- `src/client/io_loop.rs:1277-1292,1362-1383`：desired存在时旧auto-FPS写入被屏蔽。
- DecodeSafety数据来自`src/client.rs:3145-3160`的software metrics。`record_software_decode`仅见`libs/scrap/src/common/codec.rs:809,828`，match仅VP8/VP9/AV1（836-840）。native H264/H265不产生这组decoded_frames/decode_ns，capacity=None，不能新建该帽。
- 每帧处理前还清空thread-local软件指标（client.rs:3100）。`frame_rate_controller.rs:259-263`的restart_epoch调用start_epoch，后者246-247重建默认safety，不继承同display旧帽。

复核中曾把软件DecodeSafety错误套到native H265，已撤回。另一仍active的软件display可能贡献全局最小帽是多display边界，没有当前single-display触发证据。

## 4. Native提交没有发现应用层60Hz定时

- `libs/scrap/src/common/ohos/codec_adapter.rs:106-111`逐packet提交，无定时。
- `avcodec.rs:465-484`输入buffer回调入队并notify；`:1044-1085`仅输入队列空时condvar等待；`:549-552`独立输出worker直接Render，无16.67ms休眠。
- HAR的sleep(16ms)位于被控滚轮触控注入（src/lib.rs:6450），不是当前视频链；OHOS encoder的30常量也属于反方向。

Push/Render接口返回快不等于异步硬解或Surface消费快。R14 inputAcceptedPerSec是喂给解码器成功量，不是网络收包或Windows发出量。原生输出约60、输入buffer等待和压缩积压不能单独排除集成问题。

## 5. 下一阶段最小实现

在NAS隔离干净e320工作树`/Volumes/dsh-rustdesk-build/windows-high-fps/sender-diagnostic`实现默认关闭的一秒聚合诊断：请求/实际QoS FPS、capture Ok/WouldBlock和耗时、encode/入队帧数、发送任务通知等待、补sleep、transport send成功/失败与耗时。多帧消息按frames.len计，不用bool；按真实elapsed计算，不固定除1000。请求、入队、socket写入成功、客户端输出分别命名，不能混称已显示FPS。

不改QoS、协议、codec、画质、分辨率、背压或像素路径。Windows安装由用户执行。诊断实现或编译不等于修复，不掩盖NVENC CopyResource等既有严格零拷贝缺口。

数据判别：

1. QoS实际<=60：先处理RustDesk主动调度，不能只改创建提示。
2. QoS=120而采集/编码/发送只有60：查采集新帧和硬编；180Hz显示器不保证180个不同桌面帧。
3. 实际发送>70且客户端持续有待解包、native输出仍60：发送限速不能单独解释；再做相同码流绕过RustDesk网络/反馈/队列的native→原Surface饱和对照，不换规格、不加无界队列或丢参考帧。

## 6. 历史解释纠正

napi_unwrap=0不验证返回指针的C++类型；此前称其证明拿到了OH_NativeXComponent*过强。只保留当前尝试setter=-1、没有成功投票的事实，不能推导平台拒绝所有合法入口。无新投票日志也不单独证明未调用；样本前后active=120/60不能给每个采样窗分类。当前平板仍为R14，性能和严格零拷贝目标均未达成。

## 验证状态

源码审查与最小计量实现完成。隔离工作树提交`3eae81eb6e74436bdabbb1822dd141a8a8c8f1fe`已fast-forward推送至远端`perf/zero-copy-high-fps`；只包含本轮8个诊断/构建/说明文件。主开发仓原有dirty和R14平板包未带入或覆盖。

最终独立检查：Rust 1.95的std-only计量测试2 passed/0 failed，覆盖实际elapsed、重置、多frame/recipient发送尝试、失败不计成功、mixed display及partial关闭；`git diff --check`通过，Python打包助手语法检查通过。[Windows CI 34464193084](https://github.com/FrankHan052176/rustdesk4ohos/actions/runs/34464193084)已成功，包含Windows计量测试、完整Flutter客户端、辅助DLL和运行包检查。构建元信息记录耗时1664秒；这不等于Windows目标机器/NVENC运行验收。

审查纠正已落地：原recv→notify顺序不动，实际send返回后先取elapsed再统计frame长度；默认关闭无payload遍历；发送尝试不称成功入队；transport明确整连接口径，mixed/none display为-1；日志带编译期build和PID。empty窗口仍保留真实时间，禁止删掉stall来抬高FPS。详见隔离提交的`docs/WINDOWS_SENDER_DIAGNOSTICS.md`。

### 已交付诊断产物

- 下载并验证位置：`/Volumes/dsh-rustdesk-build/windows-high-fps/sender-diagnostic-artifacts/3eae81eb6e74`。
- 直接NAS副本：`/Volumes/nas/BuildCache/RustDesk/WindowsHighFps/sender-diagnostic-3eae81eb6e74`，所有复制文件逐一做SHA比对，说明也比对CI记录的SHA。
- 运行包：`rustdesk-sender-diagnostic-windows-x64-3eae81eb6e74-unsigned.zip`，31,898,948字节；SHA256=`e3c689a0ccb40d6d4d55465b9b1a21802ce47ebbd76ed515b53197b28e715d2d`。
- Core DLL SHA256=`edad686cfdc114eea3564f0d106d20137312de044d5157a1bcf3c60004fef8ee`。
- 宿主实际核验：ZIP SHA/CRC、内外metadata一致、完整Flutter资源及关键文件、16个PE32+ x64成员、说明SHA；实际Core DLL中存在本次40位build SHA及service/transport诊断标记，不仅检查文件名。
- 验证回执：同目录`ARTIFACT-VERIFICATION.json`。启用与只导出本构建诊断行的方法：同目录`WINDOWS-SENDER-DIAGNOSTICS.md`，包内也包含该说明。
- [GitHub artifact](https://github.com/FrankHan052176/rustdesk4ohos/actions/runs/34464193084/artifacts/10147789862)为外层容器；以上SHA针对其中的unsigned运行包，不是GitHub外层ZIP。

Windows安装/服务切换由用户自行执行，未自动覆盖。新GUI可能接到旧IPC server，必须以实际发送行的build+PID确认归属；缺行不能计成0FPS。R14平板包未变；诊断交付阶段完成，但实际FPS、延迟与严格零拷贝验收仍未通过，本轮未采集新Windows运行样本。

### 补充排除：不能先验归因于Windows 15.625ms sleep

按本次Rust 1.95精确提交`59807616e1fa2540724bfbac14d7976d7e4a3860`的[thread实现](https://github.com/rust-lang/rust/blob/59807616e1fa2540724bfbac14d7976d7e4a3860/library/std/src/sys/thread/windows.rs)及[Windows time实现](https://github.com/rust-lang/rust/blob/59807616e1fa2540724bfbac14d7976d7e4a3860/library/std/src/sys/pal/windows/time.rs)，现代Windows优先使用high-resolution waitable timer，旧系统或API失败才会fallback到普通Sleep。没有timeBeginPeriod调用不等于固定15.6ms。新计量可定位spf与实际补睡是否偏离；但每窗累计/最大值不是完整分布，更不能只凭15ms尖峰断言实际走了fallback，仍需运行证据。

历史记录：`docs/ZERO_COPY_ROUND13_LATENCY_RESULTS.md`。
