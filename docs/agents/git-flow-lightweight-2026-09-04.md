# Git Flow Lightweight — 团队开发手册 (2026-09-04)

> **读者**: `@YunC-GCT` / `@rc-shi` / `@cmnon159`(3 人小团队)
> **来源**: `git-flow-setup-2026-09-04.md` 操作清单 + `branch-protection.md` 当前规则 + [`git-conventions.md`](./git-conventions.md) commit 规范 + PR 模板
> **版本**: v1.0(2026-09-04 release)

---

## 0. TL;DR(30 秒读完)

1. 你开发新功能 → 从 `develop` 拉 `feature/<slug>`
2. push + 开 PR → `develop` →等 1 个 teammate review → squash merge
3. 发版 → 从 `develop` 拉 `release/<stage>` → 改 bug + 文档 + 版本号 → PR → `main` → 打 tag → 同步回 `develop`
4. 紧急修 → 从 `main` 拉 `hotfix/<slug>` → PR → `main`(同时 PR → `develop`)
5. **所有 PR 必须有 1 个 CODEOWNERS approve**(3 人中任一);**owner 可以 self-approve 兜底**(评论里写 "LGTM, self-approve per 3-person policy")
6. **多 session 并行 → 各自独立 worktree(`git worktree add`)或严格串行**,禁止共用工作目录互相切分支(§11 红线)

---

## 1. 首次同步(每个新协作者必做)

```bash
git fetch origin
git checkout develop
git pull origin develop
# 检查本地分支清单
git branch -a
# 看到:
#   main, feature/* (你自己的), release/*, hotfix/*, YunCeH (历史, 忽略)
```

---

## 2. 日常工作流

### 2.1 开新功能

```bash
# 1. 同步 develop
git fetch origin
git checkout develop
git pull --ff-only origin develop

# 2. 拉 feature 分支
git checkout -b feature/<your-slug> develop
# 例: feature/w5-sse-token-streaming

# 3. 写代码 + 写测试 + commit
git add <files>
git commit -m "feat(agents): add SSE token streaming to KnowledgeModel"

# 4. push
git push -u origin feature/<your-slug>
```

### 2.2 开 PR → develop

浏览器: GitHub 自动显示 "Compare & pull request"

- **base**: `develop`
- **compare**: 你的 `feature/<your-slug>`
- **Title**: `feat(agents): add SSE token streaming to KnowledgeModel`
- **Description**: 按 PR 模板填(8 节)
- **Reviewer**: 加 `@YunC-GCT` / `@rc-shi` / `@cmnon159` 中**任一**(3-owner 路由)

**等 CI 跑完 + reviewer approve**:
- arkts-lint(可能 2-3 分钟)
- naming-lint
- link-check

→ Squash and merge → 合入 develop → 你的 feature 分支可以删(GitHub 自动提示)

### 2.3 PR checklist(PR 模板里有,简版)

- [ ] commit message 用 conventional commits + 模块前缀
- [ ] base 是 develop(不是 main)
- [ ] reviewers 至少有 1 人
- [ ] description 包含 `## Summary` / `## Changes` / `## Test plan`
- [ ] linked issue 填好(如有)
- [ ] 若 PR 实现了某个 spec/ADR,同步更新 `docs/specs/index.md` / `docs/adr/index.md` 的状态列

---

## 3. 发版流程(1-2 周一次)

### 3.1 创建 release 分支

```bash
git fetch origin
git checkout develop
git pull --ff-only origin develop
git checkout -b release/<stage> develop
# 例: release/w5、release/v1.1

git push -u origin release/<stage>
```

**release 分支上只能做**:
- 改 bug(commit 前缀 `fix:`)
- 写文档(commit 前缀 `docs:`)
- 改版本号(commit 前缀 `chore:`)

**不能**加新功能(那是 feature 分支的事)。

### 3.2 PR release → main

```
https://github.com/YunC-GCT/MindTrace/compare/main...release/<stage>?expand=1
```

- Title: `chore(release): vX.Y — <简短描述>`
- Description: 列本次 release 包含的所有 PR / 修复 / 升级
- Reviewer: 任一 CODEOWNER
- **Squash and merge**

### 3.3 打 tag

```bash
git checkout main
git pull origin main
git tag v<X.Y> main
git push origin v<X.Y>
```

例:`git tag v1.1 main && git push origin v1.1`

### 3.4 GitHub 发布 release 页面

https://github.com/YunC-GCT/MindTrace/releases → **Draft a new release**:

