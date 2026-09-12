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

## 2026-09-12：Title拖放路径准备

- 需求：继续比较整项目识别的原时间线写回路径。
- 改动：FCP自带Basic Title临时导出后撤销，新增受限title_fixture生成器、固定ASR XML资源、原生拖出区与版本协商日志；安装构建9。
- 验证：原项目8.68秒和五条Caption恢复；1.14 DTD、构建/签名、27项回归通过；FCP面板实际加载新拖出区。
- 当前：等待用户跨窗口拖入原项目起点上方；未将静态验证视为真实落轨。
- 剩余：宿主实际接受与精确时间、包装拆分与编辑、原内容保留、产品路线选择。详见docs/title-validation.md。


## 2026-09-12：首次拖放操作核对

用户首次实际从FCP浏览器拖入了三条10秒“基础标题”，并非SubPop payload；当时没有title-drag-data日志。随后用户找到SubPop拖出区，因原项目已被临时标题延长到10秒，触发title-drag-refused（08:57:13Z）。这不属于FCP拒收payload。已通过FCP UI逐条删除三条误拖标题；UI及SDK确认原项目恢复8.68秒，mandarin与原五条Caption均保留，播放头回到起点。面板重新打开，已给出“独立小窗口三个按钮下方文字行，仅拖一次”的明确说明，等待再拖；仍未完成真实Title落轨。


## 2026-09-12：真实 Title 拖入、拆分与校对通过

用户完成正确的一次拖放。08:58:36Z FCP请求com.apple.finalcutpro.xml.v1-14，原生探针发送1988字节；08:58:39Z会话结束。operation为NSUInteger最大值，不将其单独解释为成功。实际UI与独立XML确认clip连接在原mandarin上方、相对0秒，217帧；内部三句分别0–80、84–140、146–214帧，间隙4/6/3帧。原project UID、sequence属性、asset-clip属性和五条Caption属性/文本完全保留；浏览器新增SubPop ASR Titles Probe片段，不是新项目。

再执行FCP“片段→将片段项分开”，原时间线得到三条独立Title，空隙与精确时间保持，包装及gap不再留在原时间线。选首句在文本检查器将句号改感叹号，独立XML比对仅Title文字变化（除项目modDate）；随后撤销并以UI核对恢复句号。

当前原项目保留音视频、五条Caption、三条独立Title，总长8.68秒。真实拖放、拆分、校对快照已脱敏存入tests/fixtures/fcp-12.3-title-*.fcpxml，汇总docs/evidence/subpop-title-writeback.json。构建/签名及29项回归通过。安装版本仍9，无需用户再次拖放。

比较：已生成结果之后，Title为一次拖放，若要直接逐句编辑再执行一次拆分；SRT为先前记录的五个操作阶段。Title的绝对位置由实际落点决定，本次用户准确拖到起点。尚未验证偏移纠正、批量样式、重复写回/去重、其他帧率/复杂项目；自动ASR串联与双向校对同步未实现。此结果支持用户选择写回路线，不自动将Title设为产品默认。


## 2026-09-12：用户选择Title优先，独立识别任务与面板载入通过

用户明确选择优先Title，拖入后拆开并逐句编辑样式。建立SubPop独立.venv及模型普通文件（无跨项目链接），锁定93个依赖；VinciSub只读复制模型、不改其文件。新增probes/run_job.py，单命令串联原生CLI解码、CPU识别/对齐、分句和Title/SRT生成；每任务UUID、冻结快照、阶段状态、失败记录和结果哈希。实际8.68秒快照通过，PCM与此前扩展实测SHA一致，三版本Title字节与已落轨fixture相同。

构建10增加载入识别结果NSOpenPanel及校验、内存动态拖出数据；新增仅用户选择文件夹只读权限。FCP缓存旧进程，单独终止SubPop扩展后重开成功。文件选择器前两次未正确选中目录触发invalid-result，键盘选中后真实加载3版本、ready-to-drag（09:14:28Z）。无需再次拖入同样字幕。

