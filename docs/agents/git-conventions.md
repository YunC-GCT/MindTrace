# Git conventions

> **团队流程**(分支模型 / PR / review / 发版 / 分支保护)见团队手册 [`git-flow-lightweight-2026-09-04.md`](./git-flow-lightweight-2026-09-04.md);本文聚焦 commit 规范与单兵 git 操作。

## Branches

- **主分支**: `main`(只放稳定可发布版本,每次合并打 tag)
- **集成分支**: `develop`(新功能汇集,日常 base;AI 与人均可在其上工作)
- **临时分支**: `feature/*` / `release/*` / `hotfix/*` / `bugfix/*`,合入后删除
- **历史模型**(2026-09-04 前): 单 `main` + AI 工作分支 `YunCeH`。**已废止** — 新工作不再使用 `YunCeH`;原 `origin/YunCeH` 保留作历史快照
- **详细工作流**: 见本文件 §"分支工作流(Git Flow 轻量版)";命名细则见 `docs/style/naming-conventions.md` §"Git branch names"

## Commit 风格 — conventional commits

| 前缀 | 用途 | 示例 |
|---|---|---|
| `feat(p0):` / `feat(w4):` | 新功能 | `feat(w4): add SSE streaming reply to AgentChatService` |
| `fix(agents):` / `fix(build):` | 修复 | `fix(viewmodels): disable preview units to stop fixture leak` |
| `refactor(llm):` | 重构 (no behavior change) | `refactor(llm): collapse 3 call methods to call(opts)` |
| `docs(entry):` / `docs:` | 文档 | `docs(phase-3): add ticket #5 spec` |
| `test(llm):` | 测试 | `test(llm-config): RED test for ticket #9` |
| `chore(docs):` / `chore:` | 杂事 | `chore(docs): reorganize into architecture/api/...` |
| `style:` | 格式化 | `style: reformat dispatcher.ets` |

模块前缀 (`agents:` / `entry:` / `common:` / `build:`) 表示影响的 module。

## 每 commit 前必查

```bash
git branch --show-current    # 必须不是 main
git status                   # working tree 干净或仅预期修改
git log --oneline -3         # 最近 commit 风格一致
```

## 红线

- **不 push** — 未经 user 明确说 "push",绝不 `git push`
- **不进 main** — 所有改动通过 PR 合入 `develop`(功能)或 `main`(release/hotfix),user 手动 review + merge
- **不 reset --hard** — `git reset --hard HEAD~n` 需 user 明确授权 (reflog 可找回)

## 分支工作流(Git Flow 轻量版)

> 自 2026-09-04 起,团队 (3 人) 采用 Git Flow 轻量版。模型基于你的图,适配复赛节奏。

### 分支类型与寿命

| 分支 | 寿命 | 从哪拉 | 合回哪 | 何时用 |
|---|---|---|---|---|
| `main` | 长期 | 初始 | — | 生产代码,仅放稳定可发布版本,每次合并打 tag |
| `develop` | 长期 | `main` | `main`(发版时) | 开发集成,所有 feature 合入此 |
| `feature/<slug>` | 临时 | `develop` | `develop` | 开发新功能,**一个人一个分支**,完成即合并删除 |
| `release/<slug>` | 临时 | `develop` | `main` + `develop` | 准备发版,冻结功能只改 bug、写文档、改版本号 |
| `hotfix/<slug>` | 临时 | `main` | `main` + `develop` | 生产线上紧急 bug,需立即上线 |
| `bugfix/<slug>` | 临时 | `develop` | `develop` | 开发阶段非紧急 bug,不影响发版节奏 |

### 命名约定

| 类型 | 模板 | 例 |
|---|---|---|
| feature | `feature/<ticket-or-slug>` | `feature/dispatcher-single-entry`、`feature/w4-sse-streaming` |
| release | `release/<version-or-stage>` | `release/w5`、`release/v1.0` |
| hotfix | `hotfix/<issue-or-slug>` | `hotfix/16-fixture-leak`、`hotfix/fix-crash` |
| bugfix | `bugfix/<ticket-or-slug>` | `bugfix/17-extract-json-regex` |

**禁止模式**:空格、驼峰(分支用)、`YYYYMMDD` 后缀、缩写、`/main` `/develop` 子分支。

### 关键时机(命令速查)

| 阶段 | 命令 |
|---|---|
| ① 开始做功能 | `git checkout -b feature/<slug> develop` |
| ② 功能完成 | PR `feature/*` → `develop`(走 PR 模板 + CODEOWNERS review),合并后删除 feature 分支 |
| ③ 准备发版 | `git checkout -b release/<stage> develop`,只改 bug + 写文档 + 改版本号 |
| ④ 正式发布 | PR `release/*` → `main`(合并后打 tag),再合回 `develop` |
| ⑤ 线上出 bug | `git checkout -b hotfix/<slug> main` |
| ⑥ 修复完成 | PR `hotfix/*` → `main`(合并后打 tag),同时 PR `hotfix/*` → `develop` |

