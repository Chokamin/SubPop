# SubPop 交接

## 当前状态（2026-09-12）

产品已从 Subloom 更名为 **SubPop**。仓库实际目录已改为 `/Users/chokamin/Desktop/SubPop`；旧 Subloom 路径为兼容链接。`.subloom` 缓存和历史测试项目保留原名。当前阶段为接入验证，理想闭环未通过，完整 MVP 未开发。

- 用户已明确授权安装和启动原生只读探针，无需重复确认。`/Applications/SubPop Probe.app` 已安装，FCP 12.3 标准版扩展菜单实际出现并能打开原生面板。
- 当前打开的是隔离 `Subloom-Verification-20260912` 资源库的 `Subloom-Original`，探针面板保留打开。未接触其他资源库或修改 VinciSub。
- host 身份、观察者回调、日志落盘通过；播放头和范围返回有效值，范围与 8.68 秒测试项目一致。构建 6 已恢复 activeSequence，原项目 UID 与此前独立 XML 导出一致；切换另一个项目再切回、重开面板均正确读取。根因尚未隔离，不宣称单一修复已证明。
- 更正旧结论：苹果概述明确提到 selected time range，不能凭 sequenceTimeRange 名称排除选区能力。尚未做范围变化对照。
- 前轮 SRT 原项目相对定位实测通过；同 UID XML 保留两者会新建项目。离线 Qwen 0.6B/对齐 CPU 实测通过，但 ASR 结果未写回，不能称端到端通过。
- 12 项构建/单元/真实 XML 档案回归测试通过；不是新一轮字幕写入验收。

## 下一步、风险与阻塞

1. 继续验证冷启动读取稳定性，并隔离恢复原因。构建 6 原项目/切换/重开已读通；直接 PID 读取第一项资源库成功。旧 -600 不再出现；不能只凭历史日志归因。新增诊断同时记录 NSError 与回复 errn。
2. 隔离项目中改变时间线范围，记录 sequenceTimeRange 回调和值；验证无选区时语义和浏览器范围区别。
3. 实测项目拖入原生面板的 XML 类型、源路径、访问权限；角色/子角色/组件禁用、Solo、变速和复合片段仍全部待测。
4. 补齐 Caption/Title 最短原时间线写回及校对同步实验，列出真实操作步骤后再交用户选产品路径。不得静默采用复杂导出导入或 XML 全项目替换。
5. MPS、其他帧率、长音频、冲突恢复未测；正式产品不得依赖 VinciSub 解释器和缓存。

## 关键文件和验证

- `native/Probe/`、`scripts/build_probe.py`：原生只读探针，SDK 项目内解包，未全局安装。
- `docs/sdk-probe-validation.md`、`docs/evidence/subpop-host-recovered.json`：最新宿主实测与限制。
- `docs/integration-validation.md`、`docs/evidence/asr-cpu.json`：第一轮隔离 SRT/XML/离线识别。
- 构建 `python3 scripts/build_probe.py`；测试 `python3 -B -m unittest discover -s tests -v`；提交前 `git diff --check` 并检查敏感信息，提交后检查状态。

## 目录迁移与当前会话

- 旧 `/Users/chokamin/Desktop/Subloom` → 新 `/Users/chokamin/Desktop/SubPop` 为兼容符号链接，不是第二份仓库；保护历史素材绝对路径。
- 当前 Codex 会话绑定旧工作区，普通沙箱不支持 symlink 根；本轮后续经审批在新真实路径执行。后续应在 Codex 打开新目录，建立正确的工作区权限；不建议长期靠旧路径工作。
- 当前仍打开独立原项目和探针。未修改字幕内容或其他资源库。最新安装 `/Applications/SubPop Probe.app` 构建 6。