31项回归和构建/签名通过，新增本地任务失败保护测试；真实独立ASR与FCP载入另行实测。当前安装构建10，面板已加载本次真实结果，原项目内容未改。未实现面板启动任务/自动结果回传、新鲜XML获取、去重或最终可听混音。当前输入是显式旧隔离快照，不宣称当前带Title时间线可直接重识别。下一步连接面板与独立后台任务；详见docs/local-job.md和docs/evidence/subpop-independent-job.json。


## 2026-09-12：构建11面板提交、进度与自动回传通过

新增probes/worker.py和原生服务连接/识别快照按钮。SubPop容器应用内选择项目根目录后启动独立Python worker；FCP扩展选bridge目录一次后，以文件队列提交最新已拖入XML（移除bookmark），轮询阶段并校验结果自动载入内存。无网络监听，固定工作区/命令/UID与哈希检查；权限为用户选择目录读写。

实测：初版容器直接启动Python停在初始化fopen，没有足够证据归因为特定权限；加入NSOpenPanel选择工作目录后成功，未改系统隐私设置。FCP面板09:24:56Z connected，09:25:03Z按钮提交8c734073-6422-49d7-9e4e-f6da5045df1e，09:25:04 starting、09:25:05 recognize，09:25:17自动ready-to-drag，jobID2052b020-12ef-4192-b192-d669b3198879。总约14秒，三版本Title与先前落轨fixture字节完全一致；不重复写入时间线。

构建/签名和34项测试通过，证据docs/evidence/subpop-panel-worker.json，说明docs/panel-worker.md。当前安装构建11、容器与worker运行，FCP面板已连接并持有新结果；原项目仍音视频＋五条Caption＋三条Title。

重要限制：输入明确是08:17:11Z已拖入旧快照，不是当前带Title项目实时音频；仍未解决最终可听混音、复杂项目、新鲜快照、字幕去重。扩展重开后需重连目录，容器重启需重新选择工作目录；识别取消/恢复未完成。用户不用再次拖入同样的测试字幕。下一步优先新鲜输入和重复生成保护，不能把本轮称完整产品一键识别。


## 2026-09-12：构建12新快照与重复Title保护准备

面板每次识别要求本会话新拖入（5分钟、一次消费），不再读取旧drop磁盘缓存；关闭手动载入和固定fixture拖出以免绕过检查。任务输出同样限本会话/5分钟/一次非取消拖出。新增snapshot.py将已验证静音Basic Title仅从音频副本剥离，保留原快照进行文字/时间重复与冲突比较；未知模板、嵌套音频/效果拒绝。重复或重叠冲突不生成可拖出的Title，不改原时间线。

构建/签名和37项回归通过。构建12已安装，容器worker已重启、FCP已connected；实测无新拖入时fresh-project-drop-required，旧快照不能启动。已请求用户把浏览器Subloom-Original拖到面板顶部说明区，等待完成后点击“识别刚拖入的项目”，预期对已有三条Title返回duplicate。不要要求用户把Title再拖入时间线。详见docs/snapshot-dedup.md。当前原项目未改。


独立后台补充实测：已有真实after-title-split导出经新归一化→原生解码→CPU识别，job037726ef-f9d6-4915-bee4-bfead5e6bc9a返回blocked-existing-titles/duplicate，3条精确匹配，无TitleProbe输出文件。证据docs/evidence/subpop-duplicate-job.json。不是新鲜拖入面板的实测结论。


## 2026-09-12：当前项目重新拖入后的面板重复拦截实测通过

用户重新拖入当前Subloom-Original，09:53:56Z收4种XML，均8187字节，新快照含3条Title与5条Caption。09:55:23Z点击“识别刚拖入的项目”，请求deb7a4c6-1652-4815-855e-f88629f2cba8，经原生音频副本解码/CPU识别，09:55:35Z面板显示blocked-existing-titles/duplicate：existingTitles=3、exactMatches=3、overlappingRows=3。任务98a284d6-d364-40d8-afec-94ccaf6b9280没有生成TitleProbe输出文件。

