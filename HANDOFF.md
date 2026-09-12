# SubPop 交接

## 当前状态（2026-09-12）

最新界面：构建19（0.1.0）已安装。新增词库、模型管理下载/切换/移除、真实下载动画/暂停续传/SHA校验，78项测试通过。构建18的真实Title闭环证据保留；本轮没有新FCP媒体写入。详见文末、docs/MVP_PLAN.md及docs/evidence/subpop-vocabulary-model-manager.json。

**最新用户决策：暂不做选区，每次识别活动项目完整时间线。隔离单片段已完成项目拖入→原生音频解码→外部 CPU 识别→FCP 原生 SRT 导入原项目→校对快照回读。构建13已将连续单声道剪切/空隙/音量/静音渲染接入识别，真实CPU与后台队列通过；已安装并连接，新拖入面板验收待用户操作；无交互实时读取、完整产品一键流程和最终可听混音尚未实现。**

产品已从 Subloom 更名为 **SubPop**。仓库实际目录已改为 `/Users/chokamin/Desktop/SubPop`；旧 Subloom 路径为兼容链接。`.subloom` 缓存和历史测试项目保留原名。当前阶段为接入验证，理想闭环未通过，完整 MVP 未开发。

- 用户已明确授权安装和启动原生只读探针，无需重复确认。`/Applications/SubPop Probe.app` 已安装，FCP 12.3 标准版扩展菜单实际出现并能打开原生面板。
- 当前打开的是隔离 `Subloom-Verification-20260912` 资源库的 `Subloom-Original`，当前保留新旧五条Caption和三条独立Title，详见文末最新验收。未接触其他资源库或修改 VinciSub。
- host 身份、观察者回调、日志落盘通过；播放头和范围返回有效值，范围与 8.68 秒测试项目一致。构建 6 已恢复 activeSequence，原项目 UID 与此前独立 XML 导出一致；切换另一个项目再切回、重开面板均正确读取。根因尚未隔离，不宣称单一修复已证明。
- 更正旧结论：苹果概述明确提到 selected time range，不能凭 sequenceTimeRange 名称排除选区能力。已做局部范围/清除对照：UI 选区变化但 SDK 一直返回全项目；播放头新鲜度亦有疑点，选区读取未通过；现已由用户明确选择固定全项目模式，不再将选区作为前置条件。
- 前轮 SRT 原项目相对定位实测通过；同 UID XML 保留两者会新建项目。离线 Qwen 0.6B/对齐 CPU 实测通过；最新 ASR 三条字幕已通过原生 SRT 导入写入原项目，旧两条保留。仅有人工交接的链路通过，不是插件端到端自动验收。
- 38 项构建/单元/真实 XML 与证据档案回归通过；本轮另有 FCP 实际 SRT 导入和校对回读验收，详见 `docs/writeback-validation.md`。

## 下一步、风险与阻塞

1. 继续验证冷启动读取稳定性，并隔离恢复原因。构建 6 原项目/切换/重开已读通；直接 PID 读取第一项资源库成功。旧 -600 不再出现；不能只凭历史日志归因。新增诊断同时记录 NSError 与回复 errn。
2. 固定整项目识别：使用有效的 activeSequence 项目身份、startTime 和 duration 界定完整时间线，不依赖 sequenceTimeRange。选区、浏览器范围验证延期；历史负结果保留在 `docs/evidence/subpop-selection-comparison.json`。
3. 项目拖入 XML、原生 AVFoundation 完整解码和外部 CPU 识别已在单片段测试通过，见 `docs/native-audio-validation.md`。直接文件打开/书签解析仍失败，不能泛化权限机制；角色/子角色/组件禁用、Solo、效果、变速和复合片段仍待测。
4. Caption 原生 SRT 导入原项目通过，需五个操作阶段，新角色保留旧字幕；FCP 内改标点后导出回读通过，但自动双向同步未实现。Title一次拖放＋一次拆分已通过（文末）；用户已选Title优先；独立后台任务已连接，下一步新鲜输入及去重，不采用XML全项目替换。
5. MPS、其他帧率、长音频、冲突恢复未测；正式产品不得依赖 VinciSub 解释器和缓存。

## 关键文件和验证

- `native/Probe/`、`scripts/build_probe.py`：原生只读探针，SDK 项目内解包，未全局安装。
- `docs/sdk-probe-validation.md`、`docs/evidence/subpop-host-recovered.json`：最新宿主实测与限制。
- `docs/integration-validation.md`、`docs/evidence/asr-cpu.json`：第一轮隔离 SRT/XML/离线识别。
- 构建 `python3 scripts/build_probe.py`；测试 `python3 -B -m unittest discover -s tests -v`；提交前 `git diff --check` 并检查敏感信息，提交后检查状态。

## 目录迁移与当前会话

