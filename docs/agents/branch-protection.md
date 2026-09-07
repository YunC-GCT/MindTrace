# Branch protection rules

> **MindTrace** 远程仓库的分支保护规则参考清单。2026-09-04 起,3 人协作 Git Flow 轻量版采用。
> **Source-of-truth**: GitHub 仓库 Settings → Branches / Rulesets(你手动配置,AI 不操作)。
>
> **Visibility**: 仓库已设 **Public**(2026-09-04)。**Public 后所有 protection rules 自动 enforce**(private + free plan 下显示 "Not enforced" 的限制已解除);CODEOWNERS checkbox 现在可勾。
>
> ⚠️ **Public 仓库注意事项**:
> - API key / secret 一律走 env / vault,**不入 git**(per `docs/agents/security.md`)
> - 历史 commit 也会被搜索到,所以**已 commit 的 secret 不能只删当前文件**,需 `git filter-repo` 或 BFG 清理历史(若发生泄露,立即 rotate key)
> - 当前 `.github/CODEOWNERS` 三 owner 路由:`@YunC-GCT` / `@rc-shi` / `@cmnon159`(任一 approve 即可)

---

## 受保护分支

### 1. `main`

| 规则 | 值 | 理由 |
|---|---|---|
| **Require a pull request before merging** | ✅ | 禁止直接 push |
| **Required approvals** | `1`(可 owner self-approve,见下) | 团队 3 人小团队,允许 owner 自我 approve 提高效率 |
| **Dismiss stale pull request approvals** | ✅ | 重新 push 后要求重 review |
| **Require review from Code Owners** | ✅ | CODEOWNERS 自动指派 |
| **Require status checks to pass** | ✅ | arkts-lint + naming-lint + link-check |
| **Required status checks** | `arkts-lint` / `naming-lint` / `link-check` | 见 `.github/workflows/` |
| **Require linear history** | ❌ | release/hotfix 允许 merge commit 保留历史 |
| **Include administrators** | ✅ | owner 自己也受规则约束 |
| **Allow force pushes** | ❌ | 严禁 |
| **Allow deletions** | ❌ | main 不可删 |
| **Block creations** | ❌ | 允许其他 release / hotfix 从 main 拉 |
| **Required conversation resolution** | ✅ | 评论必须 resolve 才能 merge |

### 2. `develop`

| 规则 | 值 | 理由 |
|---|---|---|
| **Require a pull request before merging** | ✅ | feature/bugfix PR 合入 |
| **Required approvals** | `1`(owner self-approve 暂未 enforce,见 §3) | 当前 team 阶段允许 owner self-approve,见 §3 |
| **Require review from Code Owners** | ☐ | **不勾**(避免因只有 1 个 owner 而 block PR),通过 §3 self-approve 策略补强 |
| **Require status checks to pass** | ✅ | 同上 3 个 |
| **Required status checks** | `arkts-lint` / `naming-lint` / `link-check` | |
| **Require linear history** | ❌ | release/hotfix 允许 merge commit 保留历史;feature 用 squash merge 但不强制 linear |
| **Include administrators** | ✅ | owner 自己也受规则约束 |
| **Allow force pushes** | ❌ | |
| **Allow deletions** | ❌ | develop 是长期分支,不可删 |

### 3. 3-Owner 路由策略(2026-09-04 团队共识)

