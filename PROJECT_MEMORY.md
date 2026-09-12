# 项目记忆

## 2026-09-12：独立初始化与第一轮接入验证

- 需求：原生 FCP 工具 Subloom，先核实接入能力和原时间线字幕闭环，再做完整界面；保护 VinciSub 和现有资源库。
- 改动：建立独立 Git 仓库及四份协作文档、README、能力报告、隔离测试 XML/SRT 生成器、严格限定简单片段的 FCPXML 回读探针、离线 Qwen 识别探针与回归测试。
- 关键文件：`probes/make_fixture.py`、`probes/readback.py`、`probes/recognize_fixture.py`、`tests/test_probes.py`、`tests/fixtures/fcp-12.3-caption-readback.fcpxml`、`docs/integration-validation.md`、`docs/evidence/asr-cpu.json`。
- 本机：arm64、macOS 27.0、Xcode 26.6、两套 FCP 12.3；本轮仅标准版实测。官方 SDK 下载页为 1.0.3，未获得有效安装包，未安装/构建扩展。
- 验证结果：8 项单元/档案回归测试通过；夹具按 FCP 自带 1.14 DTD 校验通过。FCP 隔离原项目内两条 SRT 中文字幕相对定位准确，实际导出含中文简体角色；同 UID XML 修改导入弹出替换/保留两者，后者新增项目、原字幕不变。源路径来自实际 FCP 导出，ffmpeg 内存解码、Qwen 0.6B/对齐离线 CPU 实测通过。ASR 结果未写回，不称完整闭环。
- 安全与范围：全部 FCP 写入仅独立 Subloom-Verification-20260912 资源库；未写用户已有项目。VinciSub 只读借用解释器和模型，禁用字节码与联网，媒体独立复制，Git 工作区仍干净。未发布 GitHub、未购买。结束关闭测试资源库并确认 FCP 未载入任何项，保留独立测试数据供续测。
- 剩余问题：SDK 安装/原生扩展运行；当前选区、自动可听和多角色；Title、精确自动写回及校对同步；MPS 与复杂映射。未擅自采用文件导出导入作为产品方案。后续先补齐探针再交用户选择可行路径。

## 2026-09-12：SDK 校验与原生只读扩展构建

- 需求：用户已下载 SDK，继续最小原生接入验证。
- 改动：只读挂载官方 SDK 并在项目内解包，校验苹果签名；读取实际头文件和模板，新增 AppKit 容器应用、只读时间线观察器、XML 拖入记录器及可重现构建脚本。
- 关键文件：`native/Probe/Container.m`、`native/Probe/ProbeViewController.m`、`scripts/build_probe.py`、`tests/test_native_probe.py`、`docs/sdk-probe-validation.md`。
- 验证结果：编译及签名校验通过，11 项测试全部通过。SDK 1.0.3 头文件无选区、片段枚举、角色状态、字幕写入接口。修正工具链自动选择 CLT 27 SDK 导致的链接错误，显式采用 Xcode 26.5 SDK。沙箱内签名误报经系统信任服务复核为 Apple Software/accepted。
- 剩余问题：自动审批拒绝复制自签名 app 到 /Applications，要求本次安装确认；未安装/启动，不绕过，未做新 FCP 实测。等待确认后继续真实 host/拖放验证；独立 release notes PDF 未读。未改变 VinciSub 或用户 FCP 资源库。

## 2026-09-12：更名 SubPop 并完成原生面板部分宿主验证

- 需求：用户明确允许安装启动，并将产品改名为 SubPop。
- 改动：应用显示名、原生类、bundle identifier、日志目录和构建测试更名；保留仓库物理路径与历史证据名称。安装并打开只读面板，补充 FCP inspection/automation 权限用于 SDK 通信排查；范围/播放头独立记录，不被空 sequence 隐藏。
- 关键文件：`native/Probe/`、`scripts/build_probe.py`、`tests/test_native_probe.py`、`docs/sdk-probe-validation.md`、`docs/evidence/subpop-host-partial.json`。
- 实测：FCP 12.3 标准版中原生菜单注册、面板加载、host 身份、观察者回调和日志通过；隔离原项目范围 start=3600 秒、duration=8.68 秒，播放头有效。activeSequence 为 nil；SDK Apple Events -600 根因未明。新增权限未修复，不宣称权限或 SDK 能力已定论。未写入新字幕。
- 更正前两条历史记录：不能声称 SDK 已证实无选区。苹果概述提到 selected time range，属性语义需实测对照；此前排除结论撤回。自动审批的旧安装阻塞已由用户本轮明确授权解决。
- 验证：11 项测试通过，构建/签名通过；单元测试不是 FCP 完整闭环。剩余：项目 UID、选区对照、拖入 XML、可听角色、原时间线 ASR 写回与编辑同步。未修改 VinciSub、未发布。