- 旧 `/Users/chokamin/Desktop/Subloom` → 新 `/Users/chokamin/Desktop/SubPop` 为兼容符号链接，不是第二份仓库；保护历史素材绝对路径。
- 上一轮 Codex 会话绑定旧工作区，曾受 symlink 根权限限制；本轮已从新真实目录打开，普通沙箱构建、测试和文档写入正常。
- 当前仍打开独立原项目和探针。未修改字幕内容或其他资源库。最新安装 `/Applications/SubPop Probe.app` 构建 8。

## 本轮续测（2026-09-12 16:02–16:08 CST）

新工作区权限正常。仅选区/焦点/播放头操作，未修改代码或安装；保存 21 条 SDK 日志及 6 个 UI 对照。选区读取未通过；有后续新播放头回调但范围仍全项目，不能泛化为 SDK 绝无选区。当前原项目保留 2–4 秒选区、浏览器无项目选中、探针打开。冷启动与浏览器媒体范围仍待测。

## 整项目音频续测（2026-09-12，构建 8）

用户完成一次跨窗口项目拖入，保存 4 种 XML。新“验证最近项目音频”按钮读取已保存 XML，无需再拖：核对 UID、完整项目覆盖、最多 30 秒的简单片段，在扩展内解码为 16 kHz 单声道 float32。实际 138880 个采样/555520 字节，8.68 秒。构建 7 和 8 均通过，PCM SHA 与外部 CPU ASR 输入一致，识别正确转出样本口播。未生成/导入新字幕。

权限限制：直接文件读取失败 513，带 security-scope 的书签解析失败 256，但 AVFoundation 解码成功；不宣称持久文件权限已解决。终端受限沙箱解码测试 -11800，获准普通本机执行后 19 项回归通过。未修改扩展 entitlements。

当前安装 `/Applications/SubPop Probe.app` 构建 8，原项目与面板保留打开。本轮未改变字幕/片段内容；正式产品仍需独立 Python/模型环境。`.subloom/verification/native-drop.fcpxml`、`native-audio.f32le`、`native-asr.json` 是本轮忽略的原始产物。优先读 `docs/native-audio-validation.md`。

## ASR 字幕写回续测（2026-09-12）

新增 `probes/caption_fixture.py` 从真实对齐生成三条 SRT。FCP 原生导入选择简体中文、相对时间、新字幕角色；真实 XML 回读确认原 UID、sequence/asset-clip 属性及旧两条字幕不变，新增三条时序精确。校对时把第一条句号改感叹号，导出回读确认唯一文本差异，再恢复句号，UI 已核对。

当前原项目保留五条字幕（旧 SRT 两条＋新 SRT 2 三条），探针已关闭，安装版本仍8。字幕生成和导入仍为外部测试流程，没有插件直接写入或自动校对同步。读 `docs/writeback-validation.md` 获取真实操作阶段、证据和限制；接下来可比较 Title 路径，不重复把手动导入当作自动化。

## Title 路径准备（2026-09-12，构建9）

已取得FCP自带基本字幕模板，临时插入随后撤销；原项目恢复8.68秒和五条Caption。新增Title拖出区域与三个版本的固定ASR片段payload，1.14 DTD、构建/签名及27项回归通过；构建9已安装并在FCP打开。当前等待用户将拖出行放到原项目起点上方（跨窗口拖放工具限制），尚无真实落轨结论。详见docs/title-validation.md。收到用户完成后，先核对日志和时间线，再导出XML对照原项目UID、媒体和五条Caption；不要重复请求已完成的拖放。


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


## 2026-09-12 构建18：真实输入、草稿恢复与Title闭环

用户20:36已拖入正确的Subloom-Original 1（UID810BBE85-2CFB-4719-906E-BEA30A757510，8.68秒），原构建17误报不支持。XML与宿主身份/时长一致；实时界面重复查询SDK时又误报未打开。将身份/时长取自时间线观察回调的一致快照，界面、恢复、提交/拖出保护共同使用；不取消项目/时长匹配保护。SDK内部失配原因未进一步隔离，不将推断写作已证明。

诊断增加“重新检查上次拖入”：只恢复真实最近一小时drop记录，保留原导入时间；若其后已有非取消Title拖出则不恢复。此次使用用户实际12:36:26Z输入重检，未制造新拖放。修复后的新receivePasteboard回调仍未单独重新手动触发。

面板真实请求96484d27-e9f9-4792-a29d-b91fc84ffc81，job967ccaea-cdff-4943-9d6f-6759e90ad8cf，Qwen3-ASR1.7B，3句。首句校对为“大家好，欢迎使用中文字幕工具！”，苹方36号；关闭重开实际恢复同一请求/任务、文字、字体字号，没有重新识别。用户已将紫色输出拖回副本起点，已通过FCP菜单拆成3条Title，不能再要求用户做这次拖放。

