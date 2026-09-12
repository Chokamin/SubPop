# SubPop

用于 Final Cut Pro 的本机中文字幕插件。视频类型不限，单次项目不设固定时长上限，支持普通剪切和背景音乐角色。单面板完成项目拖入、模型选择、整段识别、字幕校对和 Title 拖回原时间线。

目前为本机 MVP 候选版，**宿主完整验收尚未全部完成**。已通过的功能和剩余项目见 [MVP 计划与验收](docs/MVP_PLAN.md)，历史证据见 [HANDOFF.md](HANDOFF.md)。

## 当前功能

- Qwen3-ASR 0.6B／1.7B、Whisper Large v3 Turbo（MLX）、SenseVoiceSmall 实际本机切换，记住选择；文件缺失时明确提示，不自动回退。
- 词库：本机保存、开关、去重，每次识别冻结提示词；最多100词/2000字，以实际音频为准。
- 模型管理：面板内下载、切换和移除；首次自动补齐共用对齐模型，真实进度/速度、暂停续传和SHA-256校验。
- 默认识别对白角色，可选择全部音频；单声道、立体声、剪切、空隙和连接音频，按时间线位置渲染。
- 不设固定项目时长上限，常见整数／分数帧率；ASR 分段、时间回映射、进度与取消。
- 自动字幕整理：先按标点、实测停顿和中文词边界断句，再去句子标点；保护数值/单位/技术标识和词库专名，接平 <=0.2 秒短间隙。规则迁移及限制见 [说明](docs/subtitle-rules-port.md)。
- 字幕表格校对、字体／字号、草稿及任务恢复；三版本 Title 拖出，保留已有字幕冲突保护。
- 后台自动准备，记住首次目录授权。识别不上传音频，不调用 FCP“共享／导出”。

项目修改后必须重新拖入。暂不支持变速、复合片段、多机位、J/L 音频、音频效果、对白音量关键帧或多通道映射；这些结构会报错。背景音乐若已经混在对白源文件中，角色过滤无法将其分离。

## 下载与发行状态

公开仓库：[Chokamin/SubPop](https://github.com/Chokamin/SubPop)。安装包见 [Releases](https://github.com/Chokamin/SubPop/releases)。首个 PKG 为 `v0.1.0.29` 公开测试版，约 461 MB，适用 Apple Silicon 与 macOS 15+，FCP 实测版本为 12.3。尚未完成 Developer ID 签名及 Apple 公证，macOS 可能阻止安装；请勿把源码压缩包当作安装程序。

PKG 安装到 `/Applications/SubPop.app`，包含独立 Python 与识别依赖；首次打开 SubPop 后，从 FCP 扩展菜单进入，授权默认任务文件夹并下载模型。模型和个人数据保存在 `~/Library/Application Support/SubPop`，不依赖开发仓库。已装旧开发版的测试者应先退出并移走旧 `SubPop Probe.app`，避免同一扩展出现两份；旧开发目录中的模型和任务不会自动迁移。

面板顶部“检查更新”手动查询 GitHub 正式 Releases；有新版本且包含 PKG/DMG 时提供下载页。不会自动安装，也不上传音频或项目信息。发行标签采用 `v0.1.0.29`（最后一段是构建号）；测试版不向普通用户提示更新。

模型目前从 Hugging Face 固定版本下载，支持续传与 SHA-256 校验。默认优先使用第三方 HF-Mirror 国内镜像，失败后尝试 Hugging Face 官方源；可在模型管理改为仅官方源。所有来源共享相同固定版本与校验值。GitHub、镜像和官方源在不同网络下的可访问性不保证。下载后识别离线运行。

## 本机开发安装与更新

当前机器已安装 `/Applications/SubPop Probe.app`，独立运行环境、模型和缓存位于此仓库。不能移动或删除仓库后继续运行；此段仅针对旧开发安装，Release PKG 使用应用内运行环境。

维护更新：关闭 SubPop 面板后执行 `python3 scripts/install_local.py`，再从 FCP“窗口 → 扩展 → SubPop Probe”重开。更新保留模型和授权；若旧进程仍被 FCP 缓存，需要重新启动该扩展。普通使用无需终端或手动启动后台。

模型缺失时点击面板顶部的“模型”下载，无需终端。共用时间对齐模型约1.84 GB；移除识别模型会保留它。

维护人员也可以通过独立环境补齐：

```sh
.venv/bin/python scripts/install_models.py qwen3-asr-0.6b
.venv/bin/python scripts/install_models.py qwen3-asr-1.7b
```

仅下载官方固定版本文件。识别运行强制离线。公共模型清单在 `config/models.json`；私有任务、媒体、模型和授权不提交 Git。

## 开发验证

先 `python3 scripts/build_probe.py`，再 `python3 -B -m unittest discover -s tests -v`。原生音频测试需要系统媒体服务权限。中文分词集成须另外用 `.venv/bin/python -B -m unittest discover -s tests -v` 完整运行；依赖固定在 `requirements-asr.lock.txt`。

构建使用本项目解包的苹果 Workflow Extension SDK。`SubPopPresentationTests` 是无 FCP 宿主、无窗口的 AppKit 校对回归程序，不能替代 FCP 落轨验收。所有 FCP 工程验证只使用 `.subloom/verification/` 独立资源库，不修改用户其他工程。
