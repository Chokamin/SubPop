# SubPop

用于 Final Cut Pro 的本机中文字幕插件。视频类型不限，单次项目不设固定时长上限，支持普通剪切和背景音乐角色。单面板完成项目拖入、模型选择、整段识别、字幕校对和 Title 拖回原时间线。

目前为本机 MVP 候选版，**宿主完整验收尚未全部完成**。已通过的功能和剩余项目见 [MVP 计划与验收](docs/MVP_PLAN.md)，历史证据见 [HANDOFF.md](HANDOFF.md)。

## 当前功能

- Qwen3-ASR 0.6B／1.7B 实际本机切换，记住选择；文件缺失时明确提示，不自动回退。
- 词库：本机保存、开关、去重，每次识别冻结提示词；最多100词/2000字，以实际音频为准。
- 模型管理：面板内下载、切换和移除；首次自动补齐共用对齐模型，真实进度/速度、暂停续传和SHA-256校验。
- 默认识别对白角色，可选择全部音频；单声道、立体声、剪切、空隙和连接音频，按时间线位置渲染。
- 不设固定项目时长上限，常见整数／分数帧率；ASR 分段、时间回映射、进度与取消。
- 字幕表格校对、字体／字号、草稿及任务恢复；三版本 Title 拖出，保留已有字幕冲突保护。
- 后台自动准备，记住首次目录授权。识别不上传音频，不调用 FCP“共享／导出”。

项目修改后必须重新拖入。暂不支持变速、复合片段、多机位、J/L 音频、音频效果、对白音量关键帧或多通道映射；这些结构会报错。背景音乐若已经混在对白源文件中，角色过滤无法将其分离。

## 本机安装与更新

当前机器已安装 `/Applications/SubPop Probe.app`，独立运行环境、模型和缓存位于此仓库。不能移动或删除仓库后继续运行；跨机器独立安装包尚未制作。

维护更新：关闭 SubPop 面板后执行 `python3 scripts/install_local.py`，再从 FCP“窗口 → 扩展 → SubPop Probe”重开。更新保留模型和授权；若旧进程仍被 FCP 缓存，需要重新启动该扩展。普通使用无需终端或手动启动后台。

模型缺失时点击面板里的“模型管理”下载，无需终端。共用时间对齐模型约1.84 GB；移除识别模型会保留它。

维护人员也可以通过独立环境补齐：

```sh
.venv/bin/python scripts/install_models.py qwen3-asr-0.6b
.venv/bin/python scripts/install_models.py qwen3-asr-1.7b
```

仅下载官方固定版本文件。识别运行强制离线。公共模型清单在 `config/models.json`；私有任务、媒体、模型和授权不提交 Git。

## 开发验证

先 `python3 scripts/build_probe.py`，再 `python3 -B -m unittest discover -s tests -v`。原生音频测试需要系统媒体服务权限。

构建使用本项目解包的苹果 Workflow Extension SDK。`SubPopPresentationTests` 是无 FCP 宿主、无窗口的 AppKit 校对回归程序，不能替代 FCP 落轨验收。所有 FCP 工程验证只使用 `.subloom/verification/` 独立资源库，不修改用户其他工程。