### PR 流程(3 人版)

```
各人本地:
  develop ←─ feature/<your-slug>     (你/AI/队友各自开工)

合并第一跳:
  PR: feature/* → develop            (reviewer = CODEOWNERS 里的另 1 人,squash merge)

合并第二跳(发版):
  PR: develop → release/<stage>      (修 bug + 文档)
  PR: release/<stage> → main         (你最后合并,打 tag)
  PR: release/<stage> → develop      (同步回 develop)

紧急修复:
  PR: hotfix/* → main                (立刻打 tag)
  PR: hotfix/* → develop             (同步)
```

### 与 PR 模板的对应

- PR 模板 §"Branch type"checkbox 对应这里 5 类分支,选错会被 reviewer 打回
- PR 模板 §"Reviewer checklist" 中 "Commits land on feature/*"(不是 main)的红线来源于此
- 合并策略:**feature/* / bugfix/* 用 squash commit**;**release/* / hotfix/* 用 merge commit**(保留分支历史给 tag 引用)

## 跨 worktree 约束

- 单 worktree 多 session: 同 `.git/`, **working tree 互斥** (一个 session 改时另一个别动)
- 多 worktree: 各自 working tree 独立, 但共享 HEAD, 需注意分支同步

## Windows / DevEco 已知问题 (sandbox 适配)

### MSYS `ssh.exe` 崩溃 → 用系统 OpenSSH

**症状**: 在本仓库 (Windows 中文路径 + Git for Windows) 里 `git push` / `git fetch` 报:

```
0 [main] ssh (XXXX) D:\Git\usr\bin\ssh.exe: *** fatal error - couldn't create signal pipe, Win32 error 5
fatal: Could not read from remote repository.
```

**原因**: MSYS 包装的 `ssh.exe` (`D:\Git\usr\bin\ssh.exe`) 在本 sandbox 偶发崩溃,直接连 GitHub SSH (port 443 / 22) 失败。

**修复** (一次性, 写到本地 `.git/config`, 不入 git):

```bash
git config --local core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"
```

> 系统自带 OpenSSH (`System32\OpenSSH\ssh.exe`) 不走 MSYS 包装, 不撞 env.exe crash。验证方式: `ssh -T git@github.com` 应返回 `Hi YunC-GCT! You've successfully authenticated, but GitHub does not provide shell access.`

**注意**: `.git/config` 不在 git 里 — 每个新 clone 都要重新设一次。如果想要全机器持久, 写到 `~/.gitconfig` 而不是 `--local`。

### MSYS `git commit` 崩溃 → 用 `commit-tree` 绕路

**症状**: `git commit -m "..."` 报同样 `couldn't create signal pipe`, 但 `git add` / `git write-tree` / `git status` 都正常。

**原因**: git 内部 commit 路径 (经 env wrapper) 触发同一 MSYS bug。`git push` 修好之后 commit 也大概率修好 (因为都走 ssh 后端); 如果 push 修好后 commit 还崩, 用下面的绕路。

**绕路** (3 步, 不用 `git commit`):

```bash
# 1. 写 commit message 文件 (用 .NET 避免 PowerShell Out-File 加 BOM)
$bytes = [System.Text.Encoding]::UTF8.GetBytes('docs: your title' + "`n`n" + 'body')
[System.IO.File]::WriteAllBytes('.git/MSG_TMP', $bytes)

# 2. 提交 (引用当前 HEAD 作 parent)
$tree = git write-tree
$parent = git rev-parse HEAD
$commit = git commit-tree $tree -p $parent -F .git/MSG_TMP
git update-ref HEAD $commit
Remove-Item .git/MSG_TMP
```

`commit-tree` 不走 env wrapper, 100% 可靠。Commit message / author / author-date 全部正常。

## 完整 session 起手检查清单

新 session 接到 MindTrace, 第一件事按顺序:

```bash
git fetch origin
git branch --show-current        # 必须 != main (红线 6);正常是 develop 或 feature/*
git status                       # 看遗留修改
git config --get core.sshCommand # 没值的话跑上面那个 git config --local 命令
node scripts/naming-lint/index.mjs   # 0 violations expected
node scripts/link-check/index.mjs    # 0 broken links expected
```

跑完上面 5 行,环境就绪。**开始做功能前**再 `git checkout -b feature/<slug> develop`(或同步现有 feature)。