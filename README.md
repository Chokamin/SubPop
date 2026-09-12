# Subloom

用于 Final Cut Pro 的本地简体中文字幕工具，当前处于**接入验证阶段**，尚无可安装的 Workflow Extension 或完整 MVP。

请先读 [HANDOFF.md](HANDOFF.md)。完整能力、证据等级和未完成项见 [接入报告](docs/integration-validation.md)。

## 本轮交付

- 独立 FCP 12.3 测试资源库、25fps／01:00:00:00 起点项目。
- 原生 SRT 插入当前时间线及 XML 导出回读实测。
- 同 UID XML 修改导入：替换/保留两者对话框；保留两者新增项目。
- FCP 导出快照 → 本地源音频内存解码 → Qwen 0.6B CPU 转写/词级对齐离线探针。
- 有理数时间和拒绝超出探针范围的回归测试。

这些不是“一键生成到原时间线”验收。测试中的导出和导入是验证操作，未选为产品流程。

## 测试

`python3 -B -m unittest discover -s tests -v`

`probes/make_fixture.py` 生成测试 XML/SRT，要求 `.subloom/verification/mandarin.mp4` 已存在。该媒体是从 VinciSub 测试媒体复制的独立副本。

`probes/readback.py` 只解析一个普通 dialogue asset-clip 的实验项目，拒绝组件、变速、嵌套和效果；不推断角色独奏或最终混音。

`probes/recognize_fixture.py --xml … --asr … --aligner … --output …` 使用已安装 qwen-asr、torch、numpy、opencc 与 ffmpeg，仅允许本项目隔离样本；离线模型路径必须显式传入。输出词级时间，不实现产品级断句或写回。
