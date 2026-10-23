# MindTrace — Claude Code 入口

本仓库**唯一权威规则**是 [`AGENTS.md`](./AGENTS.md)。开工前按顺序读：

1. [`AGENTS.md`](./AGENTS.md) — 红线 10 条 + 编码契约 10 条 + 改什么读哪的指针表
2. [`docs/agents/phase-tracker.md`](./docs/agents/phase-tracker.md) — 当前阶段（P0–P6）、验收标准、DoD
3. [`CONTEXT.md`](./CONTEXT.md) — 项目词表（4 种 "agent" 的歧义）

## 最容易犯的三条

- **不 push**：只做 local commit，等 user 明确说 "push"
- **改完必跑 gate**：`node scripts/agent-gate/index.mjs`，交付回复里贴 `RESULT: PASS`
- **端A2A 配置三件事**：改 `agent_config.json` 后必须重新导入平台 → 重发真机测试 → 重启小艺

真机验证：`python scripts/a2a-smoke/a2a_smoke.py --text "整理数学题"`（需手机解锁且已连接）。
