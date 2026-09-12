# SubPop 交接

## 当前状态（2026-09-12）

最新界面：构建15已安装，三步流程、模型信息、隐藏诊断和单窗口后台结构；持久目录授权被自动审批拦截，已询问用户，待答复后验收自动启动。详见文末和 docs/interface-validation.md。

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
