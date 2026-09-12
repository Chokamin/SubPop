# 独立本地识别任务（构建10）

当前为接入验证，不是通用MVP。输入仍是明确指定的旧隔离项目XML快照，仅支持Subloom-Original、25fps、8.68秒、一个普通dialogue片段。当前活动项目已有Title，尚不能直接作为新音频输入；不会静默忽略复杂内容。全项目音频可听状态仍待验证。

## 已实测

- SubPop独立`.venv`，Python3.12.11，93个依赖安装自包仓库；运行不引用VinciSub解释器。`requirements-asr.lock.txt`锁定实际安装版本，仅在当前macOS arm64环境验证。
- 两个Qwen模型从此前已验证的本机文件只读复制成`.subloom/models/asr`和`aligner`的独立普通文件，约3.72GB；无符号链接。未修改VinciSub。模型来源revision与文件SHA记录在`.subloom/models/manifest.json`。
- `.venv/bin/python -B -m probes.run_job --xml .subloom/verification/native-drop.fcpxml`在本机实际通过：原生CLI解码→本地CPU ASR/对齐→分句→三版本Title XML及辅助SRT。PCM SHA与原扩展PCM一致。识别阶段保持HF/Transformers离线。
- 每次新UUID目录；冻结输入并再次校验，状态decode/recognize/generate-titles/ready，异常保存failed。仅ready提供输出哈希；失败不能冒充上次成功。原生解码CLI不代表扩展沙箱内的一键调用。
- 构建10新增“载入识别结果”，通过NSOpenPanel选择完成的任务文件夹，使用user-selected.read-only权限读取，检查完成状态、项目UID、三份文件SHA与clip-only XML，然后将数据留在内存供原生拖放使用。取消不替换已有结果，选错/损坏会清空结果并禁止回退固定fixture。关闭/重启扩展后载入状态不持久。
- FCP真实读取本次任务成功（ready-to-drag，3版本，09:14:28Z）。前两次选择未成功选中文件夹而invalid-result；键盘选中后成功。不是媒体读取权限机制的泛化证据。
- 三份实际输出与此前真实拖放验收的固定fixture逐字节一致，因此未重复写入时间线。当前原项目仍为音视频＋五条Caption＋三条Title。

## 运行及载入

1. `python3 scripts/build_probe.py`构建探针与本机音频CLI。
2. 用上面的单命令运行隔离快照，完成后终端输出任务目录。
3. 在SubPop Probe点击“载入识别结果”，选该任务文件夹；状态ready-to-drag后可拖出。拖到原项目起点，再“将片段项分开”。

这些步骤仅用于验证；正式产品仍需将新鲜项目输入、后台任务启动、进度和结果回传接到面板，减少文件夹选择。不得把“当前UID和长度相同”视为快照内容仍新鲜，也不能重复拖入时自动替换已有字幕。

## 后续

用户已选Title优先。下一步实现面板与独立后台任务的连接、输入快照新鲜度和重复写回处理，然后拓展整项目最终可听音频。MPS、复杂项目、其他帧率、崩溃恢复、取消识别、批量样式均未验收。此轮不对FCP原项目新增字幕。


构建11已完成面板提交与进度/结果回传，见[面板服务验证](panel-worker.md)。显式旧快照及其他能力边界保持不变。
