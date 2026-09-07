# Git Flow setup — 3 人协作(2026-09-04)

> **作者**: AI 自动化规范(本仓分支工作流落地清单)
> **执行人**: **你**(owner),AI 不会运行 `git push` 或修改 GitHub 仓库设置
> **耗时**: 约 15-30 分钟(其中 GitHub 网页操作占大头)

---

## 0. 前置确认

跑完下面 4 行再继续:

```bash
cd <本地仓库根>
git branch --show-current          # 应是 YunCeH(历史分支,即将退役)
git fetch origin                    # 拉最新
git ls-remote origin | head -10     # 远程可达
git config --get core.sshCommand    # 应有值;无则跑 git-conventions.md §"MSYS ssh 修复"
```

## 1. 推送 `develop` 分支

```bash
git checkout main                   # 切回 main(若不在)
git checkout -b develop             # 从当前 main 拉 develop
git push -u origin develop         # 推上去,GitHub 出现 develop
```

预期结果:`origin/develop` 出现,HEAD 与 `origin/main` 一致。

## 2. (可选但推荐)退役 `YunCeH` 远程分支

```bash
git push origin --delete YunCeH     # 删除 origin/YunCeH(本地 YunCeH 还在)
```

⚠️ **先确认队友工作都搬完**再删。本仓的 YunCeH 是 AI 工作分支,通常只有你自己 + AI 用,可以删。删之前 `git fetch` + `git log origin/YunCeH` 看一眼没有未合并 commit。

**本地分支保留**作为历史快照(不删):

```bash
git checkout YunCeH                 # 切回,留着
git log --oneline -5                # 验证还能用,只是不再 push
```

## 3. (可选)清理本地 `feat/auto-*` 旧分支

```bash
git branch -d feat/auto-20260721-704a68ae
git branch -d feat/auto-20260721-73792bbb
```

如果不放心,先 `git checkout feat/auto-*` 看一眼;只有合入过或已经 stale 才删。

## 4. GitHub 网页配置 branch protection

### 4.1 进入设置

```
GitHub → YunC-GCT/MindTrace → Settings → Branches → Branch protection rules
```

### 4.2 加 `main` 规则

按 `docs/agents/branch-protection.md` §"`main`" 表格逐项勾选。**最小必勾**:

- ☑ Require a pull request before merging
- ☑ Require approvals: `1`
- ☑ Require review from Code Owners
- ☑ Require status checks to pass
- ☑ Include administrators

### 4.3 加 `develop` 规则

按 `docs/agents/branch-protection.md` §"`develop`" 表格,同理勾选,**Required approvals = 1**。

### 4.4 加 CODEOWNERS 必须性

如果 GitHub 提示 "CODEOWNERS file not found in repository" → 检查 `.github/CODEOWNERS` 是否已 commit + push。

## 5. 通知 2 位队友

把下面的链接发给队友:

```
我们改用 Git Flow 轻量版了:
- 主分支: main (受保护,只能 PR 合入)
- 集成分支: develop (新 base,从 main 拉的)
- 临时分支: feature/<slug> / bugfix/<slug> / release/<stage> / hotfix/<slug>
- 详见 docs/agents/git-conventions.md §"分支工作流"
- PR 模板: https://github.com/YunC-GCT/MindTrace/compare/main...你的分支

首次同步:
git fetch origin
git checkout develop
git pull origin develop
git checkout -b feature/<your-first-ticket> develop
```

## 6. 验证一切就绪

跑下面 6 行:

```bash
git branch -a | head -10            # 应见 main / develop, YunCeH 在本地不在 origin
git remote show origin | grep -E "(main|develop)"   # 远程分支跟踪
gh repo view YunC-GCT/MindTrace --json defaultBranchRef   # 默认分支应 main
gh api repos/YunC-GCT/MindTrace/branches/develop/protection 2>/dev/null   # 应有保护规则返回
```

