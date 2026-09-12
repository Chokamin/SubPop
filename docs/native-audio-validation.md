# 整项目音频获取与识别验证 · 2026-09-12

## 当前结论

**隔离单片段项目的“拖入项目 → 原生扩展解码完整音频 → 外部本地识别”通过。** 尚未实现插件内自动启动识别、字幕自动写回或通用时间线最终混音。整项目模式是用户明确选择的当前产品范围。

目标是标准版 FCP 12.3 的 Subloom-Verification-20260912 / Subloom-Original，UID `0D11EC79-ED11-4688-97A9-CB78621857DD`，25fps，起始 3600 秒，完整时长 217/25 秒。只操作独立测试项目；本轮未改字幕、片段内容或 VinciSub 数据。

## 实际步骤与证据

1. 用户将浏览器中的 Subloom-Original 拖到 SubPop Probe 面板顶部。CUA 只能可靠定位单个窗口，因此该跨窗口拖动由用户完成，不记录成自动化完成。
2. 构建 6 的接收器保存 4 份各 3827 字节的数据，类型分别为 `com.apple.finalcutpro.xml`、`.v1-14`、`.v1-13`、`.v1-12`。逐份读取根节点确认：通用类型与 v1-14 为 1.14，v1-13 为 1.13，v1-12 为 1.12。数据同时包含其他类型，但未消费私有 pasteboard 数据。
3. 拖入 XML 直接包含 project/sequence、普通 asset-clip、原有两条 caption、original-media URL 和 bookmark。UID、起始、完整时长与既有独立导出一致。路径已是新 SubPop 真实目录。脱敏档案移除 bookmark，不提交沙箱访问凭据。
4. 增加“验证最近项目音频”按钮，读取扩展自己保存的最近 XML，不需再次拖动。核对当前活动项目 UID，严格限定完整覆盖项目的单个 dialogue asset-clip、单个原始音频资源、无变速/效果/组件，时长不超过 30 秒。用 AVFoundation 在后台解码到扩展容器里的 float32 little-endian、16 kHz、单声道 PCM；不执行 AppleScript，不调用 FCP 私有类，不增加文件或网络授权。
5. 按钮选择最近保存的 XML，本次实际解码输入为 v1-12；外部识别的项目快照使用同次拖放的 v1-14，UID 和音频时间结构一致。构建 7 首次实际输出 555520 字节 / 138880 个采样，恰为 8.68 秒，RMS≈0.125336。构建 8 增加完整采样数检查，拒绝源音频比项目短的情况。构建 8 宿主复测也输出同样采样数，PCM 哈希完全一致；两个构建的宿主记录分别保存。
6. 将扩展产出的 PCM 复制到本项目忽略目录，通过独立测试进程调用 Qwen3-ASR 0.6B / ForcedAligner 离线 CPU 识别。PCM SHA-256 与原生产物相同，未重新经 ffmpeg 解码。此次仍只读借用 VinciSub 的 Python 环境和模型，禁用字节码、联网和遥测，缓存写到 SubPop。正式产品不可依赖这些路径。

识别文字：

> 大家好，欢迎使用中文字幕工具。今天我们测试语音识别，并把生成的字幕导入达芬奇。

该句是测试媒体原口播；没有把“达芬奇”改成 FCP。词级时间保留在证据中；“我”出现零长度区间，未实现产品级修复和断句。尚未生成或导入新的字幕。

## 权限与适用边界

原生扩展日志同时显示：直接 NSFileHandle 打开失败（513）、按 security-scope 选项解析 bookmark 失败（256）、securityScopeStarted=false，但 AVFoundation 实际解码成功。这证明当前运行环境能通过该媒体 API 获取此测试文件音频，**不证明直接文件读取、书签恢复、重新启动后的持久访问或所有文件均可用**，也不将成功归因于已确定的权限机制。

单元测试的终端沙箱里，AVAssetReader startReading 返回 AVFoundationErrorDomain -11800；同一测试在获准的普通本机执行环境通过。真实扩展宿主中也通过，三种环境的证据分别记录，不能互相替代。原生扩展没有升级文件访问 entitlements。

拖入数据是项目快照：UID 相同只证明项目身份，不能证明内容仍与最新编辑一致。当前按钮重读已保存 XML，不自动监听片段变更；编辑项目后须重新拖入，生产实现还需快照新鲜度校验。

音频源读取成功不等于最终可听混音正确。当前只验证一个普通片段，无角色关闭、Solo、组件禁用、音量/效果/淡变、变速、嵌套、复合、多片段。仍记录 audibility=unknown。生产整项目方案须获取最终混音或完整建模这些状态，不把源文件无条件当成用户所听内容。

## 文件与复现

- `native/Probe/AudioProbe.m`：原生受限解码探针；`AudioProbeCLI.m` 仅供普通进程回归，不能证明扩展沙箱权限。
- `probes/recognize_fixture.py --pcm …`：直接消费已复制的原生 PCM，校验完整采样长度与有限数值，输出 PCM 哈希。
- `docs/evidence/subpop-project-drop.json`：实际拖放类型与字节数。
- `tests/fixtures/fcp-12.3-native-drop.fcpxml`：实际拖入 XML 脱敏档案。
- `docs/evidence/subpop-native-audio.json`、`subpop-native-audio-build8.json`：原生解码证据。
- `docs/evidence/subpop-native-asr.json`：使用构建 7 原生 PCM 的识别与词级时间。

先运行 `python3 scripts/build_probe.py`，再运行 `python3 -B -m unittest discover -s tests -v`。音频解码测试需要系统 AVFoundation 解码服务；若受终端沙箱限制，申请普通执行权限，而非将失败跳过为通过。原生与 Python 修改未集成为自动调用链。

## 下一步

优先验证原时间线 Caption/Title 最短写回和编辑同步，再比较实际交互成本。项目拖入→识别已形成一条受限的读取候选，但写回半段未完成，尚不把手动导出/导入或 XML 全项目替换定为产品方案。随后扩大到多片段和最终可听音频，并建立 SubPop 独立模型环境。