已通过FCP面板UI确认重复提示，原时间线仍为8.68秒、3条Title、5条Caption和mandarin。新快照脱敏保存tests/fixtures/fcp-12.3-fresh-title-drop.fcpxml，证据docs/evidence/subpop-fresh-duplicate.json。没有重写时间线，也无需用户再拖入同一项目。构建12保持运行，服务已连接，输入已消费、无可拖出新结果。

新快照→识别→重复保护已通过本受限样本；用户校对冲突仍只有此前真实导出档案回归，实时编辑后再拖入冲突的UI验收未做。实时变化监听、最终可听混音、复杂项目、通用时长/帧率仍未完成。

本轮构建/签名与38项回归通过；未修改原生代码或重新安装。


## 2026-09-12：时间线音量与禁用组件实测、音频属性检查

在隔离原项目内通过 FCP 音频检查器先设 −6 dB、导出后撤销；再关闭对白音频组件、导出后撤销。真实 XML 分别包含 adjust-volume amount=-6dB 和 audio-channel-source active=0。脱敏快照保存 tests/fixtures/fcp-12.3-audio-*.fcpxml；归一化仅去除已验证 Title 后，Python 读取器与原生 CLI 均拒绝这两种输入，不会忽略改动继续识别源音频。

补齐此前遗漏的 srcEnable=video/非法值与 audioStart/audioDuration 属性检查，两层均拒绝；这些属性用构造 XML 回归验证，尚非 FCP 对应操作实测。恢复快照 audio-restored 的 sequence 完整结构（属性、媒体、五条 Caption、三条 Title 与时间）与本轮之前 fresh-title-drop 一致，时长仍8.68秒。未写入新字幕。

构建/签名和42项回归通过。此次原生修改只在本地构建及 CLI 测试，未重新安装 /Applications 的构建12；Python worker 下次任务进程会读新代码。为操作主窗口已关闭扩展面板，重新打开后需重连服务及新拖项目。

下一步：真实剪切/J-L cut、多片段、角色禁用/Solo 与最终混音对照；本轮未实现最终可听混音，拒绝复杂音频不是已支持它们。可以先验证裁剪与时间映射，再设计音频渲染路径。


## 2026-09-12：真实切割、前置空隙与源偏移解码

在隔离原项目通过“修剪→切割”将 mandarin 在相对4秒切成4秒＋4.68秒，第二段 start=4s、offset=3604s，总长8.68秒。移除第一段时 FCP 保留4秒 gap（有连接Title），后段不前移。两种真实快照在 snapshot、readback 与原生 CLI 入口均拒绝，不会把后段误当完整项目。

操作细节：初始 Cmd+B 在当前键位配置下未切割，而是造成 enabled=0，随后菜单切割的两个片段也都禁用。此状态保留在证据中，不宣称该快照音频可听。两次撤销后独立导出发现残留禁用，第三次撤销并重新导出 audio-edit-restored-final 后，整个 sequence 与上轮 audio-restored 结构完全一致。最终脱敏恢复档案是 tests/fixtures/fcp-12.3-audio-edit-restored.fcpxml。今后关键编辑使用观察到的菜单命令，不假定快捷键。

另做明确标注的派生 CLI 实验：从真实第二段提取 source start=4s / duration=4.68s，启用、移除附属文字、改为独立单段项目。原生读取输出74880个16kHz样本，与完整PCM从第64000个样本起的尾段逐字节一致。证明该媒体的源偏移解码正确，不代表 FCP 最终混音或复杂项目识别已支持。无新ASR或字幕写回。

构建/签名及45项回归通过，原项目媒体＋5 Caption＋3 Title完整恢复。应用安装未更新，扩展面板仍关闭。下一步应验证角色/Solo及最终混音取得方式；多段拼接需保留gap、禁用状态及标题父级时间映射，不可直接解除现有拒绝条件。


## 2026-09-12：构建13整段时间线音频处理已接入识别

