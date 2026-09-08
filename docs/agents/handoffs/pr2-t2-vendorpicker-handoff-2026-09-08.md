# PR2-T2 Handoff — AI 设置页 UI 重构(开发者在 DevEco 续接)

> **For**: 在 DevEco 续接 PR2-T2 的开发者(后续 session agent)
> **Status**: 29/29 测试 GREEN + Build SUCCESSFUL + 真机 UI 已可验。**还有 1 个未提交 + 视觉重构未提交**。
> **Branch**: `feature/pr2-t2-ui-vendorpicker`(worktree `mt-llm-config-audit`)
> **PR2-T2 spec**: `docs/specs/016-llm-settings-redesign.md`

---

## 1. 一句话状态

5 个 vendor picker UI + 编辑 panel + 添加 vendor modal + 整行卡片化视觉重构**已完成**(29/29 测试 GREEN + build 6.8s SUCCESSFUL)。**真机 UI 已可验**,但 vendor model 状态 + per-vendor API key **刷新页面会丢**(未持久化)。

---

## 2. 上下文指针(必读)

按 `AGENTS.md` 的"改什么 → 读哪",本任务相关:

- **`AGENTS.md`** §"7 红线" + §"5 module 拓扑" — 必读
- **`docs/specs/016-llm-settings-redesign.md`** PR2-T2 段 — 设计规范(原始)
- **`docs/agents/file-header-template.md`** — .ets 文件头 9 字段格式
- **`docs/style/arkts-1.1.md`** — ArkTS 1.1 strict(40+ 规则)
- **`.pr2-t2-design.html`**(worktree 根临时) + **`.pr2-t2-design.md`**(worktree 根临时) — v6 设计稿 + 设计决策记录
- **`docs/research/frontend-component-audit-2026-09-06.md`** — 前端组件审查(参考)

> **不要重复**这些文件已说明的内容。本文只写"从这里**继续**做"。

---

## 3. 当前 git 状态(开发者关键信息)

```bash
# 当前分支
feature/pr2-t2-ui-vendorpicker   # 基于 bugfix/llm-config-audit-2026-09-06

# Uncommitted + Untracked:
#   M entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets          (import + build 段改用 VendorPicker)
#   M entry/src/main/ets/viewmodels/AiSettingsViewModel.ets             (加 vendorId / selectVendor / addCustomVendor / getCurrent* / load 读 vendorId / save 持久化)
#   + entry/src/main/ets/pages/AiSettings/VendorPicker.ets              (新文件,~340 行)
#   + scripts/arkts-lint/tests/ai-settings-vendor.test.mjs               (29 tests)
#   ?? .pr2-t2-design.html / .pr2-t2-design.md                          (临时,**不要 commit**)
```

**不要 `git push`**(AGENTS 红线 1)— user 没明确说 push 之前。

---

## 4. 设计语言锁(防止后续 agent 改回旧版)

PR2-T2 这轮**真实机**验证后,以下视觉决策**有强约束**,后续 agent **不要回退**:

| 元素 | 必须用 | 禁止用 |
|---|---|---|
| **Radio 视觉** | Text 字符 `●` / `○` + `fontColor(MINT / TEXT_3)` | `Stack(Line + Circle)` 真机不渲染;`Circle().fill(...)` 在 Stack 内不可靠 |
| **当前 vendor 高亮** | 整行 `.backgroundColor('#0F2A22') + .border(MINT) + 独立 "当前活跃" Text 徽章` | `Row.backgroundColor(Color.Green)`(整行绿底可,边框+徽章是关键) |
| **编辑 button** | `Text('编辑') + .border({ color: MINT_BORDER }) + .borderRadius(R_SM)` | `Button('编辑')` ArkUI default 蓝(没设计感);`Text + .backgroundColor(MINT)` 实心填充 |
| **添加 model button** | `Text('+') + .border(MINT_BORDER) + .borderRadius(R_SM)`(描边按钮) | 实心 Button 蓝 |
| **+ 添加新供应商** | `Row + .border({ style: BorderStyle.Dashed, color: MINT_BORDER }) + .borderRadius(R_MD) + Text(MINT)` | 任何非 dashed 边框 |
| **Modal 卡片** | `BG_CARD + BORDER` 边框 + 内部输入框用 `BG_DARK + BORDER` | 字面 `'#1A1F2A' / '#888' / '#666'` |
| **颜色 token** | `MINT / MINT_BORDER / BG_CARD / BG_DARK / TEXT / TEXT_3 / TEXT_4 / BORDER` from `'common'` | 任何 `Color.Green / Color.Gray / '#XXXXXX'` 字面(除 `'#0F2A22'` 当前行背景例外)|
| **字体** | `F_XS / F_SM / F_MD / W_NORMAL / W_MEDIUM / W_SEMIBOLD` from `'common'` | 任何 `fontSize(12 / 13 / 14)` 字面 |

