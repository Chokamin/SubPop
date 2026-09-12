# SubPop 协作规则

适用于 Codex 与 Claude Code。代码库是事实源，四份项目记忆是协作源。

每次开始依次读取 HANDOFF.md → PROJECT_MEMORY.md → DECISIONS.md → CLAUDE.md，然后检查代码与 Git 状态。

- SubPop 独立仓库、数据、安装与运行环境。VinciSub 仅只读参考，不改安装或用户数据；不复制 Resolve 宿主适配、落轨和 UI。
- 接入验证优先于完整 UI。所有未实测能力明确标记；文档证明、静态检查、模拟测试、离线 ASR、FCP UI 实测和扩展端到端实测分别记录。
- FCP 写入只用 `.subloom/verification/` 独立资源库和项目，操作前核对目标；不直接修改资源库数据库。不默认生成字幕版时间线，不擅自采用导出导入或菜单自动化产品方案。
- 每次改动更新相关测试；交付前先运行 `python3 scripts/build_probe.py`（需要本地解包的苹果 SDK），再运行 `python3 -B -m unittest discover -s tests -v` 和相关真实探针。不能用单元测试取代 FCP 验收。
- 追加 PROJECT_MEMORY.md：日期、需求、改动、关键文件、验证、剩余问题；每次更新 HANDOFF.md。长期决策变化才更新 DECISIONS.md；协作变化才更新本文件。
- 每次完成修改创建 Git commit，先检查差异与敏感数据，交付报告测试和提交编号，提交后检查状态。
- 未经要求不发布 GitHub、不购买服务。不以研究字幕统计或短片抽查宣称模型训练或识别准确率提高。

- 当前真实根目录为 `/Users/chokamin/Desktop/SubPop`。从新目录开始后续会话；旧 Subloom 符号链接仅兼容历史引用，不能作为新的沙箱工作区根。
