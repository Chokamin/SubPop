# SubPop 交接

## 当前状态（2026-09-12）

**最新用户决策：暂不做选区，每次识别活动项目完整时间线。隔离单片段已完成项目拖入→原生音频解码→外部 CPU 识别→FCP 原生 SRT 导入原项目→校对快照回读。构建11已通过面板提交旧快照→后台识别→自动回传Title；新鲜项目输入、完整产品一键流程和最终可听混音尚未实现。**

产品已从 Subloom 更名为 **SubPop**。仓库实际目录已改为 `/Users/chokamin/Desktop/SubPop`；旧 Subloom 路径为兼容链接。`.subloom` 缓存和历史测试项目保留原名。当前阶段为接入验证，理想闭环未通过，完整 MVP 未开发。

- 用户已明确授权安装和启动原生只读探针，无需重复确认。`/Applications/SubPop Probe.app` 已安装，FCP 12.3 标准版扩展菜单实际出现并能打开原生面板。
- 当前打开的是隔离 `Subloom-Verification-20260912` 资源库的 `Subloom-Original`，当前保留新旧五条Caption和三条独立Title，详见文末最新验收。未接触其他资源库或修改 VinciSub。
- host 身份、观察者回调、日志落盘通过；播放头和范围返回有效值，范围与 8.68 秒测试项目一致。构建 6 已恢复 activeSequence，原项目 UID 与此前独立 XML 导出一致；切换另一个项目再切回、重开面板均正确读取。根因尚未隔离，不宣称单一修复已证明。
- 更正旧结论：苹果概述明确提到 selected time range，不能凭 sequenceTimeRange 名称排除选区能力。已做局部范围/清除对照：UI 选区变化但 SDK 一直返回全项目；播放头新鲜度亦有疑点，选区读取未通过；现已由用户明确选择固定全项目模式，不再将选区作为前置条件。
- 前轮 SRT 原项目相对定位实测通过；同 UID XML 保留两者会新建项目。离线 Qwen 0.6B/对齐 CPU 实测通过；最新 ASR 三条字幕已通过原生 SRT 导入写入原项目，旧两条保留。仅有人工交接的链路通过，不是插件端到端自动验收。
- 34 项构建/单元/真实 XML 与证据档案回归通过；本轮另有 FCP 实际 SRT 导入和校对回读验收，详见 `docs/writeback-validation.md`。

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