实际FCP字体参数正确，但36号在640x360画面过小；FCP中将三条调成72号并视觉确认下方可读。生成器通用默认字号和面板默认改72，保留原28/36等档位并增加72/96/120。该字号是在宿主落轨后调整，不能声称紫色条此次直接输出72。工程回读mvp-host-after-titles.fcpxmld证明三个Title offset帧0/84/146、duration帧80/56/68、position0 -40、字体PingFang SC及72号，原视频/原两条Caption和项目UID/起点/总长保持。原Subloom-Original未改。此次没有FCP音频共享。

脱敏前后XML与回归：tests/fixtures/fcp-12.3-mvp-{before,after}.fcpxml、tests/test_mvp_host.py；完整证据docs/evidence/subpop-mvp-host-session.json。原生harness新增观察状态匹配、不同UID、无效/变化时长与未收到观察状态拒绝测试。构建18最终文件需要使用MacOS26.5 SDK构建：SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk python3 scripts/build_probe.py（本机默认27 SDK与linker出现不兼容；未改全局开发工具设置）。

下一步使用真实普通口播剪切/背景音乐长素材验收质量与性能，不把派生30分钟稀疏素材当连续30分钟质量测试；已有功能与高级不支持范围见docs/MVP_PLAN.md。本轮任务/拖放都已完成，不应再次要求拖相同输出。


## 2026-09-12 构建19：词库与模型管理、范围文案

用户要求先接词库，再加模型管理和首次下载动画；中途询问“30分钟内口播/教程”是否内容限制，已解释它是优先验收场景，实际限制是30分钟/时间线结构。主界面改“音频不上传 · 字幕可逐句编辑”，“设置”改“帮助”，帮助内说明类型不限及真正限制。

新native/Probe/Preferences.inc在现有FCP窗口附属sheet提供词库（启用/保存/取消/去重/100词2000字/每词64字，非法输入保留草稿）和模型管理（两款状态/大小/使用/下载/移除确认）。词库保存在扩展NSUserDefaults中，原生任务requestVocabulary随request/pendingSession固定，结果校验vocabulary一致；probes/vocabulary.py同样验证，worker→run_job→Qwen transcribe context真实传入，不硬替换文字。

模型管理为worker协议3，模型请求与识别任务串行，下载独立进程。probes/model_download.py显式访问固定Qwen官方版本；config/models.json补共用aligner仓库/revision和全部文件SHA（来自此前固定版本独立模型的哈希），大小/SHA验证后原子发布，.part续传，网络/文件错误可重试，取消保留进度，移除识别模型保留共用aligner。新模型首次下载包括aligner。动画为原生忙指示器和随真实字节更新的进度条，含速度/大小，完成状态立即满条；遵守系统减少动态效果设置。普通识别仍离线。CLI安装复用同一下载器。

实测：FCP词库输入“中文字幕工具/USB-C/3.5%/重复词”保存去重为3，重开保留；测试完成清空词库，不留下人工提示词。后台旧隔离XML明确测试请求d5452b08-30b1-4aff-9e1c-88d97824f55c/job26198f7b-a585-4219-be9f-cac64a79629b，0.6B带三提示真实ASR ready3；不是新的FCP拖入和写回。两模型管理切换真实通过，最终选择恢复1.7B。

下载实测：先仅备份/移走0.6B config，FCP点击下载从官方补齐、验证成功f747c758-92e2-4ebf-9972-40f5a06240b3。然后保留完整权重备份测试大文件下载、动画和暂停9746507d-30e8-49d7-b835-6b1dd1e9de52（129499136 bytes partial）；再次下载继续增长，第二次暂停的ID和字节见证据。最后恢复本机完整权重，再真实补齐config和完整SHA校验855b30ac-2ffa-4732-bcc2-a2e0e356ab74；两个模型均可用，.part清理，无权重备份遗留。不是完整多GB冷机首次安装性能测试；缺失共用aligner安装用小文件传输回归测试验证。临时config备份仍在verification，不影响模型。移除保护仅临时目录测试，不删除用户现用模型。

78项回归和原生词库/编辑harness通过，安装与深度签名验证通过。新增tests/test_vocabulary.py、tests/test_model_download.py；证据docs/evidence/subpop-vocabulary-model-manager.json。没有修改FCP媒体/时间线，没有触发FCP共享，没有使用或改动奇奇字幕的数据。词库规则只读参考其独立模块，SubPop自行运行。

未完成的整体产品边界：连续自然长素材质量/性能、复杂时间线支持、参考脚本/优化规则、GPU、公证跨机完整安装包。本机首次模型下载界面已具备，但独立Python环境仍是当前安装前提，不能称全新机器无依赖发行版。