用户明确要求扩大每轮交付，不要只做单项探针。本轮实现 probes/timeline_audio.py：校验连续单声道对白asset-clip/gap，按源起点原生解码、按项目样本位置拼接、恒定−96至0dB衰减、片段/唯一组件禁用及仅视频输出等长静音。未知效果/关键帧/J-L/多通道/叠轨仍拒绝。原生CLI保持严格单段解码器；新worker任务负责规划和渲染，不以解除旧CLI拒绝条件代替实现。snapshot.prepare支持各片段/gap上的Basic Title时间换算；识别必须使用渲染后PCM，不再回退直接识别源文件。

FCP真实组合验收：启用片段在4s切割，前段−6dB，前段音频组件关闭，以及前置gap分别导出XML；基准/音量/静音WAV用于对照。音量比0.501187/约1，静音保留位置；重采样对齐1样本后有声相关>0.9996，仍有约0.707声道增益差异，未宣称逐字节等于宿主最终混音。四项操作已撤销，mix-restored整个sequence与基准精确一致，5Caption/3Title保留。

真实CPU任务05928c08-634b-42ef-a60d-a9b1f0d1c4be：双片段＋音量识别3句，duplicate拦截3条。派生gap快照移除已知静音Title后任务8c781d90-1419-4ed3-a30a-685b0cc53c97生成两句，100–140与146–214帧，不前移；三版本Title输出，1.14 DTD通过。真实新worker队列：silent请求8496bd0b-d300-4c0e-8327-e949b4bf33b5→blocked-no-audio（不加载ASR、不生成Title）；gap请求2529a727-4077-488c-907c-ad9505250dac→ready两条payload。源码新增校验失败终态和具体错误回传；面板增加静音结果处理，移除写死“三条Title”的拖拽文案。

构建/签名与54项回归通过。构建13已安装到/Applications/SubPop Probe.app，旧容器/worker停止，新容器通过目录选择启动，FCP实际加载新面板，服务connected。主项目8.68s保持不变，尚无本轮新字幕写入。新版面板最终新拖入按钮验收等待用户：已通过异步问题请求将浏览器Subloom-Original拖到面板顶部说明处；不要重复要求拖入Title。当前旧drop不能复用。若收到“已拖入”，直接核对新drop→点击识别→核对返回，再补充证据和提交。

详见docs/timeline-audio.md、docs/evidence/subpop-timeline-mix.json、subpop-timeline-jobs.json；四份mix真实XML已脱敏归档。此版本仍只允许固定隔离UID/原媒体/8.68s/25fps，不是通用多媒体项目产品；实时角色/Solo监听、完整宿主混音、长视频、任意帧率、多轨效果待做。


## 2026-09-12：构建14原生界面重组

用户反馈界面不友好，本轮直接实现并安装新界面，使用better-ui技能。导入项目/整段识别/拖回字幕三个阶段；专用拖放卡片（收到后校验UID）、一个主要按钮、服务状态、阶段提示和spinner；未满足新输入/活动项目/有效结果时禁用识别或拖出。JSON及探针按钮移到诊断弹窗。状态文案集中于ProbePresentation.h/.m，记录日志与任务提示分开，不被播放头事件覆盖。

容器窗口同样改为启动识别服务＋实际worker心跳反馈；容器和扩展授权默认打开正确目录，无需手输路径。FCP实测初版底部因宿主旧窗口尺寸截断，已收紧间距/高度并重新安装，最终截图全部操作和说明可见。实际检查未连接、默认目录连接、绿色连接状态、无输入按钮禁用及诊断弹窗。未向时间线写入或更改内容。

构建/签名及54项原有回归通过。构建14已安装并在FCP打开，容器服务运行；最新界面的新卡片拖入、识别/结果/异常全状态端到端仍待实测，不把已有功能回归算作完整新UI验收。详见docs/interface-validation.md。后续用户拖入时直接验证新版卡片和按钮，不再要求找旧面板顶部文字。旧构建13的待拖入问题已由本轮UI调整接续。


