# 鸿蒙真机调试与部署

本地仓库是源码基准。先在本地修改、验证并提交，再将同一提交同步到 FDEV01 构建。构建前逐文件核对两端已跟踪源码；不要直接在 FDEV01 改源码或从未同步的旧工程打包。

## 构建

FDEV01 的 HarmonyOS 工具链需要设置环境变量：

```bash
export NODE_HOME=/root/ohos-sdk/command-line-tools/tool/node
export DEVECO_SDK_HOME=/root/ohos-sdk/command-line-tools/sdk
/root/ohos-sdk/command-line-tools/ohpm/bin/ohpm install
/root/ohos-sdk/command-line-tools/hvigor/bin/hvigorw assembleApp
```

应用构建使用与本地 `rustdesk-ohrs.har` 一致的 HAR；若 ArkTS 报缺少导出，先核对 HAR 的版本，不要只复制旧的 FDEV01 构建产物。取用 `entry/build/default/outputs/default/app/entry-default.hap`，并确认包内版本高于设备已安装版本。

## 本机签装与设备验证

Mac 上的 HoKit 可完成设备连接、华为账号重签名和安装。它与“小白调试助手”分别使用自己的 HDC 服务；查询设备要使用当前连接工具对应的 HDC，不要以另一套 HDC 的空列表断定设备未连接。小白调试助手内置 HDC 的查询方式：

```bash
"$HOME/Library/Caches/hap_installer/hdc_tools/hdc" list targets
```

在 HoKit 中选择本次构建的 HAP，确认应用包名与版本，重签名后安装到目标设备，并在设备端完成授权。安装后读取设备上 `top.frankhan.resk` 的版本并启动 `EntryAbility`，再在真机上验证本次修改。若提示“不能降级安装”，先比较包和设备的 `versionCode`，通过本地版本提交生成更高版本的包。