**为什么**:ArkUI 真机**不渲染** Row.borderRadius on Text、Stack(Line + Circle) 透明背景、Circle() 在 Stack 嵌套内。必须用 Text 字符 + common tokens。

---

## 5. 跑测试 / build 验证

**第一次跑必做**(开发者接手时):

```bash
# 1. 测试 29/29 GREEN
node --test scripts/arkts-lint/tests/ai-settings-vendor.test.mjs
# 期望:ℹ tests 29 ... pass 29 fail 0

# 2. Build SUCCESSFUL
# Windows PowerShell + hvigor CLI:
$env:DEVECO_SDK_HOME = 'D:\HarmoNova\DevEco Studio\sdk'
$env:PATH = 'D:\HarmoNova\DevEco Studio\jbr\bin;' + $env:PATH
& 'D:\HarmoNova\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap
# 期望:BUILD SUCCESSFUL

# 3. .hap 产物
ls -la entry/build/default/outputs/default/entry-default-unsigned.hap
# 期望:~6.89 MB,生成时间 < 1 hour
```

**任一不通过** → **不要继续**,先看哪里坏了。

---

## 6. 关键文件(开发者要改的)

| 文件 | 改什么 | 怎么改 |
|---|---|---|
| `entry/src/main/ets/pages/AiSettings/VendorPicker.ets` | UI 视觉修改 | 改 build 段,保持 §4 锁的约束 |
| `entry/src/main/ets/viewmodels/AiSettingsViewModel.ets` | 加字段/方法 | 不要动已固化的 vendorId / selectVendor / addCustomVendor / getCurrent*;P4 持久化时**只加** KEY_CUSTOM_VENDORS + 读写方法 |
| `entry/src/main/ets/pages/AiSettings/AiSettingsPage.ets` | 顶层布局 | 用 vm.getCurrentVendor() 等,不要回退到 modelSummary/endpointSummary |
| `scripts/arkts-lint/tests/ai-settings-vendor.test.mjs` | 加新测试 | 必须用 §4 锁的视觉验证(`.backgroundColor('...')` 而不是字面色) |
| `entry/src/main/ets/pages/AiSettings/EndpointPicker.ets` | **删除** | `git rm` — 已被 VendorPicker 替代(AGENTS 红线 3:不 overwrite 已删文件) |
| `entry/src/main/ets/pages/AiSettings/ModelPicker.ets` | **删除** | `git rm` — 同上 |

---

## 7. PR2-T2 已完成的工作

| Ticket | 内容 | 状态 |
|---|---|---|
| **P1** | `vm.save()` 持久化 `vendorId`(`llm.setVendorId()`) + `vm.load()` 还原(`llm.getVendorId()`) | ✅ |
| **P2-a** | 编辑 panel 展开(`@State editingVendorId` 单真理源) | ✅ |
| **P2-b** | 编辑 panel 完整内容:API Key + 模型目录 + line+circle radio + × delete + + add | ✅ |
| **P3** | 添加 vendor modal(Stack overlay + 4 字段 + onAddVendorConfirm 回调) | ✅ |
| **视觉重构** | vendor row 卡片化 + common tokens + 真机兼容 | ✅ |

---

## 8. 已知限制(后续 PR 处理)

按优先级:

