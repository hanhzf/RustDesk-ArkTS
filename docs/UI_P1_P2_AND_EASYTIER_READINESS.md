# P1/P2 界面与 EasyTier 连接准备收尾

> 历史记录：2026-09-08 用户要求前端恢复至 Git `9b7bf4a`，本文件所述 UI 改造已回退；EasyTier 短等待与非 UI 功能保留。当前回退结果及新方向见 `PERFORMANCE_FIRST_ZERO_COPY_PLAN.md`，不要据本记录再次自动恢复 `.87` 界面。

## 范围

本次仅修改 ArkTS UI 和 EasyTier 启动后的连接准备逻辑。不修改 Core/HAR、
录屏授权、编解码、RustDesk 认证协议，也不重复旧录屏诊断。

## P1/P2

- 宽窗身份栏从 236vp 增至 304vp，密码槽高 64vp；显示/刷新均为 40×40vp，
  固定不收缩，文字占剩余宽度。避免原来的最小文字宽度把刷新按钮挤出边界。
- `FloatingSurface.ets` 将 LuminousSurface 的阴影框居中，而不是从左上对齐。
  LuminousNeo 1.0.2 的深浅主题使用不同内部阴影 padding；容器不能把浅色 padding
  的负偏移直接用于深色表面，否则可见表面和命中区域会错位。
- 远程 ID 直接使用 `@Local remoteIdFocused` 驱动 LuminousSurface depth：
  Raised(1) → 聚焦 Inset(-1) → 失焦 Raised(1)，保持原生 TextInput、Enter 行为。
- 窄窗输入框额外保留完整阴影布局框，不裁掉阴影、不压缩 84vp 本体高度。
- PeerCard 保留原始 70/78vp 内容高度；DirectoryPanel 在 Swiper 页内保留
  token 推导的阴影边距。不能通过缩小卡片内容或关闭 Swiper 裁切造成相邻页串色。

## EasyTier 连接准备

EasyTier 的 RUNNING 快照/启动成功只证明实例运行，不证明目标已经可达。

新增 `EasyTierReadinessController.ets`（可注入时钟、定时器、探测器）及
`EasyTierSocketProbe.ets`（NetworkKit TCP 适配）。两条 EasyTier 成功入口都先
进入既有可取消的等待 overlay，完成准备后再交给 Core 创建一次正式会话。

- 仅启用 EasyTier 且目标为规范 IPv4 或 IPv4:port 时预检；裸 IP 使用 Core
  对应的默认直连端口 21118，自定义端口保持不变。
- 最多 5 次尝试，尝试起点间隔至少约 2.5 秒，每次最多 1.5 秒；硬总预算 12 秒。
- TCP 成功即关闭探测 socket，然后启动 Core；不发送应用数据或 RustDesk 消息。
- 超时明确失败，用户可以手动重试；不无限重试、不自动重启 EasyTier。
- 取消、目标/实例改变、页面销毁、会话切换/关闭使旧 generation 失效并关闭探测。
- DNS、数字 ID、IPv6 和非 EasyTier 普通连接保持 Core 原路径；这些路径未新增重试。
- 密码错误、2FA、用户拒绝、安全确认等认证结果不参与自动重试。
- `EasyTierApiService.finishPending` 在异步读取结果后重新核对 requestId，避免
  取消后的旧结果消费新目标的 intent。
- 页面暂时隐藏不丢弃 EasyTier 返回结果：跨应用启动可能先回调再恢复前台。

## 验证

- `.87`：default/debug `assembleApp` 成功；只覆盖安装到 `127.0.0.1:5555`。
- 设备元数据：`1.0.3.87 / 10322964`。源 AppScope 仍为 `1.0.3 / 1000005`。
- HAP SHA-256：`a9c563ea8a371f269f314c097a2877363711f48b53b4e8fbd41ef43faff9d40e`。
- 原生库未变化：`d0bdbf0fafec43e44af24de48b9ae84eb7140b6754eb0bd6493dc58be5b0485a`。
- 默认深色主题，约 1100vp / 570vp / 390vp 窗口已实际检查。宽窗密码两按钮
  bounds 分别为 `[827,713][903,789]` 与 `[919,713][995,789]`，尺寸及纵向坐标一致。
- 实际截图验证宽窄 ID 框 Raised/Inset；切换页面并恢复宽窗后恢复 Raised。
  窄窗阴影上下左右均有完整空间，密码按钮在独立服务端页同样对齐。
- 4 项确定性控制器用例通过：延迟可达、预算耗尽/挂起回调、取消/晚到成功/换代、
  非 EasyTier 与不支持语法不探测。执行方式是 Node 26 对实际 ets 类型擦除并用
  Hypium 断言适配运行；**不等同于设备 Hypium 测试或真实 VPN 网络联调**。
- 主 ArkTS 编译覆盖了 controller 与 NetworkKit 适配器；测试包未在设备运行。
- `git diff --check` 通过；临时签名配置已在构建结束清理。

本轮会话中的外部取证文件：`/tmp/resk-ui86-idle.json`、
`/tmp/resk-ui86-idle.jpeg`、`/tmp/resk-ui86-focus.jpeg`、
`/tmp/resk-ui87-narrow.jpeg`、`/tmp/resk-ui87-narrow-focus.jpeg`、
`/tmp/resk-ui87-small.jpeg`、`/tmp/resk-ui87-small-host.jpeg`、
`/tmp/resk-ui87-final-wide.jpeg`。它们是临时证据，不属于产品数据或录屏实现。

## 未覆盖

真实 EasyTier VPN 从启动到目标可达的端到端测试、实际 TCP 适配器超时/取消、
浅色主题/放大字号/屏幕朗读/性能分析尚未执行；不宣称这些场景已通过。
代码与测试仍为工作树改动，未提交或推送，也未修改远端分支/PR/workflow。
