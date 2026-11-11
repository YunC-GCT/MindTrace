# ReviewAgent 用独立复习表；MathVideoAgent 只产脚本

## Status

accepted（2026-10-30，#242 拍板）

## Context

`#242` 要求在开两个子 Agent 的实现票之前定两件事：Video 做到哪一步、复习用哪套领域模型。现状：

- `study_plan` 是**待办表**（`id` / `title` / `is_done` / `priority` / `linked_note_id` / `created_at` / `due_date`），没有 `subject`、没有评分、没有掌握度；
- `review_item` / `review_log` **不存在**，`DatabaseHelper` schema 版本 **14**；
- 项目已定**测试态不上架**（见 `docs/agents/phase-tracker.md`），线上没有真实用户数据；
- v1 已冻结，本轮只定方向、开实现票，不立刻写代码。

## Decision

### 1. MathVideoAgent：只产脚本，不做 mp4

`outline → script` 为止，**不引入 mp4 renderer**。产物是文本（脚本/Markdown），落 `App Store` 的文本产物；不占大文件配额，也不引入外部渲染服务。

取消/隐私因此简化：脚本生成中途取消 = 丢弃草稿，没有半成品视频文件需要清理。

### 2. ReviewAgent：新建 `review_item` / `review_log`，`study_plan` 保持待办

不改 `study_plan` 的语义，也不把复习字段塞进去。因此：

- `StudyPlanReadPort` / 未来的 `StudyPlanWritePort` 继续只承载**待办**语义；
- 复习侧新增 `ReviewReadPort` / `ReviewWritePort`（契约另开，形状参考 `#238` 六必填项）；
- `SM-2` 算法放在 `review.plan` 工具里，不写进 UI。

### 3. 数据迁移按「本地开发数据」处理

测试态不承诺线上数据迁移：schema 15 迁移按 **`CREATE TABLE IF NOT EXISTS`** 落地，回滚 = `DROP TABLE`；开发数据可清空重建。**不设计线上数据回填**（那是上架时另开的 ADR）。

### 4. Schema 草案（v14 → v15，实现票再细化）

```sql
CREATE TABLE IF NOT EXISTS review_item (
  id TEXT PRIMARY KEY,
  unit_id TEXT NOT NULL,
  subject TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'new',        -- new / learning / review / graduated / lapsed
  next_review_at INTEGER NOT NULL DEFAULT 0,
  interval_days INTEGER NOT NULL DEFAULT 0,
  ease_factor REAL NOT NULL DEFAULT 2.5,
  repetitions INTEGER NOT NULL DEFAULT 0,
  lapses INTEGER NOT NULL DEFAULT 0,
  last_reviewed_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_review_item_due ON review_item (next_review_at);
CREATE INDEX IF NOT EXISTS idx_review_item_unit ON review_item (unit_id);

CREATE TABLE IF NOT EXISTS review_log (
  id TEXT PRIMARY KEY,
  review_item_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  reviewed_at INTEGER NOT NULL,
  grade TEXT NOT NULL,                        -- again / hard / good / easy
  correct INTEGER NOT NULL,                   -- 0 / 1
  duration_ms INTEGER NOT NULL DEFAULT 0,
  interval_before INTEGER NOT NULL DEFAULT 0,
  interval_after INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_review_log_item ON review_log (review_item_id);
```

`study_plan` 不动；`review_item.unit_id` 与 `knowledge_unit.id` 对应，删除笔记时由业务层级联清理（实现票里定事务）。

## Consequences

- 派生票：① schema v15 迁移（加两表 + 回滚）② `ReviewReadPort` / `ReviewWritePort` 契约与契约测试 ③ `ReviewAgent` 子图（`plan → ask → grade`）④ `MathVideoAgent` 脚本流水线。
- 好处：待办与复习解耦，`#238` 的 `StudyPlanWritePort` 不受复习模型牵连；Video 不背渲染与存储风险。
- 代价：复习需要新表与新端口，比"改 `study_plan`"多两张表和一层契约；换来的是语义清晰。

## Considered Options

- **升级 `study_plan` 为间隔复习**：被否。待办（人工勾选、无评分）与间隔复习（算法调度、有评分历史）是两种语义，混表后 UI 和查询都要按模式分叉。
- **上 mp4 renderer**：被否。需要外部渲染依赖 + 存储配额 + 产物隐私/删除策略，v1 冻结期收益不足。
