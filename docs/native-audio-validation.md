# 整项目音频获取与识别验证 · 2026-09-12

后续：本轮原生 PCM 的 ASR 结果已完成原项目 SRT 导入及校对快照回读，见 [写回记录](writeback-validation.md)。下文保留音频验证阶段的范围。

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
