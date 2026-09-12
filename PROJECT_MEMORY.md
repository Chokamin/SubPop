# 项目记忆

## 2026-09-12：独立初始化与第一轮接入验证

- 需求：原生 FCP 工具 Subloom，先核实接入能力和原时间线字幕闭环，再做完整界面；保护 VinciSub 和现有资源库。
- 改动：建立独立 Git 仓库及四份协作文档、README、能力报告、隔离测试 XML/SRT 生成器、严格限定简单片段的 FCPXML 回读探针、离线 Qwen 识别探针与回归测试。
- 关键文件：`probes/make_fixture.py`、`probes/readback.py`、`probes/recognize_fixture.py`、`tests/test_probes.py`、`tests/fixtures/fcp-12.3-caption-readback.fcpxml`、`docs/integration-validation.md`、`docs/evidence/asr-cpu.json`。
- 本机：arm64、macOS 27.0、Xcode 26.6、两套 FCP 12.3；本轮仅标准版实测。官方 SDK 下载页为 1.0.3，未获得有效安装包，未安装/构建扩展。
- 验证结果：8 项单元/档案回归测试通过；夹具按 FCP 自带 1.14 DTD 校验通过。FCP 隔离原项目内两条 SRT 中文字幕相对定位准确，实际导出含中文简体角色；同 UID XML 修改导入弹出替换/保留两者，后者新增项目、原字幕不变。源路径来自实际 FCP 导出，ffmpeg 内存解码、Qwen 0.6B/对齐离线 CPU 实测通过。ASR 结果未写回，不称完整闭环。
- 安全与范围：全部 FCP 写入仅独立 Subloom-Verification-20260912 资源库；未写用户已有项目。VinciSub 只读借用解释器和模型，禁用字节码与联网，媒体独立复制，Git 工作区仍干净。未发布 GitHub、未购买。结束关闭测试资源库并确认 FCP 未载入任何项，保留独立测试数据供续测。
- 剩余问题：SDK 安装/原生扩展运行；当前选区、自动可听和多角色；Title、精确自动写回及校对同步；MPS 与复杂映射。未擅自采用文件导出导入作为产品方案。后续先补齐探针再交用户选择可行路径。
