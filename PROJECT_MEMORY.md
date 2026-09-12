# 项目记忆

## 2026-09-12：独立初始化与第一轮接入验证

- 需求：原生 FCP 工具 Subloom，先核实接入能力和原时间线字幕闭环，再做完整界面；保护 VinciSub 和现有资源库。
- 改动：建立独立 Git 仓库及四份协作文档、README、能力报告、隔离测试 XML/SRT 生成器、严格限定简单片段的 FCPXML 回读探针、离线 Qwen 识别探针与回归测试。
- 关键文件：`probes/make_fixture.py`、`probes/readback.py`、`probes/recognize_fixture.py`、`tests/test_probes.py`、`tests/fixtures/fcp-12.3-caption-readback.fcpxml`、`docs/integration-validation.md`、`docs/evidence/asr-cpu.json`。
- 本机：arm64、macOS 27.0、Xcode 26.6、两套 FCP 12.3；本轮仅标准版实测。官方 SDK 下载页为 1.0.3，未获得有效安装包，未安装/构建扩展。
- 验证结果：8 项单元/档案回归测试通过；夹具按 FCP 自带 1.14 DTD 校验通过。FCP 隔离原项目内两条 SRT 中文字幕相对定位准确，实际导出含中文简体角色；同 UID XML 修改导入弹出替换/保留两者，后者新增项目、原字幕不变。源路径来自实际 FCP 导出，ffmpeg 内存解码、Qwen 0.6B/对齐离线 CPU 实测通过。ASR 结果未写回，不称完整闭环。
- 安全与范围：全部 FCP 写入仅独立 Subloom-Verification-20260912 资源库；未写用户已有项目。VinciSub 只读借用解释器和模型，禁用字节码与联网，媒体独立复制，Git 工作区仍干净。未发布 GitHub、未购买。结束关闭测试资源库并确认 FCP 未载入任何项，保留独立测试数据供续测。
- 剩余问题：SDK 安装/原生扩展运行；当前选区、自动可听和多角色；Title、精确自动写回及校对同步；MPS 与复杂映射。未擅自采用文件导出导入作为产品方案。后续先补齐探针再交用户选择可行路径。

## 2026-09-12：SDK 校验与原生只读扩展构建

- 需求：用户已下载 SDK，继续最小原生接入验证。
- 改动：只读挂载官方 SDK 并在项目内解包，校验苹果签名；读取实际头文件和模板，新增 AppKit 容器应用、只读时间线观察器、XML 拖入记录器及可重现构建脚本。
- 关键文件：`native/Probe/Container.m`、`native/Probe/ProbeViewController.m`、`scripts/build_probe.py`、`tests/test_native_probe.py`、`docs/sdk-probe-validation.md`。
- 验证结果：编译及签名校验通过，11 项测试全部通过。SDK 1.0.3 头文件无选区、片段枚举、角色状态、字幕写入接口。修正工具链自动选择 CLT 27 SDK 导致的链接错误，显式采用 Xcode 26.5 SDK。沙箱内签名误报经系统信任服务复核为 Apple Software/accepted。
- 剩余问题：自动审批拒绝复制自签名 app 到 /Applications，要求本次安装确认；未安装/启动，不绕过，未做新 FCP 实测。等待确认后继续真实 host/拖放验证；独立 release notes PDF 未读。未改变 VinciSub 或用户 FCP 资源库。

## 2026-09-12：更名 SubPop 并完成原生面板部分宿主验证

