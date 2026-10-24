# 033 进程边界与模块可见性契约

Status: accepted · 2026-10-24（S1 已落地并接入 gate；S2/S3 待定）
相关：`docs/system-architecture-layered.md`（逻辑分层 L1–L5）、`docs/specs/032-model-gateway-and-a2a-runtime.md`

## 1. 问题

逻辑分层（L1 入口 / L2 编排 / L3 能力 / L4 数据 / L5 基础设施）只回答了「谁调谁」，没有回答「**哪段代码允许被哪个进程加载**」。

2026-10-24 的事故就是这一维缺失导致的：

```
common/Index.ets 导出 LocalChatProvider（内部 import @kit.DataAugmentationKit）
        ↓
AgentExtAbility 只写了 import { LlmConfig } from 'common'
        ↓
barrel 求值 → 整个 @kit.DataAugmentationKit 进入 :agent 扩展进程
        ↓
该 Kit 限 PC/2in1 + 企业资质，扩展进程里初始化失败
        ↓
proxy SendRequest failed 201 / http handover manager init fail
        ↓
A2A 的 LLM 调用永不返回：日志停在「LLM 调用开始」，60s 超时都不触发
```

**机制要点：HSP 只有一个对外出口**（`oh-package.json5` 的 `main` 指向 `Index.ets`），且 ESM 的 barrel 是**静态全量求值**——`import { X } from 'common'` 会把 `Index.ets` 里 re-export 的所有模块都加载一遍。所以「只导出一个符号」在运行时等于「导出全部」。

## 2. 现状 as-built

### 2.1 进程

| 进程 | 由来 | 生命周期 | 说明 |
|---|---|---|---|
| `com.example.mindtrace`（main） | `EntryAbility` | 用户可见，前台/后台 | UI、数据库、模型调用（云端/端侧）都在这里 |
| `com.example.mindtrace:agent` | `AgentExtAbility`（`type: agent`） | 小艺调用时拉起，空闲回收 | 端A2A 服务端；**无 UI 能力** |
| `com.example.mindtrace:agentUI` | `AgentUIExtAbility`（`type: agentUI`） | 平台拉起（当前不自动拉起） | 半屏卡片 UI，有 ArkUI。**进程归属待证**：`AgentUIExtAbility.ets:18` 注释称「与 AgentExtAbility 同进程」，manifest 未声明 `process`——需真机同时拉起两个扩展抓 PID 才能定 |
| `com.example.mindtrace:render` | ArkWeb 渲染进程 | 随 Web 组件 | 只跑 web 内容，不加载应用代码 |
| 卡片宿主 | `cardservice` 的 `FormAbility` | 桌面卡片刷新时 | Form Kit 能力 |

### 2.2 模块

| 模块 | 形态 | 对外出口 | 被谁加载 |
|---|---|---|---|
| `entry` | HAP（entry） | — | main / `:agent` / `:agentUI`（按 srcEntry 分别加载） |
| `common` | HSP（shared） | `Index.ets`：**37 条值导出 + 17 条 `export type`** | 任何 import 它的进程 |
| `agents` | HSP（shared） | `Index.ets`，**13 条导出** | 任何 import 它的进程 |
| `cardservice` | feature（HAR） | 随 HAP 打包 | 卡片宿主 |

### 2.3 已登记的违规

| # | 违规 | 状态 |
|---|---|---|
| V1 | `common` barrel 导出 `LocalChatProvider`（受限 Kit） | 已从 barrel 移除，代码暂存 `entry/src/main/ets/services/` |
| V2 | 没有任何机制阻止「下一个受限 Kit 再被 barrel 导出」 | **已建**：`scripts/process-boundary/check.mjs` 接入 gate（S1） |
| V3 | 分层文档未记录进程维度 | 本文补齐 |

> V1 的临时处置（把 L3 能力放进 `entry`）**不符合逻辑分层**，是安全妥协，不是终态。终态见 §6。

## 3. 目标契约

### R1 扩展入口的可达集不得含受限能力

从扩展入口（`AgentExtAbility.ets`、`AgentUIExtAbility.ets`）出发，沿 import 图可达的所有模块，必须全部在**该进程的白名单**内。`from 'common'` / `from 'agents'` 一律按「该 HSP 的全部导出」展开计算。

### R2 `common` / `agents` 只放进程无关代码

共享层不允许出现：受限 Kit（见 §4 清单）、`@ohos.web.webview`、任何只能在 UI 进程求值的模块。

### R3 进程专用适配放 `entry`，且不进任何 barrel

