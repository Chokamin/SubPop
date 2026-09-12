# Subloom 交接

## 当前状态（2026-09-12）

独立项目和 Git 仓库已建立。阶段为接入验证，**理想闭环未通过，无可安装面板或完整 MVP**。

已先读取 VinciSub 四份协作文档及研究范围说明，未修改其文件、安装或数据。详细报告见 `docs/integration-validation.md`。

- FCP 12.3 标准版，隔离资源库测试；结束已关闭测试资源库，恢复原先无打开资源库状态。测试资源库保留供后续续测。
- 原生 SRT 通过 FCP 导入到当前 Subloom-Original，两条简体字幕时间准确、音视频位置保持；真实 XML 回读已保存。
- 同 UID 修改 XML 触发替换/保留两者；保留两者新增 Subloom-Original 1，不是原时间线增量更新。
- 从真实 FCP 导出快照读取简单源文件、内存解码、Qwen 0.6B/ForcedAligner 离线识别通过；实际 CPU，未写回 ASR 结果，不能报端到端通过。
- 8 项回归测试通过。有理数时间、父级 offset、拒绝变速/组件/复杂片段及真实导出档案回归。单元测试不是新一轮 FCP 实测。

## 本轮新增：SDK 原生探针（2026-09-12）

- 已从下载目录取得真实 SDK 1.0.3 并验证苹果签名，解包到 `.subloom/sdk-expanded`，无需全局安装 SDK。
- `native/Probe/` 原生只读扩展已构建为 `.subloom/build/Subloom Probe.app`；11 项测试通过。构建、签名和 bundle 检查不等于 FCP 宿主实测。
- 自动审批拒绝将本地自签名应用安装到 `/Applications/Subloom Probe.app`，要求本次用户确认。应用尚未安装或启动，未绕过拦截。
- 详细记录：`docs/sdk-probe-validation.md`。SDK 头文件确认没有选区、片段枚举、角色状态、字幕写入方法。

## 阻塞与风险

- 当前阻塞为安装并启动已构建的只读探针所需的用户明确确认；SDK 下载阻塞已解决。官方独立 Release Notes PDF 尚未读取（包内未找到），模板与头文件已读。
- FCPXTimeline 的 sequenceTimeRange 不是用户选区；公开列表未发现片段枚举、选区、字幕写入接口。SDK 头文件已确认；运行时行为仍待确认。
- 自动可听角色、角色多选、复杂时间映射、Title 拖回、编辑同步全部未实测。不要静默回退全部音频或 XML 替换。
- 本轮 ASR 临时只读借用 VinciSub 解释器与模型；正式产品必须独立安装和缓存。
- 仅 25fps、简单片段、原生 SRT 相对插入实测。MPS、其他帧率、长音频、字幕冲突和恢复待测。

## 下一步

1. 用户明确允许安装并启动后，将 `.subloom/build/Subloom Probe.app` 安装至 `/Applications`，启动容器 app，再在 FCP 打开扩展；验证 host/timeline/project UID 和观察者事件。只用原隔离资源库。
2. 在现有隔离资源库中验证选区有无可用接口；验证项目拖入扩展时真实 XML 内容和权限，不将浏览器范围当时间线范围。
3. 扩展测试多角色、子角色、组件启用、role off、Solo、恒速/曲线变速、复合/同步/多机位。比较实际可听音频，未知状态拒绝自动生成。
4. 原生 Caption 和 Title 各验证最短写回方式及真实用户步骤；只有可行路径完整实测后才交用户选择。
5. 路径获选再开发精简主面板、独立编辑/词库/脚本/模型窗口。

## 文件和命令

- `probes/make_fixture.py`：创建隔离 XML/SRT。
- `probes/readback.py`：只读单普通片段实验解析器，不是通用宿主适配。
- `probes/recognize_fixture.py`：离线识别实验，命令参数见 README。
- `.subloom/verification/`：忽略的测试资源库、媒体副本、原始导出、模型结果与下载失败文件。
- `tests/fixtures/fcp-12.3-caption-readback.fcpxml`：去除 bookmark/私人路径后的真实 FCP 导出结构。
- `docs/evidence/asr-cpu.json`：脱敏真实离线识别结果。
- 先 `python3 scripts/build_probe.py`，再 `python3 -B -m unittest discover -s tests -v`；Git 提交前 `git diff --check`，检查暂存差异，提交后检查状态。