## 2026-09-12：构建15模型说明、单窗口后台结构，授权验收待用户

用户追问没有模型选择、两个窗口及“启动服务”的含义。已说明当前只有Qwen3-ASR 0.6B接入；主界面直接展示模型名，“模型与设置”说明已安装模型和CPU，未冒充支持切换。容器改成LSUIElement后台agent，无常规服务窗口；扩展通过subpop-probe://start启动，设计为分别记忆任务目录/工作目录的security-scoped bookmark，重开自动恢复。首次必要授权仍使用系统NSOpenPanel，准备/等待提示代替服务管理术语。

构建15已编译签名安装，LaunchServices注册链接，FCP实际显示新模型信息和准备按钮。旧容器worker已停止；当前后台未启动。54项回归通过，更新原生bundle测试验证后台agent和唯一scheme。

关键阻塞：点击任务目录“允许并继续”被CUA自动审批拒绝：“授予SubPop对本机任务文件夹及模型的持久访问权限；尚未得到用户对具体资源和范围的明确批准”。没有绕过，没有成功保存授权。已通过request_user_input_async请求用户确认记住 /Users/chokamin/Desktop/SubPop 及 .subloom/verification/bridge 的访问（读取模型/程序、读写任务结果），选项允许记住/仅本次。不重复询问已回答的问题；若允许，继续当前NSOpenPanel，再验证后台首次模型授权及完全关闭后自动恢复。若仅本次，先移除持久保存/恢复行为再操作。当前UI文件选择器停留待授权；不能声称后台自动启动或单窗口冷启动已实测通过。

本轮原项目内容未改。docs/interface-validation.md保留构建14实测和构建15新增及限制。


## 2026-09-12：构建15持久授权与冷启动实测通过

用户明确回复“允许”，授权记住工作目录 /Users/chokamin/Desktop/SubPop 和其中 .subloom/verification/bridge 的访问。通过实际系统文件选择器先后确认两个默认目录，没有写入或伪造书签。首次启动后台worker PID 67024，实际心跳idle，FCP显示“● Qwen3-ASR 0.6B · 本机就绪”。模型说明弹窗核实当前Qwen3-ASR 0.6B、本机CPU、尚不支持切换；随后关闭。

冷启动验证：关闭扩展面板，终止已核实的扩展66604、后台容器66951和worker67024；仅通过FCP“窗口→扩展→SubPop Probe”重开。新worker PID 67569自动出现，心跳idle；FCP重新显示本机就绪，未再出现两个目录选择器，也未手动启动容器或Python。实际截图确认主界面完整可见，无输入时开始识别禁用。首次授权和重新启动的证据见docs/evidence/subpop-background-startup.json。

本轮未改源码/构建，仍为已通过54项回归的构建15；本轮新增的是实际首次授权、后台冷启动与模型说明验收，不宣称新跑54项测试。仅修改验证文档，不向FCP时间线写入。当前新卡片拖入→识别→结果全流程仍待新输入；测试范围仍为固定8.68秒Subloom-Original，不是任意视频产品。下一步继续产品功能，不重复要求目录授权。


## 2026-09-12：构建17，本机日常MVP候选版（宿主闭环待新拖入）

用户要求实现多模型、改善UI，并明确升级目标为“直接做到日常可用MVP”，使用场景为30分钟内口播／教程、有剪切和背景音乐。本轮沿用better-ui技能、无子代理。已下载官方固定版本Qwen3-ASR1.7B至独立asr-1.7b目录，0.6B/1.7B均实际CPU识别完成三条字幕；模型清单共享给Python与原生菜单，任务绑定modelID、可用状态检查与结果身份校验，不悄悄回退。主面板真实切换1.7B，构建17重开自动连接并保留选择，无重复目录授权。

通用处理新增probes/project.py，移除生产任务固定UID／媒体／8.68s限制，支持最长1800s、常见整数和分数帧率、普通剪切／gap／连接音频、单声道／立体声、静态增益和启用状态。对白模式排除音乐/效果角色（被排除音乐的淡入淡出不参与处理），全音频模式混合所有支持的声音。音频效果、变速、复合/多机位、J/L、多组件仍明确拒绝；不是宿主实时Solo混音。识别按20–25s低能量边界切段，映射回项目时间。