- Tag: `v1.1`
- Target: `main`
- Title: `v1.1 — <简短描述>`
- Description: 复制 `pr-body-release.md` 的 "What's included" 段 + 致谢贡献者
- **Publish release**

### 3.5 同步回 develop

```
https://github.com/YunC-GCT/MindTrace/compare/develop...main?expand=1
```

- Title: `chore: sync main → develop after vX.Y`
- (3 owner 自动路由,任一 approve)
- **Squash and merge**

### 3.6 通知团队

打开 `.scratch/team-announcement.md`(本地草稿)→ 复制 → 发到3 人消息群。

---

## 4. 紧急修复(线上 bug)

### 4.1 hotfix 分支

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b hotfix/<slug> main
# 例: hotfix/16-fixture-leak

# 修代码 + 测试 + commit
git commit -m "fix(viewmodels): disable preview units (fixture #6 #16)"

git push -u origin hotfix/<slug>
```

### 4.2 双 PR(hotfix 必须同时合 main + develop)

```
1. PR: hotfix/* → main     (修复进入生产,打 tag v1.0.1)
2. PR: hotfix/* → develop  (保证 develop 不漏修)
```

合并顺序:**先 main → 后 develop**(避免 develop 在 main 之前漏修)。

### 4.3 打 patch tag

```bash
git checkout main
git pull origin main
git tag v1.0.1 main
git push origin v1.0.1
```

GitHub Releases → 选中 v1.0.1 → 编辑 → 加 "Hotfix release" 标签。

---

## 5. 非紧急 bug 修复

```bash
git fetch origin
git checkout develop
git pull --ff-only origin develop
git checkout -b bugfix/<slug> develop
# 例: bugfix/17-extract-json-regex

# 修代码 + commit
git commit -m "fix(agents): use balanced-walker for extractJsonObject (#17)"

git push -u origin bugfix/<slug>
```

PR: bugfix → develop(reviewer 任一 CODEOWNER)→ Squash merge

**bugfix 与 hotfix 区别**:
- `hotfix/*`:紧急(线上已爆),从 main 拉,需要同步回 develop
- `bugfix/*`:非紧急,只合 develop,下次 release 自动包含

---

## 6. commit 规范

格式:`<type>(<module>): <description>`

| type | 用途 | 例 |
|---|---|---|
| `feat` | 新功能 | `feat(agents): add dispatcher single-entry seam` |
| `fix` | 修复 | `fix(viewmodels): disable preview units (#16)` |
| `refactor` | 重构(无行为变化) | `refactor(llm): collapse 3 call methods to call(opts)` |
| `docs` | 文档 | `docs(adr): add 0008-mcp-tools-rename-decision` |
| `test` | 测试 | `test(llm-config): RED test for ticket #9` |
| `chore` | 杂事 | `chore(ci): add CODEOWNERS for 3-person review` |
| `style` | 格式化 | `style: reformat dispatcher.ets` |
| `perf` | 性能 | `perf(render): cache KaTeX render output` |

模块前缀:`entry` / `common` / `agents` / `cardservice` / `skill` / `build` / `ci`

---

## 7. PR 模板必填字段

PR 创建时按 `.github/PULL_REQUEST_TEMPLATE.md` 填:

1. **Title**: 跟 commit message 一致(去掉模块前缀可以)
2. **Tied to**: `Closes #N` / `Refs #N` / `none — housekeeping`
3. **Type**: feat / fix / refactor / docs / test / chore / style
4. **Branch type**: feature / release / hotfix / bugfix
5. **Target branch**: develop / main
7. **Merge strategy**: squash(feature/bugfix) / merge commit(release/hotfix)
6. **Summary**: 1-3 句话
7. **Changes**: bullet list
8. **Test plan**: 怎么验证的
9. **Lint**: 4 个 checkbox(本地跑过)
10. **Risks & Rollback**: risk level + 回滚方案
11. **Related**: ADR / Spec / Closes / Follow-up

---

## 8. CODEOWNERS 路由说明

`.github/CODEOWNERS` 默认:

```
*  @YunC-GCT @rc-shi @cmnon159
```

**任何 PR 只要有 1 个 owner approve 即可 merge**。**owner 可以 self-approve 兜底**(无 teammate reviewer 时),前提评论写 "LGTM, self-approve per 3-person policy"。

高危路径单独列 owner(全部3 人):

- `/agents/` — AI 业务核心
- `/common/src/main/ets/llm/` — LLM 调用层
- `/common/src/main/ets/render/` — 渲染协议
- `/scripts/arkts-lint/` — 自研 lint 引擎
- `/entry/` — UI 入口

---

## 9. CI status checks

所有 PR 必须通过 3 个 status checks:

| Check | 检查内容 |
|---|---|
| `arkts-lint` | `node scripts/arkts-lint/index.mjs --` |
| `naming-lint` | `node scripts/naming-lint/index.mjs` |
| `link-check` | `node scripts/link-check/index.mjs` |

本地跑 3 个 check 通过后再 push,避免 CI 红:

```bash
node scripts/arkts-lint/index.mjs --quiet
node scripts/naming-lint/index.mjs
node scripts/link-check/index.mjs
```

---

## 10. 什么时候升级策略(2026-09-04 共识)

| 触发 | 升级 |
|---|---|
| 团队扩展到 5+ 人 | 勾 `Require approval of the most recent reviewable push`(强制非作者 review) |
| 出现 release 节奏 + 严格 gate | 勾 `Required linear history` |
| 有人故意放水 | 勾 `Required signed commits` |
| 敏感代码变更(AI / LLM / 渲染) | 在 CODEOWNERS 加额外 reviewer |

详细见 `docs/agents/branch-protection.md` §3.

---

## 11. 多 session 并行(独立 worktree 或串行)— 红线

> **背景(2026-09-06 事故)**:两个 AI session 共用同一 clone 并行开发,一方中途切换分支,把另一方**未完成、未过构建**的提交随自己的 PR 带进了 `develop`(develop 一度构建失败)。以下规则由此立为红线,不可逾越。

**规则:≥2 个 session 同时改同一仓库时,必须二选一**

1. **独立 worktree(推荐)** — 每个 session 一个工作区、一个分支,互不可见:

   ```bash
   # 新 session 接任务时(在主 clone 里执行一次)
   git fetch origin
   git worktree add ../MathMind-<slug> -b feature/<slug> origin/develop
   cd ../MathMind-<slug>
   # 该 session 之后只在这个目录里 commit/push; 收尾清理:
   git worktree remove ../MathMind-<slug>
   ```

2. **串行** — 只有一个 clone 时严格排队:一个 session 完成自己的 commit + push 并切回 `develop` 之前,另一个 session 不执行任何 git 写操作。

**绝对禁止**

- ❌ 在别的 session 可能正在工作的 clone 里 `git checkout` 切换分支
- ❌ 把别人工作区里未完成 / 未过构建的改动一起 commit 进自己的 PR
- ❌ 多个 session 对同一工作目录并发执行 commit / push

**同步方式不变**:各 worktree 的分支照常 PR → `develop`;`develop` 是唯一同步点。本地另一个人手工开发时同理(AI session 与人共用 clone 也要串行)。

---

## 12. 常见问题

**Q: 我开 PR 时"Review changes"按钮在哪?**
A: GitHub 2024+ UI 有时藏得深。
- 优先按 `r` 键(快捷键直接打开 review 弹窗)
- 或在 PR 描述文本下方找"Review changes"按钮
- 如果 owner self-approve,评论写 "LGTM, self-approve per 3-person policy"

**Q: merge 按钮是灰的?**
A: 检查 3 件事:
1. CI 全绿
2. 有 1 个 CODEOWNERS approve(看 PR 顶部 reviewers 区)
3. PR base 是预期的(develop / main)

**Q: 我开了 PR 但忘了 reviewers?**
A: 在 PR 详情页右侧栏 "Reviewers" 点击 → 加人。GitHub 会发通知。

**Q: 紧急情况需要绕过 CODEOWNERS?**
A: 编辑 ruleset 临时关 "Require review from Code Owners" → merge → 重新勾上。**audit trail 会记录在 PR 评论里**。

**Q: `feature/*` 合入后可以删吗?**
A: 合并后 GitHub 提示 "Delete branch",建议删(保持仓库干净)。本地 `git branch -d feature/<slug>`。

---

## 13. 进一步阅读

- `docs/agents/git-conventions.md` — 完整 commit + 分支规范
- `docs/agents/branch-protection.md` — 保护规则 + self-approve 策略
- `docs/agents/git-flow-setup-2026-09-04.md` — owner 操作清单(初始化用,后续不需要)
- `.github/PULL_REQUEST_TEMPLATE.md` — PR 必填字段
- `.github/CODEOWNERS` — 3-owner 路由表
- `CONTEXT.md` — 项目词汇表(术语消歧)
- `AGENTS.md` — 工作流入口

---

**版本**: v1.0
**适用**: MindTrace 3 人小团队,长期有效
**下次审查**: v1.1 发版时(如需调整策略)