| # | 限制 | 影响 | 后续 PR 工作 |
|---|---|---|---|
| L1 | `LlmConfig` 只支持 1 个 customVendor(非 list) | 用户的 custom vendors **不持久化**,刷新页面 + 重启 app 后丢失 | 扩 LlmConfig 加 `KEY_CUSTOM_VENDORS` (JSON 数组) + 读写 API |
| L2 | vendor 编辑 panel 内的 model list 是 `VendorPicker.@State`,刷新就丢 | 切到某 vendor 添加 model,刷新页面后只剩 defaultModel | 同 L1 一起:per-vendor models 持久化 |
| L3 | per-vendor API Key 走 `KeyInput` 段全局 1 个 key | panel 内的 API Key TextInput 没接任何持久化 | 扩 AssetStoreKit 加 per-vendor alias |
| L4 | `AiSettingsViewModel` 旧字段未删:`useCustomEP / customEP / mdlIdx / useCustomMD / customMD / temp / maxT / to` + `syncEndpoint / syncModel` 关键字嗅探 + 12 个 set/toggle/resolve 方法 | ticket #9 "LlmConfig 静默覆盖" 修复目标未完整达成(只删 2 个 UI 状态) | **当前工作只做增量**,**不要在这个 PR** 删旧字段(防止破坏引用)— 后续 ticket #9 清理 PR |
| L5 | `EndpointPicker.ets` / `ModelPicker.ets` 文件未 `git rm` | 死代码,build 仍包含 | 收尾:`git rm` + 验证 build |

---

## 9. 续接时建议的下一步(按 user 节奏选)

| 选项 | 内容 | 工时 |
|---|---|---|
| **A. 收尾 commit** | 整理 git status + commit(`git add` + `git commit`);不动 L1-L4 | 10 min |
| **B. push + PR** | user 明确说 push 后 → `git push -u origin feature/pr2-t2-ui-vendorpicker` + `gh pr create --base develop` | 10 min |
| **C. 删旧文件 + commit** | `git rm EndpointPicker.ets ModelPicker.ets` + commit L5 | 15 min |
| **D. 清理旧 ViewModel 字段** | L4 完整清理 + 新增更多测试 | 1-2 hr(高风险,可能影响其他引用)|
| **E. P4 持久化** | L1 + L2 + L3 一起做 | 2-3 hr(需要扩 LlmConfig + 写测试)|

**建议路径**:A → C → B(等 user 明确 push)

---

## 10. 真机验收 checklist(DevEco Run → Run 'entry')

- [ ] 5 个 vendor 卡片(DeepSeek / 通义 / GLM / Kimi / 豆包),整行**圆角卡片**带边框
- [ ] 当前 vendor:绿底 + MINT 边框 + 下方 "**当前活跃**" 徽章
- [ ] 左侧 ● 实心 / ○ 空心字符 radio(MINT / TEXT_3)
- [ ] 中间 vendor 名 + 灰色 baseUrl
- [ ] 右侧 "编辑" MINT 描边按钮
- [ ] 点 "编辑" → panel 展开(API Key 输入 + 模型目录 + × + +)
- [ ] 点 "+ 添加新供应商" → modal 弹出(Stack 遮罩 + 卡片 + 4 字段 + 取消/添加)
- [ ] 切到其他 vendor → AI 服务段更新
- [ ] API Key 段(全局)仍工作

**任一不通过** → 截图 + 描述,我来 debug。

---

## 11. 沟通模板

给后续 agent / developer 的指令格式(用 markdown):

```text
## 任务
{明确单句,如"删 EndpointPicker.ets + 跑 build 验证"}

## 约束(来自 PR2-T2 设计语言锁)
- vendor row 视觉保持卡片化 + common tokens
- 不要回退到 Button(Text + border 风格)
- 编辑 panel 单真理源(@State editingVendorId in VendorPicker)

## 完成标准
- `node --test ...` 仍 29/29 GREEN
- `hvigorw assembleHap` SUCCESSFUL
- .hap 文件存在且最新

## 不要做
- 改 ViewModel 旧字段(useCustomEP / syncEndpoint 等)— L4 后续 PR
- 改设计语言锁的视觉
- push(user 没说)
```

---

**最后更新**: 2026-09-08(本 session 内)
**作者**: MiniMax-M3 / DeepSeek Harness(本 session agent)
**给**: 续接 PR2-T2 的开发者 + 后续 session agent