> **背景**: 比赛项目 + 3 人小团队。`YunC-GCT` / `rc-shi` / `cmnon159` 都已加入 collaborator(Write权限)。
>
> **决定**: 采用 **3 owner 路由**:
>
> 1. **任何 CODEOWNERS 中列出的 owner**(默认 `@YunC-GCT` / `@rc-shi` / `@cmnon159` 中任一)approve 即可
> 2. **不**勾选 `Require approval of the most recent reviewable push`(允许 owner 自我 approve,作为兜底——主流程仍是队友互审)
> 3. **必须**所有 CI status checks 全绿(3 个 lint check)
> 4. **必须** PR base 正确(feature/* → develop;hotfix/* / release/* → main)
>
> ### 3.1 当前实际勾选状态(终态)
>
> |字段 | 状态 |
> |---|---|
> | Require a pull request before merging | ✅ |
> | Required approvals (number = 1) | ☐ **(故意不勾)** — 用 CODEOWNERS 路由替代 |
> | Require review from Code Owners | ☑ ✅ **(已勾,** CODEOWNERS 路由生效)|
> | Require approval of the most recent reviewable push | ☐ (允许 self-approve 兜底)|
> | Require status checks to pass | ✅ |
> | Require conversation resolution | ✅ |
> | Include administrators | ✅ |
> | Allow force pushes | ☐ |
> | Allow deletions | ☐ |
>
> ### 3.2 升级触发条件
>
> - 团队扩展到 5+ 人:加勾 `Require approval of the most recent reviewable push`,强制非作者 review
> - 出现 release 节奏 + 严格 gate:加勾 `Required linear history`
> - 有人故意放水:加勾 `Required signed commits` + CODEOWNERS 严化

### 4. 关键修正:`bypass_mode = "pull_request"`(2026-09-05 12:14)

> **背景**: 初次创建 Rulesets 时 `bypass_actors[*].bypass_mode` 设为 `"always"` —— 这意味着 Repository Admin(actor_id=4)和 Maintain(actor_id=5)**可以完全绕过所有规则**,包括 direct push 到 main。这造成"AI 在其他 session 直接 push 到 main"风险。
>
> **修正**(2026-09-05 12:14): `bypass_mode` 从 `"always"` → **`"pull_request"`**。
>
> **效果对比**:
>
> | 路径 | Before(always) | After(pull_request) |
> |---|---|---|
> | `git push origin main`(直接 push) | ⚠️ Admin 可绕过 ✅ | ❌ **Admin 也被拦** |
> | `git push origin feature/xxx` | ✅ 不受限(临时分支) | ✅ 不受限 |
> | PR `feature/* → main` 走 review | ✅ 可走 | ✅ 可走 |
> | Admin 在 PR 里 self-approve | ✅ 可走 | ✅ 可走(兜底)|
> | `current_user_can_bypass` 字段 | `always` | **`pull_requests_only`** |
>
> **结论**: 现在 `git push origin main` **被 ruleset 完全挡住**(任何人,包括 admin)。AI 在其他 session 必须走 **PR 流程**(创建 feature 分支 → push → 开 PR → review → merge),无法直接动 main。
>
> **api 更新命令**(gh CLI,需 admin scope `repo`):
>
> ```bash
> gh api --method PUT /repos/YunC-GCT/MindTrace/rulesets/22318353 \
>   --input .scratch/protect-main.json
> gh api --method PUT /repos/YunC-GCT/MindTrace/rulesets/22318810 \
>   --input .scratch/protect-develop.json
> ```
>
> **未来变更流程**: 修改 `.scratch/protect-main.json` 或 `.scratch/protect-develop.json` → 用 gh PUT 更新 → 验证 `current_user_can_bypass: pull_requests_only` 保持 → 提交 commit message 记录变更。

### 3. 不受保护

- `feature/*` / `release/*` / `hotfix/*` / `bugfix/*` — **临时分支,无需保护**
- 删除 / force push 均可(临时分支合入后即删)

---

## CODEOWNERS 集成

| 触发 | 行为 |
|---|---|
| 打开 PR | GitHub 自动从 `.github/CODEOWNERS` 找匹配行的 owner,加为 reviewer |
| 团队扩展 | 编辑 `.github/CODEOWNERS` 在合适 path 加 `@<github-handle>`,新 reviewer 会自动出现在该 path 的 PR 上 |
| 默认 fallback | 未列文件 → `* @YunC-GCT` 兜底 |
| **Public 后强制 review** | public + 任一保护分支的 "Require review from Code Owners" 勾选后,匹配路径的 PR 缺 owner review **不能 merge** |

详见 `.github/CODEOWNERS` 文件本身。

### Visibility 切换记录

| 日期 | 状态 | 触发原因 |
|---|---|---|
| 2026-09-04 | Private → **Public** | 比赛项目需要公开 commit history / PR 供评委查看;同时解开 private + free plan 下 "Not enforced" 的限制 |

切换步骤(owner 操作,AI 不做):
1. https://github.com/YunC-GCT/MindTrace/settings/general → 滚到 Danger Zone
3. **Change repository visibility** → 选 Public
4. 二次确认输仓库全名 `YunC-GCT/MindTrace`

切换后:
- `main` / `develop` ruleset 自动从 "Not enforced" → enforce
- "Require review from Code Owners" checkbox 从灰 → 可勾
- 历史 commit 全部公开,含 `git-conventions.md` 里废弃的 `YunCeH` 分支历史(信息透明)

---

## CI status checks 来源

`main` / `develop` 保护规则要求的 3 个 status checks 来自 `.github/workflows/`:

| Workflow | 检查内容 |
|---|---|
| `arkts-lint.yml` | `node scripts/arkts-lint/index.mjs --quiet` — ArkTS 1.1 strict 引擎 |
| `naming-lint.yml` | `node scripts/naming-lint/index.mjs` — 文件 / 目录命名规范 |
| `link-check.yml` | `node scripts/link-check/index.mjs` — 文档死链扫描 |

CI 全部 green 才能 merge。

---

## 维护

- 调整保护规则 → GitHub 网页操作,本文件手动同步
- 新增 reviewer → 改 `.github/CODEOWNERS` + 在本文件 §"CODEOWNERS 集成"追加说明
- 新增 CI check → 在 `.github/workflows/` 加 workflow + 在本文件 §"CI status checks"追加一行 + GitHub 把新 check 标为 Required