- 需求：用户明确允许安装启动，并将产品改名为 SubPop。
- 改动：应用显示名、原生类、bundle identifier、日志目录和构建测试更名；保留仓库物理路径与历史证据名称。安装并打开只读面板，补充 FCP inspection/automation 权限用于 SDK 通信排查；范围/播放头独立记录，不被空 sequence 隐藏。
- 关键文件：`native/Probe/`、`scripts/build_probe.py`、`tests/test_native_probe.py`、`docs/sdk-probe-validation.md`、`docs/evidence/subpop-host-partial.json`。
- 实测：FCP 12.3 标准版中原生菜单注册、面板加载、host 身份、观察者回调和日志通过；隔离原项目范围 start=3600 秒、duration=8.68 秒，播放头有效。activeSequence 为 nil；SDK Apple Events -600 根因未明。新增权限未修复，不宣称权限或 SDK 能力已定论。未写入新字幕。
- 更正前两条历史记录：不能声称 SDK 已证实无选区。苹果概述提到 selected time range，属性语义需实测对照；此前排除结论撤回。自动审批的旧安装阻塞已由用户本轮明确授权解决。
- 验证：11 项测试通过，构建/签名通过；单元测试不是 FCP 完整闭环。剩余：项目 UID、选区对照、拖入 XML、可听角色、原时间线 ASR 写回与编辑同步。未修改 VinciSub、未发布。

## 2026-09-12：仓库迁移、只读诊断与活动序列恢复

- 需求：目录也更名 SubPop，继续解决活动项目空值。
- 改动：关闭独立测试库后，将真实仓库移至 Desktop/SubPop，旧目录保留兼容链接；更新协作路径。增加原生只读诊断按钮，使用公开 Apple Events 按 FCP PID 获取第一项资源库，同时记录 NSError 与回复 errn；容器补齐用途说明。
- 实测：迁移后 FCP 正确显示新资源库路径。重启最初仍 nil；构建 4 的应用名请求回复 -10004，构建 5 的 all 索引格式错误回复 -1700，不能视为 SDK 项目读取失败原因。构建 6 改为整数索引后，资源库请求成功。该构建在点击诊断按钮前已记录 hasSequence=1；因此不能宣称按钮治好空值。
- 恢复验收：原项目 UID 0D11EC79-ED11-4688-97A9-CB78621857DD 与此前独立 XML 导出一致，事件/资源库链、3600 秒起始、8.68 秒时长、1/25 帧时长全部返回。切换副本再切回、关闭重开面板保持正确。旧 -600 在本轮新日志未再出现。期间变更多项，单一根因未隔离；仍需冷启动稳定性验证。
- 关键文件：native/Probe/ProbeViewController.m、scripts/build_probe.py、tests/test_native_probe.py、tests/test_probes.py、docs/evidence/subpop-host-recovered.json、docs/evidence/subpop-library-diagnostic.json。
- 验证：构建及签名通过，12 项测试通过（增加真实宿主 UID/时间与独立 XML 导出对照档案回归）；不是字幕完整闭环。未修改 VinciSub 和测试字幕。当前探针及原测试项目保留打开。
- 剩余：冷启动稳定性与单一根因；选区语义、角色/片段、音频权限、原时间线 ASR 写回。当前 Codex 工作区绑定旧路径，迁移后普通沙箱不支持符号链接根；后续会话从新路径打开。

## 2026-09-12：时间线选区对照验证

- 需求：读取交接并继续验证选区读取。新工作区路径权限已正常。
- 实测：在原隔离项目用 R 建立 2–4、3–6、1–5 秒范围，Option-X 清除，再取消浏览器选择重试。UI 范围确实变化；SDK 初始化、手动和后续回调均返回 start=3600、duration=8.68。选区读取未通过，不能据此回退全项目。
- 限制：SDK 播放头一度与 AX 固定播放头不一致；后续回调又更新，焦点/浏览与时效原因未隔离。不把本轮负结果泛化为 SDK 无选区能力。浏览器两个项目的局部范围操作未生效，媒体范围正对照待测。
- 改动：保存 21 条宿主日志、6 个独立 UI 对照；更新验证和交接记录，新增有理数与 UID 的证据档案回归。未修改原生代码、安装、字幕内容或 VinciSub。
- 关键文件：docs/evidence/subpop-selection-comparison.json、docs/sdk-probe-validation.md、tests/test_probes.py。
- 验证：本轮真实宿主结果为选区未读通；构建/签名及 13 项回归通过，不当作选区宿主通过。
- 剩余：回调/浏览/固定播放头正对照、浏览器媒体范围、FCP 冷启动、拖放音频及写回闭环。保留原项目 2–4 秒范围和探针供复核。