构建19最终重开实测：仍选择1.7B，模型管理恢复100%/可用；词库65字单词被拒绝，确认错误提示后原输入完整保留，取消后词库仍0。完成时模型管理窗口打开、两个模型可用，无运行任务。


## 2026-09-12：构建20取消单次30分钟限制

用户明确取消单次项目30分钟上限，覆盖此前MVP时长边界。移除原生拖入1800秒、project.inspect的1800秒、Title生成108000帧三处上限；仍校验有效正时长、帧边界、项目身份、字幕范围与结构。帮助/README/MVP计划同步。保留30秒解码和25秒ASR分块、取消、5000片段/XML大小保护与worker4小时处理超时（处理运行时间，非视频时长）；长项目仍受本机资源影响，当前整段PCM占用随时长增长。

构建20使用MacOS26.5 SDK构建、安装和深度签名验证通过。78项Python回归通过；新增1801秒/45分钟/2小时规划和三版本片尾Title回归，原生harness证明2小时输入接受、零时长拒绝。真实后台0.6B任务29449269-86eb-4aca-9062-f9477ef3dae2处理2700秒派生快照完成，43200000采样/172800000字节，片尾3条字幕且三版本包装时长2700秒。素材为2691.32秒静音+8.68秒讲话，不是连续45分钟自然素材质量/性能验收。证据docs/evidence/subpop-no-duration-limit.json。未写FCP项目、未触发共享。旧扩展/容器/空闲worker已重启，新界面连接正常并保留1.7B选择。


## 2026-09-12：构建21帧率适配及AAC分段边界

用户实际未命名项目报conform-rate，要求修正。失败job e3f38972-7e9d-46d8-9108-8c8c44a14bd9内为scaleEnabled="0"，项目30fps、源格式528/16000秒。按本地官方FCPXML1.14 DTD（默认scaleEnabled=1），只接受显式0且空节点/已知属性/单个conform-rate；缺省、1、未知结构及timeMap继续拒绝。移除该标记前后实际音频plan完全一致。

真实完整解码进一步发现AAC包超出30秒范围48个样本，旧decoder达到容量保护取消（readerStatus4）。AudioProbe.m按输出sample presentation timestamp裁剪到请求区间，保持完整性检查与最多16采样resample尾差，增加失败采样数/reader状态诊断。实际1334.2秒项目完整解码成功：21347200采样、85388800字节，SHA5075bd871110093a526924877dbdb5629905932adc6a232a9be153082203b8e5；证据docs/evidence/subpop-conform-rate.json。未重跑完整22分钟ASR，不宣称质量/最终字幕验收。

81项回归通过，包括帧率适配白名单/缺省缩放拒绝/真实变速拒绝、合成48k AAC的30秒和后续1秒边界；原生harness通过。构建21使用26.5 SDK构建并安装/签名验证；旧空闲扩展、容器、worker重启。不改用户媒体或FCP时间线，无共享。用户目前使用隔离库内未命名项目，原始Subloom-Original仍受保护。


## 2026-09-12：构建22字幕量化边界与失败恢复

用户22分钟真实识别失败Quantized captions overlap。原job164f6cec-10e2-4057-bbdd-bc568f850d09实际已完成1.7B识别（59段5490词），仅generate-titles失败。逐项修复后还发现断句切开aligner词、整条零时长“呜”、跨ASR块70ms对齐重叠。caption_fixture.py在真实token结束处断句；零时长/跨块实测重叠合并保留文字；纯帧取整重叠用实测间隙中点附近的共享边界，保证至少1帧，不够时合并。每段内部真实词重叠、文字不一致、范围错误仍拒绝。未改原始ASR文字/时间。

run_job提取共用finalize，失败在generate-titles的完全相同snapshotSHA/UID/model/audioMode/vocabulary重试可复用ASR；验证输入hash、snapshot相等、PCM长度/hash及源媒体mtime未晚于原任务开始，并拒绝链接文件。仅重新生成输出，不重跑模型。新增test_job_recovery与4项字幕边界测试；86项全套通过，最后增加媒体mtime保护后的专项测试通过。

后台恢复job f04711a8-fc33-498e-a157-91f49d7ca451 ready562；构建22安装/签名后FCP重检实际旧drop并点击开始识别，真实面板新job eb2097e8-bb6a-4720-8796-b68a8e593484复用原job ready562，全部文字拼接逐字相同且无时间重叠。原生562行编辑/三版本样式时间回归通过；1.14输出通过官方1.14DTD（1.12/1.13对应DTD本机未提供，未宣称同版本DTD验收）。证据docs/evidence/subpop-caption-boundaries.json。主面板已显示“字幕已准备好”及拖回条，保留1.7B，用户不需再次拖入/重识别。尚未对562条做实际落轨和逐句质量校对。没有FCP时间线写入或共享。
