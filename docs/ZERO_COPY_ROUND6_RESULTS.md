# 第六轮：strict 故障暂停与 packed 采集单次映射

本轮聚焦前一轮已发现的具体问题，不重新设计界面，不更改协议/认证、不修改 strict 默认值。**实现、审查、Core 目标测试与最终 App 构建安装完成；真实采集8帧仍未通过，整链零拷贝未达标。**

## strict 故障与恢复范围

Core 改动限定 `src/server/service.rs` 与 `src/server/video_service.rs`：仅 OHOS 视频使用受控 runner。类型化 strict 能力/owned 构造/提交故障暂停自动重建、通知新旧订阅者；普通 SWITCH、捕获 reset/Interrupted、一般 IO 与 legacy 仍走原有恢复。恢复键只能包含新订阅 epoch、strict 实际配置、codec 和有效 I444，不因计时/QoS 质量变化自动重试。通知不交换 snapshot，保持待首关键帧订阅语义。

初次实现的独立审查拦下了两个边界：reset 清零尺寸后 owned 构造失败可能被误锁存为永久错误；非 VP9 协商不应被无关 VP9 色度变化反复唤醒。最终版本已修正：strict 能力判断前 `capture_ready` 将零尺寸返回普通 WouldBlock；只有当前 codec 和保存的真实 EncoderCfg 都是 VP9 才查询 I444。无 synthetic 配置，不在失败后重读 epoch/config；首次实际配置的 I444 在 owned 构造前观察并绑定，不凭 None→Some 自动重试。独立限定复核通过。

## 非致命通知必须跨层保留连接

HAR 已有 `msgbox` 仅把 `Connection Error` 标题或含 `error` 的类型转为 failed；但 ArkTS `handleMsgBoxEvent` 先前将其它未知类型也送入 `handleRemoteDisconnect`。

本轮仅补精确 `custom-nook-nocancel-hasclose` 且非 `Connection Error` 的分支：保留会话状态，显示现有 toast 并保留 notice 文本；toast 异常也不关连接。密码/2FA/insecure/等待首帧/成功/普通错误路由不变，没有新增布局或登录成功判定。