## 2026-09-12：用户将当前版本改为整项目识别

- 需求：暂不做选区，每次直接识别整个视频。
- 决策：FCP 内按活动项目完整时间线识别；选区延期，不再阻塞当前版本。使用有效项目身份、sequence.startTime/duration 界定范围，不依赖 sequenceTimeRange。
- 改动：更新 DECISIONS.md、HANDOFF.md、README.md 和接入报告。现有代码只有只读探针和隔离样本离线识别，未声称产品整段识别已实现；未改历史证据或宿主数据。
- 下一步：验证整个项目对应的音频获取、时间映射及原时间线字幕写回；不继续选区实验。

## 2026-09-12：整项目原生音频读取及识别通过受限样本

- 需求：继续整项目模式接入验证。用户协助一次跨窗口拖入 Subloom-Original；CUA 无法可靠定位跨窗口目标，不冒充自动拖放。
- 改动：增加 Objective-C AudioProbe 和“验证最近项目音频”按钮，核对活动 UID、整项目覆盖、简单单片段和 30 秒上限，安全解析 XML，记录直接文件/书签结果，AVFoundation 后台解码和完整采样检查；构建 8 已安装。离线识别探针支持原生 PCM 输入、长度/有限值检查与哈希。
- 实测：4 个 XML pasteboard 类型落盘；根节点版本分别 1.14/1.14/1.13/1.12。扩展内输出 8.68 秒、16kHz 单声道、138880 采样；构建 7/8 PCM 完全一致。直接打开失败513、书签解析失败256，但 AVFoundation 解码成功；机制未隔离。
- 识别：仅用扩展实际 PCM，由外部本地 CPU Qwen/对齐转出完整测试口播。仍只读借用 VinciSub 模型/解释器，禁字节码与联网；没有改 VinciSub 文件。不是插件自动调用闭环。
- 关键文件：native/Probe/AudioProbe.m、AudioProbeCLI.m、ProbeViewController.m；probes/recognize_fixture.py；tests/test_audio_probe.py；docs/native-audio-validation.md、docs/evidence/subpop-native-*.json、subpop-project-drop.json。
- 验证：编译/签名通过；终端沙箱中的 AVFoundation reader-start -11800，普通本机获准执行后19项回归通过；构建8真实宿主完整解码通过。脱敏证据不含书签凭据。
- 剩余：Caption/Title最短原时间线写回、校对同步、最终可听混音、多片段、持久访问、独立模型环境。未生成或写入新字幕；原测试项目和探针保留打开。

## 2026-09-12：真实 ASR 字幕导入原项目与校对回读

- 需求：继续验证整项目识别后的原时间线写回。
- 改动：新增受限 `probes/caption_fixture.py`，按标点分句、用真实词时间定边界并量化25fps，不按字数生成时间；新增断句和真实写回档案回归。
- 宿主实测：在隔离 Subloom-Original 通过原生 SRT 导入，选中文简体/相对时间；已有同角色字幕触发添加/替换/新角色选择，选新角色。三条进入 SRT 2，原两条保留。UID、sequence和asset-clip全部属性不变，起点0/84/146帧、时长80/56/68帧准确。
- 校对实测：FCP内将首句句号改感叹号，导出回读仅该文本变化；随后恢复句号并经UI确认。不是插件自动双向同步。
- 关键文件：docs/writeback-validation.md、docs/evidence/subpop-asr-writeback.json/.srt、tests/fixtures/fcp-12.3-asr-writeback.fcpxml、fcp-12.3-asr-proofread.fcpxml。
- 验证：构建/签名及24项回归通过；真实SRT导入和XML回读另行完成。未发布；未修改VinciSub；原项目保留新旧五条字幕，探针关闭，安装构建8。
- 剩余：手动SRT写回五个操作阶段仍不是已采用产品方案；Title最短路径、自动识别串联、校对同步、稳定身份/去重、快照新鲜度、最终可听音频和独立模型环境待验证。