真实验证：派生30分钟时间线（前1791.32s静音＋末8.68s语音）渲染115200000字节，尾部与短片PCM逐字节相同；后台长任务de2603dc-7375-4fe3-b05a-1c170d709e0b返回3条字幕，未把静音后的字幕前移。86.8s十次重复语音片段／4识别分段，任务30c623f2-38f5-4e57-aa3c-a24158a4bf1d返回31条（分段可能拆句），不是连续自然口播准确率评测。实际立体声WAV连接音乐对照：对白模式与无音乐基准完全一致，全音频模式有音乐能量；AVFoundation在48kHz立体声重采样时少5个尾样本，原生解码新增最多16样本（1ms）的尾部补齐/截断，较大不足仍拒绝。取消请求aae57a0c-685c-4589-928c-86bc649c715d返回cancelled，采用独立进程组终止识别和解码子进程。

UI：原生模型下拉、音频范围、较紧凑层次、滚动页面、取消/错误/分段进度、字幕校对表格、字体字号、下方Title。实现关闭面板恢复请求、持久校对草稿（只把文字/样式恢复到已验证时序），需要宿主实测。AppKit无窗口回归直接调用真实controller校对方法，三版XML文本/字体字号更新、时间保持及XML转义通过；生成的新版下方Title通过1.14DTD，但尚未新落轨确认视觉位置。尝试FCP浏览器复制后粘贴未提供所需XML，该入口已从构建17移除。

构建/签名、67项回归、AppKit校对程序、真实双模型/长任务/立体声/取消验证通过。构建17（0.1.0）已安装，后台自动连接，主界面模型记忆1.7B。未执行任何FCP共享/WAV导出。用户询问反复“共享成功”通知：后台任务全部闲置，mix-baseline.wav修改时间18:13:35、此时20:11；证据表明不是本轮新导出，无法确定通知重复原因，没有修改系统通知设置。

**仍未宣称日常MVP全部验收通过。** 已打开隔离库Subloom-Verification-20260912里的Subloom-Original 1（副本，8.68s，mandarin＋两条旧Caption，无Title），原Subloom-Original原内容不变。已异步请求用户把浏览器的“Subloom-Original 1”拖到SubPop“拖入你的项目”区域；尚未收到新输入，不重复提问。如果用户回复已拖入，立即检查新drop和activeUID，再点击识别（当前1.7B）→核对表格→改一句/字体字号→关闭重开验证草稿→拖回副本起点并核对实际Title。跨窗口拖放工具仍不可靠，允许请求必要手动拖放，但不要用旧XML伪造新拖入。此闭环是最终MVP验收剩余阻塞。

开发计划重写于docs/MVP_PLAN.md，说明六模块已实现/证据/待验收及高级能力边界；README从历史探针状态改成真实本机候选版。新增模型补齐和本机安装更新脚本，仍依赖当前workspace、独立.venv及本机模型，不是公证的跨机发行包。全部证据索引docs/evidence/subpop-mvp-validation.json。

补充：最终DTD检查发现下方Title的adjust-transform节点顺序错误，已改为置于text/style之后，增加官方DTD回归；复测67项通过。


## 2026-09-12：构建18真实宿主闭环

用户真实拖入被17误拒；18统一使用时间线观察回调的项目身份/时长，避免UI重复SDK查询导致状态不一致。增加明确的真实旧drop重检（保留时间，1小时，已拖出结果不重用）。使用本轮实际输入完成1.7B识别、3句面板校对、苹方36号、关闭重开同任务草稿恢复。用户已拖回，FCP拆分和XML回读通过，原视频和两Caption保留。视觉发现36偏小，FCP三条调72后可读，通用默认字号改72并扩充档位。核心文件ProbeViewController.m/title_fixture.py/PresentationTests.m/test_mvp_host.py；证据subpop-mvp-host-session.json。68项回归、构建/签名及原生harness通过。原始Subloom-Original未改，无音频共享。新修复后直接拖入回调与自然连续长素材验收仍未完成；不得重复要求已完成的输出拖放。详情HANDOFF末尾。


