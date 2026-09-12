# FCP 接入验证 · 2026-09-12

后续进展：SDK 已取得并构建只读原生探针，安装被自动审批拦截，详见 [SDK 记录](sdk-probe-validation.md)。下文保留第一轮实测范围。

## 结论与门槛

尚未通过理想闭环，不开始完整界面。已证明“原生字幕文件能准确加入当前时间线”，未证明“Workflow Extension 可以直接读取当前时间线音频并增量写字幕”。不能从前者推断后者。

## 环境

- arm64，macOS 27.0 (26A428)，Xcode 26.6 (17F113)。
- Final Cut Pro.app 与 Creator Studio 版均安装 12.3；实测仅 `com.apple.FinalCut`。
- 官方下载页显示 Workflow Extensions SDK 1.0.3，2026-01-27。标准 `/Library/Frameworks/ProExtensionHost.framework` 和用户 Xcode Templates 路径未发现 SDK。FCP 自带运行时框架不等于开发 SDK。
- 下载页登录可用，点击下载未取得可定位安装包；无登录态 curl 下载返回 HTML（不是 DMG）。未伪装安装成功，未复制/提取账户凭据。
- 原 FCP 无打开资源库。新建 `.subloom/verification/Subloom-Verification-20260912.fcpbundle`；所有写入都在此处。未修改 VinciSub 源码、安装和数据，`git status --short` 为空。

## 六项能力核查

| 能力 | 证据和当前结论 | 尚需验证 |
|---|---|---|
| 当前项目/时间线 | 官方 FCPXProject 有 uid/name/sequence；FCPXSequence 有 startTime/duration/frameDuration；FCPXTimeline 有 activeSequence | SDK 原生扩展回调与身份读取尚未运行 |
| 选定范围/无范围全项目 | 官方概述明确提到 selected time range，属性页称 sequence range；语义需宿主选区对照实验确认 | 选区读取路径尚未建立；不能用未知选区回退全项目 |
| 源音频/剪辑位置/映射 | FCP 实际导出 XML 含 media-rep URL、asset 起始、asset-clip offset/duration/role；简单片段成功内存解码识别 | 这需要已取得 XML，不是实时读取 API；多片段、嵌套、变速、音频效果、权限均未验证 |
| 自动可听/多角色 | DTD 有 audio-channel-source / audio-role-source、enabled/active、mute、timeMap；角色状态与片段启用不能混为一谈 | 多角色选择、子角色、全局角色关闭、Solo、组件、混音效果尚未实测；自动模式保持 unknown |
| 原始时间线写回与校对 | SRT 两条实际导入当前项目，简体角色正确，帧位置回读正确 | 无程序化字幕追加/修改 API 实证；后续插件内编辑同步、外部冲突、重复导入尚未验证 |
| Caption/Title/XML | 原生 SRT 已实测；相同 UID 修改 XML 触发替换/保留两者；保留两者实际新建项目 | Title 拖入、定位、拆分、样式和同步未实测；没有真实操作步数可承诺 |

本机 ProEditor.sdef 暴露资源库/事件/项目/序列读取；未提供选区、片段源列表或字幕追加命令。公开 FCPXTimeline 列表只有活动序列、序列范围、观察者及播放头相关调用。此为公开接口核查，不是“绝无其他可行交互方式”的断言。

## 实测记录

### T01 原生 Caption 放回当前原始项目：通过（UI 路径）

项目 Subloom-Original，25fps，tcStart=3600s，时长 217/25s，一段普通音视频。

通过 FCP 文件→导入→隐藏式字幕，选测试 SRT，指定 SRT / 中文（简体）及“与时间线相对”：

| 文本 | SRT 时间 | UI 时间码 | XML 回读 |
|---|---|---|---|
| Subloom 简体字幕定位测试 | 1–2s | 01:00:01:00–01:00:02:00 | 父 clip 下 offset=1s，duration=1s |
| 保留 3.5% 和 USB-C | 4–5.2s | 01:00:04:00–01:00:05:05 | offset=4s，duration=30/25s |

音视频仍为 01:00:00:00–01:00:08:17。项目仍为 Subloom-Original；导出 UID `0D11EC79-ED11-4688-97A9-CB78621857DD`，字幕角色 `SRT?captionFormat=SRT.cmn-Hans`。导入前无原生 UID 快照，不能声称已做前后 UID 比对；同一打开项目、项目数量和音视频位置由 UI 确认。

真实导出：`.subloom/verification/after-captions.fcpxmld/Info.fcpxml`。纳入 Git 的 tests/fixtures 版本移除了 bookmark、媒体元数据及资源库位置，媒体 URL 替换成测试路径，字幕和时间结构未改。

### T02 XML 同 UID 再导入：有条件观察通过

