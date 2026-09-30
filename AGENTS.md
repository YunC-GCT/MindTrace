# MindTrace 协作说明

MindTrace 是面向数学学习的 HarmonyOS 原生智能笔记与可追溯复习应用。仓库采用 1 个 HAP 与 4 个 HSP：

- `entry`：主应用、页面、业务服务与数据访问。
- `common`：公共模型、StateGraph、LLM 调用、工具与协议。
- `agents`：材料理解、分类、结构化和 Agent 工作流。
- `skill`：小艺意图入口。
- `cardservice`：元服务卡片。

## 参赛提交边界

`main` 分支作为参赛提交包使用，应保持简洁。README、基础使用说明、项目术语、代码规范和必要工具说明可以保留；调研、测试过程、缺陷修复记录、handoff、来源索引、旧审计和历史计划不进入主分支提交包。

## 开发约定

- 优先从 `README.md`、`CONTEXT.md` 和 `docs/index.md` 理解项目。
- 改代码前先确认当前工作区和分支，避免带入无关改动。
- 重命名文件使用 `git mv`，保持历史清晰。
- 提交使用 conventional commits，例如 `docs: ...`、`fix(entry): ...`、`feat(agents): ...`。
- 未经用户明确要求，不直接合并到 `main`。
- 多任务并行时使用独立 worktree，避免共享未提交修改。

## 常用检查

```bash
node scripts/link-check/index.mjs
node scripts/naming-lint/index.mjs
node --test scripts/link-check/tests/*.test.mjs
npm --prefix scripts/arkts-lint test
```

HarmonyOS 构建与运行使用 DevEco Studio，OCR 服务说明见 `tools/ocr_service/README.md`。

## 演示重点

- 图片或文本输入后生成结构化数学笔记。
- 草稿经用户确认后入库。
- 基于个人笔记进行复习问答。
- 回答可追溯到笔记来源和版本。
- 知识星系展示概念、前置关系与关联路径。
- 元服务卡片和小艺入口体现 HarmonyOS 生态接入。