## 2026-09-12：构建19词库和模型管理

用户要求词库、模型管理和首次下载动画；并指出用途说明像视频类型限制。新增Preferences.inc原生词库/模型sheet、vocabulary.py提示规则、model_download.py固定版本SHA校验/续传/取消/独立进程，worker协议3串行管理模型与ASR。词库任务冻结到Qwen context，真实0.6B旧隔离快照ASR ready3；FCP保存/去重/重开验证后清空测试词。两模型切换、真实配置下载、大文件暂停/续传/动画通过；完整权重备份恢复，最终两模型可用/选择1.7B，非完整多GB冷机首装测试。78项测试及原生harness通过。主界面“帮助/词库/模型管理”，底部“音频不上传 · 字幕可逐句编辑”，真正30分钟/复杂结构限制留帮助。证据subpop-vocabulary-model-manager.json；无FCP媒体写入/共享，无奇奇字幕数据修改。构建19已安装，详见HANDOFF末尾。


## 2026-09-12：构建20取消单次30分钟限制

用户明确取消单次项目30分钟上限，覆盖此前MVP时长边界。移除原生拖入1800秒、project.inspect的1800秒、Title生成108000帧三处上限；仍校验有效正时长、帧边界、项目身份、字幕范围与结构。帮助/README/MVP计划同步。保留30秒解码和25秒ASR分块、取消、5000片段/XML大小保护与worker4小时处理超时（处理运行时间，非视频时长）；长项目仍受本机资源影响，当前整段PCM占用随时长增长。

构建20使用MacOS26.5 SDK构建、安装和深度签名验证通过。78项Python回归通过；新增1801秒/45分钟/2小时规划和三版本片尾Title回归，原生harness证明2小时输入接受、零时长拒绝。真实后台0.6B任务29449269-86eb-4aca-9062-f9477ef3dae2处理2700秒派生快照完成，43200000采样/172800000字节，片尾3条字幕且三版本包装时长2700秒。素材为2691.32秒静音+8.68秒讲话，不是连续45分钟自然素材质量/性能验收。证据docs/evidence/subpop-no-duration-limit.json。未写FCP项目、未触发共享。旧扩展/容器/空闲worker已重启，新界面连接正常并保留1.7B选择。


## 2026-09-12：构建21帧率适配及AAC分段边界

用户实际未命名项目报conform-rate，要求修正。失败job e3f38972-7e9d-46d8-9108-8c8c44a14bd9内为scaleEnabled="0"，项目30fps、源格式528/16000秒。按本地官方FCPXML1.14 DTD（默认scaleEnabled=1），只接受显式0且空节点/已知属性/单个conform-rate；缺省、1、未知结构及timeMap继续拒绝。移除该标记前后实际音频plan完全一致。

真实完整解码进一步发现AAC包超出30秒范围48个样本，旧decoder达到容量保护取消（readerStatus4）。AudioProbe.m按输出sample presentation timestamp裁剪到请求区间，保持完整性检查与最多16采样resample尾差，增加失败采样数/reader状态诊断。实际1334.2秒项目完整解码成功：21347200采样、85388800字节，SHA5075bd871110093a526924877dbdb5629905932adc6a232a9be153082203b8e5；证据docs/evidence/subpop-conform-rate.json。未重跑完整22分钟ASR，不宣称质量/最终字幕验收。

81项回归通过，包括帧率适配白名单/缺省缩放拒绝/真实变速拒绝、合成48k AAC的30秒和后续1秒边界；原生harness通过。构建21使用26.5 SDK构建并安装/签名验证；旧空闲扩展、容器、worker重启。不改用户媒体或FCP时间线，无共享。用户目前使用隔离库内未命名项目，原始Subloom-Original仍受保护。