依据：Core Flutter `common.dart` 的 hasclose 按钮仅 dismiss 对话框；[HarmonyOS PromptAction.showToast](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uicontext-promptaction#showtoast) 是现有 UIContext API。这里复用标准消息类型，不添加新协议。

真实生产 `handleMsgBoxEvent` 提取、Node TS stripping+VM spy 测试两组通过（`node /tmp/round6-msgbox-review-20260819.cjs`）：非致命通知/显示异常均仅改变 notice、不修改 session/phase/2FA/timer；fatal、认证和等待等旧路由保持。这不是目标 UI 或真实远端 E2E 证据。

独立检查还发现既有后台 protected 事件截断生成的 `warning` 仍可能进入默认断联分支，本轮不扩大消息分类范围；不能把精确通知的修复说成所有后台溢出语义已修复。

## 消除已证实的重复映射盲点

HAR `ohos_capture_lease.rs`：只对现有 RGBA/RGBX/BGRA/BGRX packed 白名单，在 GetConfig/stride/容量校验后调用一次 Map，或保留原有 fence 的一次 MapWaitFence。移除 MapPlanes 失败后再次 Map 的路线，因为官方参考实现可能已经 Map 成功、仅后续 GetPlanesInfo 失败。

未知/planar 格式在 map 前拒绝并返回原 acquire fence；无复制、引用补偿扩展或 native 重试。Map 失败不猜测性 Unmap；成功但空地址则单次 Unmap 再归还。只证明 packed direct-map 契约，不支持任意多 plane/offset 布局，不声称修好了上轮 Release cache miss。

清理统计保留原 aggregate，增加真实已映射 lease Drop 与输入拒绝两类 Release 计数，以及 owner 缺失时单独 Unreference 计数；不向 Release 合成错误码。capture 诊断增加这些统计及独立读取的已有发布帧/回调计数，只是当前采集的独立瞬时计数，不是原子帧快照，不含像素/指针/配置内容。

子任务提取真实校验函数和原有测试，5 项宿主 Rust 测试通过（原3+新2）。不证明实际 Map/Release/驱动行为。

## 验证与剩余范围

### 真实 Core 测试：编译、目标执行、产物绑定

不再从 HAR 工作区测试非成员依赖；本次从 Core 自身工作区执行：

```text
cargo test --target aarch64-unknown-linux-ohos
  --target-dir /Volumes/RustDeskBuildCache/har-target
  --release --locked --lib --features ohos-har,cliprdr-file-service --no-run
```

使用 HAR 的既有 OHOS 环境和版本化 libvpx 验证脚本。首次编译3m54s成功，但构建前后视频源码 SHA 不同（子任务最后一处 cfg 一致性修订在构建期间落盘），父检查拒绝该次产物证明；冻结后同命令重跑1m00s，两个 Core 文件构建前后 SHA 一致。

最终真实测试程序 `librustdesk-4e0c144774c234a5` SHA-256：`16b2888510d0cf8de0dae8450c58d6fd0a534054f2078698a3c3d53c59c3ebe3`。仅需要设备已有 libc/libc++，在 `127.0.0.1:5555` 的本轮唯一临时路径上分别 `--exact` 运行以下两项，各 **1 passed / 0 failed / 62 filtered out**：

- `server::video_service::strict_input::tests::fatal_pause_rearms_only_for_changed_attempt_key_and_preserves_other_results`
- `server::service::controlled_service_tests::subscription_epoch_and_failure_notice_cover_pending_and_existing_without_swapping`

前者覆盖 typed 暂停、开始时恢复键、零尺寸 WouldBlock、普通 SWITCH/Interrupted/IO 保留、有效配置查询和安全 MessageBox；后者实际使用 Service、ConnInner 与 Tokio 通道，验证重复 pending/active ID 不增加 epoch、snapshot 报错仍 swap、通知覆盖两 map 且不 swap、退订与重连。测试程序已从设备删除。

这是 OHOS 上的真实库单元测试，**不是完整 runner 线程竞争压测、真实远端认证/协议连通或可见通知 E2E**。记录：`/tmp/resk-zero-copy-round6-core-tests-final.log`、`...-gate-target.log`、`...-subscriber-target.log`。

### Core→HAR→ArkTS 最终构建与安装

- HAR 工作区 `cargo build --target aarch64-unknown-linux-ohos --release --locked`：2m32s成功，7个相关源码/声明在构建前后 SHA 一致。
- 源工作区和 APFS 镜像均通过 refresh-native-har 脚本重新安装依赖，未只覆盖归档文件。镜像页面 diff 核对只包含本轮12行非致命通知处理；同步后 SHA 一致。
- `hvigorw tasks --mode project --no-daemon` 确认 assembleApp，项目级列表未显示 test 任务；`assembleApp product=default buildMode=debug --no-daemon --no-incremental`：10.090s成功。保留原有 warnings，不宣称零告警；临时签名目录已清理。
- 仅 `127.0.0.1:5555` 执行 `install -r` 成功；安装查询 `1.0.3.88 / 10322965`、debug=true、debug Profile。源 `1.0.3 / 1000005` 不变，未卸载/清数据/变更身份。

| 产物 | SHA-256 |
|---|---|
| package.har | `2f3dc3265d1061b9dd935242605bff750ba23af46d1c74ff65801cf1b8cccd89` |
| HAR 原始 SO | `def94edd77cc30097d7c634d2a790fc0803c3a34ba5e4f7c8c16b1b306ff0ead` |
| signed HAP | `137ae99de7e92df6135dacdad81f325b749a0fac21442ed18fe2063bcb1e08d3` |
| HAP stripped SO | `ffe2ff92345fa3a5eee32bb1db8cc27a94511d8f877630b53a9cb20b759c0d12` |
| 同步后的 RustDeskIndex.ets | `eadfba60485aa220cd76ba328f87a5d68e9343441dfaad2f7de7716a78afd6a7` |

原始/stripped SO 的23个可加载 section 属性、地址、大小和内容相同。构建日志：`/tmp/resk-zero-copy-round6-native.log`、`...-arkts.log`。

### 目标采集：新增证据与未通过项

正常服务端页与系统录屏授权交互，保留已勾选的屏幕隐私保护；没有改权限/隐私设置或触发远端连接。为隔离 once-per-process 诊断，正常 force-stop/start App 一次，不清数据。

| 进程/场景 | 结果 |
|---|---|
| PID7213，未启动采集 | `capture_not_active`，0ms，0帧，worker=false；全部新旧清理计数与回调/发布计数0 |
| PID14046，正常授权后观察真实采集 | 1920×1280 RGBA，stride7680；2 编码/2 packet/2 解码；10028ms后 `deadline_exceeded`，worker=false，RustScopesDropped=true；目标8帧未通过 |

第二次日志的4条记录均通过完整 JSON 解析，没有因新增 detail 字段而截断。开始时 frameAvailableSignals/publishedFrames=6/6，最终8/8；probe处理2个新帧与此计数增量相符。这缩小了“probe 大量漏采/故意不消费”的解释空间，但独立瞬时计数仍非完整事件追踪，不能断言绝无竞争、dirty-only机制或驱动背压根因。

最终全局累计 Release 7次/失败7；**全部来自 releaseMappedLeaseDrop**，lastCode/lastErrorCode为41210000；releaseRejectedInput=0、ownerMissingUnreference=0；Unmap与Unreference均7次/失败0。这说明当前记录的失败发生在成功映射的 lease 正常 Drop，而非格式/容量拒绝或缺失 owner 的补 Unreference 路径。计数仍不逐帧归因，不能断言所有7次错误码相同，也不能把7次都归给 probe 的2帧。单次 Map 修复没有消除队列 Release 问题。

期间逐条执行一次首页/服务端切换，没有受控帧率或连续动画保证。诊断结束后，通过已确认的“停止服务端”正常停止；最终 hierarchy 的 `originalText` 明确恢复为“启动服务端”。这仍不等于所有驱动资源成功归还证明。

有效日志：`/tmp/resk-zero-copy-round6-inactive-final.log`、`...-capture.log`。导航排查曾因只读 `text` 漏掉 `originalText` 中按钮而误判点击没生效，已纠正，未据此更改 UI。临时 UI 截图只用于导航核对，查看前遮挡非导航内容，原始及遮挡图、临时 hierarchy 均已从本机/设备清理，不作为零拷贝证据。误用 host `hdc hilog` 导致过滤参数未生效的日志流已停止、广域日志已删除；有效记录来自显式 `hdc ... shell hilog` 的 PID+tag 过滤。

尚无证据保证一次正常 UI 动作能提供诊断所需的8个新捕获帧：当前 hierarchy 的 Scroll/List 均未报告可滚动；弹性边缘效果不等于确定的持续帧源。不得把极低 swipe 速度（系统会回默认值）或零散工具点击包装成受控性能基准。上一轮真实采集超时、Release失败和显示能力缺口保持未解决，直到出现新的目标证据。

## 下一步收敛

strict 永久错误暂停与跨层非致命通知本轮已落地，不再反复重做其设计。下一轮优先查成功映射 lease 的队列归还契约/缓存成员资格及实际捕获通知来源；只对已证实的问题修复，不通过补引用、忽略错误或复制来掩盖失败。DMA-BUF EACCES、GLES3.0与要求3.1路线的显示能力缺口继续明确保留。生产 strict/完整远端会话、持续帧/尺寸变化与驱动端零搬运仍未验收；长期目标保持 active，不标完成或 blocked。