原样再导入没有看到新增项目。修改首条字幕和 modDate 后再导入，FCP 明确弹出替换/保留两者/取消。选择保留两者后，浏览器由 1 项变 2 项，新增 Subloom-Original 1；打开的 Subloom-Original 仍显示原字幕。

没有测试“替换”能否保留所有身份、特效、磁性遮罩、链接及外部编辑；即使可替换，也不是已证实的增量字幕写入。不能把 XML 解释为无条件新建项目，也不能解释为直接修改当前时间线。

### T03 音频源 → 本地识别：离线通过

探针读取 T01 的 FCP 导出 XML，定位本项目媒体副本，ffmpeg 输出 16kHz 单声道浮点 PCM 到内存。只读借用 VinciSub 已安装解释器、0.6B ASR 和 ForcedAligner；设置离线模式、禁用字节码，HF_HOME 指向 Subloom。没有调用 VinciSub worker、Resolve 接口或 UI。

实际设备 CPU（沙箱内 torch 未检测到可用 MPS）；输出“大家好，欢迎使用中文字幕工具。今天我们测试语音识别，并把生成的字幕导入达芬奇。”与样本口播相符。词时间包含零长度“我”，尚未在 Subloom 实现修复/断句。见 evidence/asr-cpu.json。该输出未写回 FCP，不能称完整识别→落轨通过，也不构成准确率基准。

## 路径与操作成本

**完整可行产品路径：目前没有完成实测的候选，因此尚不要求用户选择。**

1. 已验证的写入半段：已有字幕文件及已打开目标项目时，调用导入命令、选择文件、确认角色/语言/插入方式、点击导入，共 4 个操作阶段；如果按菜单点击计数则更多，首次语言选择需要展开子菜单。这违背期望中的自动文件交接，未采用为默认产品流程。
2. 项目拖到扩展→源媒体识别：苹果有浏览器项目拖出 FCPXML 的文档，潜在增加一次项目拖动；尚未实测，不保证包含时间线范围或最终可听音频。
3. 自定义共享目的位置→识别：官方支持渲染媒体+XML，能避免用户找文件的可能性待验证；渲染、配置、范围、角色输出及回写成本未实测，不擅自采用。
4. Title 拖回：官方有数据拖放机制，但本机原时间线精确定位、批量 Title、拆分步骤与样式未验证，不能许诺“只拖一次”。

Caption 的文本/时间可在 FCP 编辑，样式受 SRT/iTT/CEA-608 标准约束；SRT 外部播放器样式兼容性有限。Title 的 Motion/文字样式空间更大，但这不证明其写回更容易。本轮未实现/选择 Title。

## 官方来源（本轮查阅）

- [FCPXTimeline](https://developer.apple.com/documentation/professional_video_applications/fcpxtimeline)：公开属性和方法。
- [sequenceTimeRange](https://developer.apple.com/documentation/professional_video_applications/fcpxtimeline/sequencetimerange)：序列范围定义。
- [FCPXProject](https://developer.apple.com/documentation/professional_video_applications/fcpxproject) 与 [FCPXSequence](https://developer.apple.com/documentation/professional_video_applications/fcpxsequence)：身份和时间基础。
- [Building a Workflow Extension](https://developer.apple.com/documentation/professional-video-applications/building-a-workflow-extension) 与 [SDK 下载页](https://developer.apple.com/download/all/?q=WorkflowExtensions)。
- [导入原生字幕](https://support.apple.com/guide/final-cut-pro/import-closed-captions-ver4185ef95a/mac)：原项目与相对/绝对插入。
- [字幕格式](https://support.apple.com/guide/final-cut-pro/format-closed-caption-text-ver23b2d99f0/mac)。
- [角色开关](https://support.apple.com/en-il/guide/final-cut-pro/ver5d6f2052d/mac) 与 [音频组件](https://support.apple.com/guide/final-cut-pro/show-audio-components-in-audio-lanes-ver7b5986f35/mac)。
- [接收拖放](https://developer.apple.com/documentation/professional-video-applications/supporting-drag-and-drop-to-receive-final-cut-pro-data)。
- [自定义共享](https://developer.apple.com/documentation/professional-video-applications/receiving-media-and-data-through-a-custom-share-destination)。
- [Importing（2016 历史文档）](https://developer.apple.com/library/archive/documentation/FinalCutProX/Conceptual/FinalCutProXWorkflowsGuide/Importing/Importing.html)：只作历史机制参考，已另用 FCP 12.3 测试同 UID 行为。
- 本机苹果随 FCP 12.3 分发的 `ProEditor.sdef` 与 `FCPXMLv1_14.dtd`：静态本机证据，不能当作实时宿主调用成功。
