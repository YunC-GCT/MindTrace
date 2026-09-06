# D4 — 鸿蒙 Kit 采用范围与替换边界

> **Status**: P0 契约已落地 (`common/kit/`, 2026-09-05);entry 端实现与实际 Kit 资源接入**后续评估**(2026-09-06 决策, 见 ADR-0009)
> **Date**: 2026-09-05
> **Source decision**: GitHub issue #11
> **Scope**: 仅架构规范化与 Kit 替换边界定义，不在本阶段实施具体替换。

## Why this ticket

D1 决策已经定下：

- OCR 保留自研
- 其余主链路优先 Kit 化

但具体哪些 Kit 在本次时间盒内替换、哪些保留自研、哪些只在节点接缝处提供 facade 没有明确边界。直接替换会破坏现有业务；完全不替换又浪费平台能力。

## Goals

1. 在 D2 CaptureGraph 节点接缝上定义 Kit 适配边界，让节点可替换
2. 列出本次时间盒内 P0/P1/P2/P3 优先级
3. 给出每个 Kit 的适配点、评估成本、不推荐理由
4. 不实施具体 Kit 替换；只产出接缝与契约

## Non-goals

- 不引入新 Kit 依赖到 package.json
- 不改写 `OcrTool` 之外的业务实现
- 不做性能 / 体积 / 兼容性优化

## Priority matrix（基于调研结论）

| Kit | 当前使用 | 优先级 | 适配点 |
|---|---|---|---|
| `@kit.NotificationKit` `ReminderAgent` | 未用 | **P0** | 复习提醒节点 |
| `@kit.BackgroundTasksKit` | 未用 | **P0** | 后台拉取节点 |
| `@kit.FormKit` / `@ohos.app.form.*` | 部分（mock）） | **P0** | 桌面卡片节点 |
| `@kit.AIEngine` / `@hms.ai.llm` | 未用 | **P1** | `LlmClient` facade |
| `@kit.ArkData` `relationalStore` | 已用 | 维持 | 不动 |
| `@kit.CoreVisionKit` | 已用（OCR 兜底） | 维持 | 不动 |
| `@kit.NetworkKit` | 已用 | 维持 | 不动 |
| `@kit.ImageKit` | 已用 | 维持 | 不动 |
| `@kit.ArkData` `preferences` | 已用 | 维持 | 不动 |
| `PushKit` | 未用 | **P3** | 复赛窗口不做 |
| `UniversalKeystoreKit` | 未用 | **P3** | LLM key 自配无收益 |
| `AVPlayerKit` / `MediaKit` | 未用 | **P3** | 无业务入口 |
| `ScanKit` | 未用 | 低 | 业务无扫码入口 |

## P0 适配点（接入但不替换业务实现）

```text
CaptureGraph node 适配：每节点内部调用 Kit facade。
Kit facade 位于 common/kit/。
业务节点 (agents/) 仍走 CaptureGraph。
```

- `ReminderAgent`：在 `entry/services/` 注入到 CaptureGraph 的 `remind` 节点
- `BackgroundTasksKit`：通过 `entry/services/BackgroundTaskService` 暴露给 CaptureGraph
- `FormKit`：仅替换现有 mock FormAbility 数据来源

## P1 适配点

- `AIEngine`：仅在 `LlmClient` 内部做能力探测，外部仍是统一 `call(opts)` 接口
- `@hms.ai.llm`：作为云端 fallback，明确与 `LlmConfig` 配合

## P3 不建议

- 复赛窗口上 `PushKit`：上云连锁改动、隐私评估
- `UniversalKeystoreKit`：LLM key 自配无内置 secret，无收益
- `AVPlayerKit` / `MediaKit`：无业务入口

## Acceptance criteria

- [ ] `common/kit/` 目录与文件命名符合项目 kebab-case 规范
- [ ] 每个 P0 Kit 有独立 facade 接口
- [ ] D2 节点可以无侵入调用 Kit facade
- [ ] 不实施实际 Kit 替换；只产出接缝与契约
- [ ] 不执行 build / push / 未授权 commit

## Out of scope

- 实际 Kit 调用实现
- 性能优化与降级策略
- 端侧 Kit 替代现有服务的迁移脚本