# SubPop 交接

## 当前状态（2026-09-12）

**最新用户决策：暂不做选区，每次识别活动项目完整时间线。本轮已通过隔离单片段的项目拖入→原生音频解码→外部 CPU 识别。下一步优先验证原时间线写回；尚未实现插件内一键流程或最终可听混音。**

产品已从 Subloom 更名为 **SubPop**。仓库实际目录已改为 `/Users/chokamin/Desktop/SubPop`；旧 Subloom 路径为兼容链接。`.subloom` 缓存和历史测试项目保留原名。当前阶段为接入验证，理想闭环未通过，完整 MVP 未开发。

- 用户已明确授权安装和启动原生只读探针，无需重复确认。`/Applications/SubPop Probe.app` 已安装，FCP 12.3 标准版扩展菜单实际出现并能打开原生面板。
- 当前打开的是隔离 `Subloom-Verification-20260912` 资源库的 `Subloom-Original`，探针面板保留打开。未接触其他资源库或修改 VinciSub。
- host 身份、观察者回调、日志落盘通过；播放头和范围返回有效值，范围与 8.68 秒测试项目一致。构建 6 已恢复 activeSequence，原项目 UID 与此前独立 XML 导出一致；切换另一个项目再切回、重开面板均正确读取。根因尚未隔离，不宣称单一修复已证明。
- 更正旧结论：苹果概述明确提到 selected time range，不能凭 sequenceTimeRange 名称排除选区能力。已做局部范围/清除对照：UI 选区变化但 SDK 一直返回全项目；播放头新鲜度亦有疑点，选区读取未通过；现已由用户明确选择固定全项目模式，不再将选区作为前置条件。
- 前轮 SRT 原项目相对定位实测通过；同 UID XML 保留两者会新建项目。离线 Qwen 0.6B/对齐 CPU 实测通过，但 ASR 结果未写回，不能称端到端通过。
- 19 项构建/单元/真实 XML、选区与原生音频证据档案回归测试通过；不是新一轮字幕写入验收。

## 下一步、风险与阻塞

1. 继续验证冷启动读取稳定性，并隔离恢复原因。构建 6 原项目/切换/重开已读通；直接 PID 读取第一项资源库成功。旧 -600 不再出现；不能只凭历史日志归因。新增诊断同时记录 NSError 与回复 errn。
2. 固定整项目识别：使用有效的 activeSequence 项目身份、startTime 和 duration 界定完整时间线，不依赖 sequenceTimeRange。选区、浏览器范围验证延期；历史负结果保留在 `docs/evidence/subpop-selection-comparison.json`。
3. 项目拖入 XML、原生 AVFoundation 完整解码和外部 CPU 识别已在单片段测试通过，见 `docs/native-audio-validation.md`。直接文件打开/书签解析仍失败，不能泛化权限机制；角色/子角色/组件禁用、Solo、效果、变速和复合片段仍待测。
4. 补齐 Caption/Title 最短原时间线写回及校对同步实验，列出真实操作步骤后再交用户选产品路径。不得静默采用复杂导出导入或 XML 全项目替换。
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
