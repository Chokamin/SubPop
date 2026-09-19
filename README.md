<div align="center">

<img src="assets/subpop-icon.png" width="144" height="144" alt="SubPop 图标">

# SubPop

**让字幕跟上你的表达。**

为 Final Cut Pro 制作的本机中文字幕插件。<br>
拖入项目，识别语音，校对与调整样式，再把字幕放回时间线。

**[下载 SubPop 1.0.0](https://github.com/Chokamin/SubPop/releases/download/v1.0.0/SubPop-1.0.0-arm64.pkg)** · [所有版本](https://github.com/Chokamin/SubPop/releases) · [反馈问题](https://github.com/Chokamin/SubPop/issues)

Apple Silicon · macOS 15+ · PKG 约 210 MB<br>
Developer ID 签名 · Apple 公证

</div>

---

## 用 SubPop 做什么

- **从项目开始**：直接接收 FCP 浏览器中的完整项目，省去手动导出音频。
- **在本机识别**：四种模型可选，下载后离线运行，识别时不上传音频或视频。
- **整理中文表达**：自动断句、去除句子标点，保留数值、单位与技术标识；词库帮助统一专名写法。
- **整批调整样式**：搭配 Tap5a 自适应底框，统一设置文字、底框、位置与效果，边调边预览。
- **回到 FCP 编辑**：生成可逐句修改的 Title 字幕片段，继续完成剪辑。

## 豆包云端识别（开发版 1.1.0，尚未发布）

本机模型之外，开发版增加了可选的豆包云端识别。上方 **1.0.0 安装包尚不包含此功能**。

1. 在[火山引擎豆包语音控制台](https://console.volcengine.com/speech/new/setting/apikeys)开通「录音文件识别 2.0」，创建语音服务 API Key。此处不是方舟聊天模型密钥，也不需要开通极速版。
2. SubPop「模型」→「豆包录音文件识别 2.0」→「配置云端识别」，填写 API Key 并保存。密钥保存在 macOS 钥匙串；保存不会上传音频或验证服务额度。
3. 选择豆包模型，拖入项目，在确认音频上传和计费后开始识别。

只需语音 API Key，不需要 APP ID、Access Token 或 TOS 存储桶。SubPop 将音频分成不超过 1 分钟的小段，直接提交给标准版 2.0，再查询识别结果。视频画面、FCP 项目文件和词库不上传；音频不会传到 SubPop 开发者的服务器，识别费用由你的火山引擎账户结算。

识别提交不自动重试；取消、超时或断网后，已经提交的部分仍可能计费。返回结果沿用 SubPop 的本机词库规范化、断句和字幕样式流程。此前已保存的 API Key 会继续使用，无需重填。

已用真实服务验证标准版 2.0 的 API Key 直接提交音频、查询文字和逐字时间戳。短音频测试不代表所有素材的识别质量或长项目稳定性。[官方接口说明](https://www.volcengine.com/docs/6561/1354868?lang=zh)

## 安装前先看这里

| 项目 | 说明 |
| --- | --- |
| Mac | Apple Silicon（M 系列芯片） |
| 系统 | macOS 15 或更高版本 |
| Final Cut Pro | 当前实测版本为 12.3 |
| SubPop 安装包 | 包含插件与独立运行环境，无需另装 Python |
| 识别模型 | 首次使用时在 SubPop 内下载，不包含在 PKG 中 |
| 基础字幕 | 使用 FCP 自带标题，无需安装 Tap5a |
| 自适应底框字幕 | 首次使用时可在 SubPop 内下载安装 **Tap5a Autosize Text Background** |

**Tap5a 不包含在 PKG 中，但可在 SubPop 内下载并安装。** 首次选择自适应底框样式时，点击「下载并安装 Tap5a」，授权一次「影片」文件夹，SubPop 会从作者源下载并放到正确目录。基础字幕无需 Tap5a。

## 第一次使用

1. **安装 SubPop**：下载上方 `.pkg` 文件，按安装向导完成安装。Releases 中的 `Source code` 是源码，不是安装程序。
2. **打开扩展**：先打开「应用程序」中的 SubPop，再从 FCP「窗口 → 扩展 → SubPop」打开面板。首次使用时，允许访问默认任务文件夹。
3. **下载模型**：点击面板顶部「模型」，下载需要的识别模型。模型大小见下表。
4. **开始识别**：在 FCP 中打开要处理的项目，再把浏览器里的该项目拖入 SubPop。确认项目名称、时长、模型与音频范围，点击「开始识别」。
5. **校对结果**：展开字幕预览，检查文字和断句，再选择基础字幕或 Tap5a 样式送回 FCP。

修改过时间线后，请重新拖入项目，让 SubPop 使用最新内容。当前处理整个项目，不是浏览器里的单个素材或时间线选区。

## 将字幕放回时间线

### 基础字幕：直接拖回

把 SubPop 的「拖回字幕到 Final Cut Pro」卡片拖到**原项目时间线起点、视频上方**。字幕以项目起点对齐，不以当前播放头位置对齐。

需要逐句编辑时，选中整段字幕包装片段，执行 FCP「片段 → 将片段项分开」，即可分别调整每条字幕。

### Tap5a 自适应底框：先导入，再拖回

在「字幕样式」中选择「Tap5a · 自适应底框」。首次使用时，可点击「下载并安装 Tap5a」，也可点击「选择已安装的模板…」选择已有的 `Tap5a Autosize Text Background.moti`。完成后会记住位置。

1. 在 SubPop 中点击「导入字幕到 Final Cut Pro」。如 FCP 询问资源库，选择原项目所在资源库。
2. 等待 FCP 导入完成，浏览器会显示本次新建的编号事件（例如「SubPop 字幕 001」），其中只有对应的「项目名 · Tap5a 字幕 001」字幕片段。每次导入使用新序号并保留旧版，插件也会提示本次的完整名称。将新片段拖到**原项目时间线起点、视频上方**。

选中导入的字幕片段后，同样可以执行「将片段项分开」来逐句编辑。每次导入会增加编号，减少同名冲突。点击导入只表示已发送请求，请在 FCP 浏览器中确认结果。

切换字幕样式或重新导入无需再次识别。调整样式后会生成一份新字幕，**不会同步修改 FCP 时间线上已有的字幕**；请按需移除旧版，避免重叠。SubPop 也不会读取后来在 FCP 中修改的文字。

## 安装 Tap5a（可选）

当前适配的是 **Tap5a Autosize Text Background**，不是 Multiline Text Background 或其他 Tap5a 模板。模板由 [Tapio Haaja（tap5a）](https://github.com/tap5a/free-final-cut-pro-x-plugins#tap5a-autosize-text-background) 提供。SubPop 从作者源下载安装，保留作者说明，不随安装包重新分发模板。

### 在 SubPop 中安装

1. 识别完成后，选择「Tap5a · 自适应底框」，点击「下载并安装 Tap5a」。
2. 在系统授权窗口中选择当前用户的「影片」文件夹，点击「授权并安装」。
3. 等待下载与安装完成，SubPop 会自动选择模板；如果 FCP 尚未显示新模板，重新打开 FCP。

下载约 **37 KB**，需要连接作者的 GitHub 源；网络不可达时可重试或手动安装。安装前会校验固定版本文件，保留已有模板；同名文件夹不兼容时会提示处理，不会覆盖你的修改。

### 手动安装

已安装的用户可直接选择模板；无法联网或使用其他安装位置时，也可按以下方式安装：

1. 打开作者的 [Tap5a_Autosize_Text_Background.zip 下载页](https://github.com/tap5a/free-final-cut-pro-x-plugins/blob/main/Tap5a_Autosize_Text_Background.zip)，点击「Download raw file」下载并解压。
2. 在 Finder 按 **⌘⇧G**，前往下面的目录。缺少文件夹时创建对应文件夹；已有 Motion Templates / Titles 目录时使用原目录，不要再建一套。

   ```text
   ~/Movies/Motion Templates.localized/Titles.localized/Tap5a/
   ```

3. 将解压后**包含 `.moti` 文件的整个 `Tap5a Autosize Text Background` 文件夹**放进去，保留其中的 `Media`、预览图和模板文件。最终结构应为：

   ```text
   Tap5a/
   └── Tap5a Autosize Text Background/
       ├── Tap5a Autosize Text Background.moti
       ├── Media/
       ├── large.png
       └── small.png
   ```

4. 如果 FCP 已打开，重新打开 FCP。确认标题浏览器的 Tap5a 分类里能看到模板，再回到 SubPop 选择它。

Finder 可能将这些目录显示为「影片」「Motion Templates」或「Titles」，不显示 `.localized` 后缀。SubPop 当前需要模板位于 `Titles.localized` 目录内，不能直接选择「下载」文件夹中的副本。作者的通用安装说明见 [Tap5a 安装指南](https://github.com/tap5a/free-final-cut-pro-x-plugins#installation)。

## 调整样式与预览

选择 Tap5a 后，点击「整批样式」，将当前字幕统一为同一套视觉样式。

| 分类 | 可调整内容 |
| --- | --- |
| 文字 | 字体、字形／粗细、字号、颜色、字距、额外行间距 |
| 位置 | X／Y 偏移，文字与底框一起移动 |
| 文字效果 | 外框、光晕、投影及各自的相关参数 |
| 底框与留白 | 颜色、不透明度、圆角、四侧留白、边框 |
| 预设 | 应用到全部字幕，或保存预设供以后载入 |

X 正值向右，Y 正值向上；偏移以项目像素为单位，支持正负值。字号支持 1–1000 和小数。双击参数前的文字标签，可将该项数值恢复默认值。数值支持左右拖动调整，部分 FCP 宿主环境的拖动与 Shift 精调仍需验证。额外行间距仅影响多行字幕。

预览显示当前字幕对应的**源视频静帧**，支持上一句／下一句、90% 动作安全框、80% 标题安全框和全屏预览。参数变化会更新预览；自动取帧失败时，可自行选择视频截图作为背景。安全框不会出现在导出的字幕中。

预览不是视频播放，也不包含 FCP 调色、特效或完整 Motion 渲染；最终效果以 FCP 为准。

## 模型与国内下载源

| 模型 | 本机运行方式 | 模型大小（约） |
| --- | --- | --- |
| Qwen3-ASR 0.6B | CPU | 1.88 GB |
| Qwen3-ASR 1.7B | CPU | 4.70 GB |
| Whisper Large v3 Turbo | MLX | 1.61 GB |
| SenseVoiceSmall | CPU | 0.94 GB |

两个 Qwen 模型还需要约 **1.84 GB** 的共用时间对齐模型，首次下载会自动补齐，之后无需重复下载。处理速度取决于模型、项目长度和设备性能。

模型管理支持下载进度、续传和 SHA-256 文件校验。默认优先尝试第三方 **HF-Mirror 国内镜像**，失败后尝试 Hugging Face 官方源；也可选择仅使用官方源。网络环境不同，速度和可访问性可能不同。

## 让词库统一专名写法

在「词库」中添加希望输出的完整写法，并启用词库。例如：

| 词库中的写法 | 可规范的识别结果 | 输出 |
| --- | --- | --- |
| `iPhone 18 Pro` | `iPhone十八pro` | `iPhone 18 Pro` |

词库参与断句保护，并统一匹配词条的大小写、空格和等值数字写法。它不会把不同型号强行替换，也不能保证纠正所有同音词或错听。不同模型对识别提示词的支持不同；SenseVoice 的词库在字幕整理阶段生效。

新增或修改词库后，在下一次识别时生效，不会自动改写已经导入 FCP 的字幕。

## 常见问题

**没有 Tap5a 能用吗？**

可以。基础字幕无需第三方模板；选择自适应底框时，可在 SubPop 内下载并安装 Tap5a。

**为什么 Tap5a 不能像基础字幕一样直接拖回？**

当前版本的大批量模板字幕采用「导入到 FCP 浏览器 → 拖回时间线」两步流程。请按上面的 Tap5a 操作步骤使用。

**更新后，旧字幕会跟着变吗？**

不会。新版本的识别、断句和样式修改作用于新生成的结果，FCP 中已有的字幕需要自行替换或编辑。

**为什么还要校对？**

识别与断句不能保证完全准确，尤其是专名、方言、噪声和多人同时说话的片段。导入前请检查关键内容。

**FCP 扩展菜单里没有 SubPop？**

先打开「应用程序」中的 SubPop，再重新打开 FCP。

## 当前支持范围

- 支持整项目识别与普通剪切；暂不支持变速、复合片段、多机位、J/L 音频，以及部分音频效果、音量关键帧和多通道映射。
- 「仅对白」按 FCP 音频角色过滤音乐，不能分离已经混进同一源文件的背景音乐。
- 输出为 **Title 标题片段**，不是 FCP 原生的 Captions 字幕轨。
- 当前实测环境为 FCP 12.3，尚未在另一台干净 Mac 上完成安装到落轨的全流程验收。

## 数据、更新与反馈

使用本机模型时，识别在本机完成；检查更新和下载模型时需要联网。开发版选择豆包云端模型并确认后，音频会上传至火山引擎。正式安装版的模型和任务文件保存在：

```text
~/Library/Application Support/SubPop
```

面板中的「检查更新」会查询 GitHub 正式 Release，并提供下载页，由你下载安装。各版本的改动和校验文件见 [Releases](https://github.com/Chokamin/SubPop/releases)。

遇到问题可提交 [GitHub Issue](https://github.com/Chokamin/SubPop/issues)，附上 macOS、FCP、SubPop 版本，使用的模型、复现步骤和错误提示即可，无需上传私人视频。

仓库公开 SubPop 源码与模型清单；模型权重和 Tap5a 模板不随源码或安装包分发。模型、模板与第三方依赖遵循各自的使用条款。
