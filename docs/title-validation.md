# Title 原项目拖放验证

## 2026-09-12：构建 9，待真实拖放回读

范围：隔离 `Subloom-Original`（UID 与音频/Caption 证据一致），25fps，217 帧。复用真实 ASR 三句的 0–80、84–140、146–214 帧；不重新计算对齐。

已完成：

- 在 FCP 12.3 原项目临时添加自带“基本字幕”，导出其 effect UID/text/text-style-def 结构后立即撤销。UI 确认项目恢复 8.68 秒，仍为原音视频和五条 Caption。
- `probes/title_fixture.py` 生成只有 resources 和一个 clip 的交换文档。clip 的 spine 包含三条 Title 与 4/6/3 帧空隙，总长217帧；无 library/event/project 或媒体资源。字体大小28仅供低分辨率样本验证，并非产品样式。
- `native/Probe/Fixtures` 固定打包三个交换版本。1.14通过本地苹果 DTD 校验；1.12/1.13尚未分别做宿主或对应DTD验证。
- 构建9增加拖出区，AppKit 数据提供者按 FCP 请求返回对应 XML，记录请求类型/字节数与拖放结束 operation。拖动前限制活动项目 UID 和217/25秒长度；不能据此保证用户最终落点、目标未切换或时间线内容未更改。
- 构建/签名和27项回归通过，安装新版本，FCP面板实际显示拖出区。SDK读取当前原项目和8.68秒长度正常。

待验收：跨窗口实际拖放、宿主接受、落点偏差、包装是否成为单个片段及拆分步骤、Title内容与时间回读、原项目/音视频/五条Caption保留、单条校对。拖放 operation 成功本身不算写回证据。

苹果[发送数据到 Final Cut Pro 的拖放说明](https://developer.apple.com/documentation/professional-video-applications/supporting-drag-and-drop-for-data-sent-to-final-cut-pro)支持按版本提供 FCPXML，以及将 clips 拖到当前项目时间线；插入位置由落点决定。本实现把多条 Title 包在 clip 内以符合根级语法，是否保持时间和便于编辑必须实测，尚未采用为产品写回路线。

原始模板位于忽略目录 `.subloom/verification/basic-title-template.fcpxmld`，可能含原始媒体路径/书签，不提交。打包 fixture 没有这些信息。


## 2026-09-12：首次拖放操作核对

用户首次实际从FCP浏览器拖入了三条10秒“基础标题”，并非SubPop payload；当时没有title-drag-data日志。随后用户找到SubPop拖出区，因原项目已被临时标题延长到10秒，触发title-drag-refused（08:57:13Z）。这不属于FCP拒收payload。已通过FCP UI逐条删除三条误拖标题；UI及SDK确认原项目恢复8.68秒，mandarin与原五条Caption均保留，播放头回到起点。面板重新打开，已给出“独立小窗口三个按钮下方文字行，仅拖一次”的明确说明，等待再拖；仍未完成真实Title落轨。
