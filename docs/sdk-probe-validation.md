# SDK 1.0.3 原生探针验证 · 2026-09-12

## SDK 真实性与范围

用户下载的 `/Users/chokamin/Downloads/Workflow_Extensions_SDK_1.0.3.dmg` 校验、只读挂载成功。包版本 `1.0.3.1.1730248147`。

- DMG SHA-256：`fbd245c2d1439a93b86284cce2b6bb028fddea90d76aa4960d48502fa05c376a`。
- FCPXHost.h SHA-256：`bc1cbf4e75f7f35a3e6cb7575f959c97b6843cb5b60a3031d4732a02d3173104`。
- 沙箱内 pkgutil 最初显示 invalid signature；获准访问系统信任服务后复查为 **signed Apple Software**，证书链 Software Update → Apple Software Update Certification Authority → Apple Root CA，spctl 为 **accepted / Apple Installer**。不能沿用初次误报。
- 仅用 pkgutil 将 SDK 解包到项目忽略目录 `.subloom/sdk-expanded`，未运行包安装脚本、未全局安装 SDK、未改变系统 Xcode 设置。
- 包内没有找到独立 Release Notes PDF；读取了 PackageInfo、FCPXHost.h、ProExtensionHost.h、ProExtension.h、模板配置与 entitlements。官方独立 release notes 尚未读取，不声称已读。

## 头文件实际接口

- FCPXHost：timeline、versionString、bundleIdentifier、name。
- FCPXTimeline：movePlayheadTo:、playheadTime、activeSequence、sequenceTimeRange、add/removeTimelineObserver:。
- 观察者：activeSequenceChanged、playheadTimeChanged、sequenceTimeRangeChanged。
- 容器：Library URL/name，Event UID/name，Project UID/name/sequence；对象有 container/objectType。
- Sequence：name/startTime/duration/frameDuration/timecodeFormat。

**此版本头文件未暴露独立选区字段、片段枚举、可听角色、字幕追加/更新 API。** 这是 SDK 静态证据。头文件不证明其他交换路径不可行，也不构成原生宿主已连接的证据。

## 构建产物

`.subloom/build/SubPop Probe.app` 内嵌 `SubPopProbe.appex`，本地 ad-hoc 签名，arm64，最低 macOS 13。仅用于隔离验证，不是发布构建。

- 原生 AppKit NSViewController：显示实时 JSON；SDK 观察者回调后读取状态，未收到回调时保持未知。
- 只读记录项目及容器 UID、时间值/时基/flags/epoch；不将 sequenceTimeRange 标为选区。
- XML drop receiver 接受 FCP XML 类型并记录实际 pasteboard 类型和文件。行为尚未实际拖放验证。
- 日志已实际落盘于扩展容器 com.chokamin.SubPopProbe.Extension 的 Data/Library/Application Support/SubPopProbe。
- 不调用播放头移动，不写 FCP 时间线，不自行编写 AppleScript；SDK 内部使用 Apple Events，不请求网络/辅助功能权限。未复制 VinciSub 宿主适配或 UI。
- 使用官方 libProExtension.a 和模板定义的 `_ProExtensionMain` 入口；不链接私有 FCP class symbols。

最初编译误用 CLT macOS 27 SDK，旧链接器不识别 arm64e.x1；构建脚本改为显式采用 `xcrun --sdk macosx --show-sdk-path` 返回的 Xcode macOS 26.5 SDK，避免修改全局 Xcode 选择。

## 验证结果与阻塞

- `python3 scripts/build_probe.py`：通过，clang 开启 Wall/Wextra/Werror（仅忽略未使用的回调参数）。
- 11 项测试全部通过：原 8 项 + 编译 bundle metadata、arm64/SDK 入口、签名与沙箱 entitlements 3 项。
- `codesign --verify --deep --strict`：通过。`otool -L` 只见系统依赖。
- 用户后续明确允许安装启动，更名后安装至 `/Applications/SubPop Probe.app`，容器与 FCP 原生菜单面板均实际打开成功。
- FCP 12.3 标准版、隔离 Subloom-Original 时间线：host 名称/版本/bundle、观察者回调、日志落盘通过。实际回调读取到有效播放头和 sequenceTimeRange（start=3600 秒、duration=8.68 秒）。
- **activeSequence 仍为 nil**，因此项目 UID/容器链未通过。系统日志出现 ProExtensionHost Apple Events `NSOSStatusErrorDomain -600`。这不是“项目未打开”的证据，也尚不能归因为权限问题。
- 构建 2 加入 FCP `library.inspection` scripting-target；构建 3 加入 automation.apple-events entitlement/用途说明，仍未解决 activeSequence。范围与播放头此前未无条件记录，不能断言新增 entitlement 使其可读。
- 实际快照见 `docs/evidence/subpop-host-partial.json`。没有开展 XML 拖放、选区对照、角色或字幕写回的新一轮测试。

## 更正：选区能力仍待实测

[苹果时间线交互概述](https://developer.apple.com/documentation/professional-video-applications/interacting-with-the-final-cut-pro-timeline) 明确描述 selected time range within the sequence，而属性页只写 sequence range。此前凭属性名称/头文件排除选区能力过早，现撤回该结论。必须在 FCP 内改变时间线范围，比较回调和值，再判断可用性。