> 注意：这**不构成对 L1–L5 的违反**。分层定义的是职责与调用方向，不是目录归属——`LocalChatProvider` 的职责仍属 L3 模型网关，只是实现按进程放在 `entry`。

目录：`entry/src/main/ets/ui-only/`（新增）。文件头必须写：

```ts
 * Process: main only. 不得被 agent / agentUI 入口可达，也不得进 common barrel。
```

`entry` 内部的 UI 代码可以直接 import；扩展入口目录（`entry/src/main/ets/agentextability/`）**禁止** import `ui-only/`。

### R4 新增受限能力必须先登记

任何新 Kit 进 `common` 之前，先在 §4 清单登记「允许的进程」；未登记的一律按「全进程禁止」处理，直到登记完成。

## 4. 受限能力清单（initial）

| 能力 | 包 / 符号 | 允许进程 | 依据 |
|---|---|---|---|
| 系统端侧问答模型 | `@kit.DataAugmentationKit`（`localChatModel`） | main | 限 PC/2in1 + 企业资质；扩展进程求值会破坏网络栈（已实测） |
| 小艺面板 | `@kit.AgentFrameworkKit`（`FunctionComponent`、`AgentController`） | main | 依赖 UI 与华为账号态 |
| ArkWeb | `@ohos.web.webview` / `Web` 组件 | main | 需要渲染进程与 UI 上下文 |
| 卡片 | `@kit.FormKit` | 卡片宿主 | 由 FormAbility 提供 |

## 5. 执行机制

新增 `scripts/process-boundary/check.mjs`，接入 `scripts/agent-gate/index.mjs`。

算法（已实现于 `scripts/process-boundary/check.mjs`）：

1. 入口**从各模块 `module.json5` 自动发现**（abilities + extensionAbilities + cardservice 的 FormAbility），不写死清单；扩展 `type` 映射到进程名。
2. 抽取会触发求值的说明符：静态 `import`、**值** `export ... from`、动态 `import()`：
   - `x` 为 `common` / `agents` → 展开 `Index.ets` 的 re-export 目标，**但 `export type` 跳过**（运行时被擦除，17 条类型导出不能算加载）；
   - `x` 以 `.` 开头 → 相对路径解析成工程内文件，继续遍历；
   - `x` 以 `@` 开头 → 查 §4 清单。
3. **运行时页面加载也要进图**：`windowStage.loadContent('pages/X')`、`session.loadContent(...)`、`router` 的 `url: 'pages/X'`，按模块的 `src/main/ets` 根解析（`AgentUIExtAbility → pages/AgentUiCard → common` 就是这条路径漏掉的那一环）。解析失败直接失败关闭。
3. 命中清单但进程不在白名单 → 失败，打印**完整路径链**：

```
[FAIL] process-boundary
  AgentExtAbility (:agent) 可达 @kit.DataAugmentationKit
    链：AgentExtAbility.ets → common (Index.ets) → llm/LocalChatProvider.ets → @kit.DataAugmentationKit
  允许进程：main；当前：agent
```

4. 同时检查 R3：`agentextability/` 目录下任何文件 import 了 `ui-only/` → 失败。

这条检查的价值：**它拦的是「barrel 传染」，而不是「有人手滑 import 了 Kit」**——今天这次事故，肇事代码是一行完全合法的 `import { LlmConfig } from 'common'`。

## 6. 迁移步骤

| 步 | 动作 | 判据 |
|---|---|---|
| S1 | 落 `process-boundary` 检查并接 gate | ✅ 已落：6 入口 / 378 文件可达；4 条回归测试（含 barrel 传染、`export type` 不误报、`loadContent` 入图） |
| S2 | spike：`LocalChatProvider` 改**动态 import** Kit，回迁 `common` | HSP 打包支持动态 import；小艺仍 1.5s 返回 |
| S3 | 若 S2 不可行：拆 `capabilities` HSP（只被 `entry` 依赖） | `:agent` 的依赖树里不含 `capabilities` |
| S4 | 红线 + phase tracker 记账 | AGENTS 红线 11 升级为「先登记、再进 barrel」 |

S2 优先于 S3：结构不变、成本最小；S3 是分层最干净的兜底。

## 7. 未决

- 动态 import 在 HarmonyOS HSP 里是否可用（本仓库无先例，需 spike）。
- `agentUI` 是否独立进程未定（见 §2.1）；若是同进程，白名单要按「实际进程」而不是「入口」合并。
- Codex 评审（gpt-6-astra, max）提出的三条 P0 已核实并修入本版；仍未决的是 S2 的编译可行性。
- 卡片宿主是否需要独立白名单（`cardservice` 目前只依赖 `common`）。