如果 `gh` 命令未装或返回 404,用 GitHub 网页眼睛目测:
- Settings → Branches → `main` 规则存在
- Settings → Branches → `develop` 规则存在
- Compare 页能看到 `develop` 分支可选

## 7. 你需要 commit 的本地改动(回仓前)

刚才 AI 帮你改了这些本地文件,**还没 commit**(红线):

```
M  .github/PULL_REQUEST_TEMPLATE.md        (去 YunCeH + 加 Branch type)
M  AGENTS.md                                (红线叙述:feature/* + develop)
M  docs/agents/git-conventions.md          (废弃 YunCeH + Git Flow 轻量版)
M  docs/agents/patterns/refactor-x.md      (命令示例:feature/*)
M  docs/style/naming-conventions.md        (分支约定:develop + feature/*)
A  .github/CODEOWNERS                       (新文件)
A  docs/agents/branch-protection.md         (新文件)
A  docs/agents/git-flow-setup-2026-09-04.md  (本文件,新)
```

### 提交建议(分 2 个原子 commit)

**Commit 1 — 文档与规范**:

```bash
git checkout -b feature/git-flow-lightweight develop
git add docs/agents/ docs/style/naming-conventions.md AGENTS.md .github/PULL_REQUEST_TEMPLATE.md
git commit -m "docs(agents): adopt Git Flow lightweight for 3-person team

- Add docs/agents/git-conventions.md §'分支工作流'
- Add docs/agents/branch-protection.md
- Add docs/agents/git-flow-setup-2026-09-04.md (manual ops checklist)
- Add .github/CODEOWNERS (default owner @YunC-GCT)
- Update .github/PULL_REQUEST_TEMPLATE.md: deprecate YunCeH, add Branch type
- Update AGENTS.md: red-line 6/7 refer feature/* + develop
- Update naming-conventions.md: § branch convention
- Update refactor-x.md pattern: git push example"

# 然后单独提交 .github/CODEOWNERS(让 owner 单独审)
git add .github/CODEOWNERS
git commit -m "chore(ci): add CODEOWNERS for 3-person review routing"
```

**Commit 2 — 跑 PR**:

```bash
git push -u origin feature/git-flow-lightweight
```

去 GitHub 打开 PR:`feature/git-flow-lightweight` → `develop`。

---

## 8. 红线清单(执行期间不要碰)

- ❌ 不进 `main`
- ❌ 不删 `origin/main`
- ❌ 不删 `origin/YunCeH`(若还有用,先用;不用再单独删)
- ❌ 不 force-push `origin/develop`(长期分支)
- ❌ 不直接 push 到 `main`(必须 PR)
- ✅ 临时分支可 force-push(只影响自己)

---

## 9. 后续维护

- 团队扩人 → 改 `.github/CODEOWNERS` + `branch-protection.md`
- 加 release 节奏 → 在 `git-conventions.md` §"关键时机" 表追加 `release/w6` 等实例
- 想换合并策略 → 改 `PULL_REQUEST_TEMPLATE.md` §"Merge strategy" + GitHub Settings → Allow merge methods
- 发现 doc 过期 → 本仓已有 ticket #1(doc expiry),把过期项加入

---

## 10. 一句话总览

| 谁 | 做什么 | 用什么 |
|---|---|---|
| **AI** | 本地 commit + 改 docs + 建文件 | `feature/<ticket>` from develop |
| **队友 A** | 同上,reviewer 给 B + owner | `feature/<ticket>` from develop |
| **队友 B** | 同上,reviewer 给 A + owner | `feature/<ticket>` from develop |
| **Owner(你)** | merge develop→release→main + 打 tag + 紧急 hotfix | 终端 + GitHub 网页 |

---

**整装待发**。所有本地改动已完成,你只需要:

1. 跑 §1 (push develop,2 分钟)
2. 跑 §4.2/4.3 (GitHub 网页设保护,10-15 分钟)
3. 跑 §7 (commit + PR,5 分钟)
4. 跑 §5 (通知队友,1 分钟)

**预计 30 分钟内 3 人协作工作流完整上线。**