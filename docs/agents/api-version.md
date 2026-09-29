# API 版本兼容 & ArkTS strict 适配

## 当前版本

- 当前项目 API/SDK 基线以 `build-profile.json5` 为准；当前为 **6.1.1(24)**。
- 使用系统 API 前必须核对当前 SDK 与官方文档；禁止使用高于已配置 SDK 的 API。
- ArkTS strict 规则由项目 lint/检查链强制，不再依赖旧 API 9 假设。

## ArkTS 1.1 strict 完整规则

**40+ 规则表 (含 rule ID + error code + 代码示例 + 验证命令)** 见 [`docs/style/arkts-1.1.md`](../style/arkts-1.1.md) (2026-09-01 从子代理调研笔记 §3.2 抽出)。

主要分组 | 关键规则 | Error code |
|---|---|---|
| 类型系统 | `any` / `unknown` 禁; 结构 / mapped / conditional / intersection 禁; `<T>x` 禁 (用 `as`); catch 不能 typed | 10605xxx |
| 控制流 | `for..in` 禁; 解构赋值/声明/参数 禁; `var`/`#private`/`function` 表达式/`with`/`delete`/`class` 表达式/嵌套函数/generator 禁 | 10605xxx |
| 对象与类 | `obj['key']` 动态属性禁; 类只能 `implements interface`; `this` 类型禁 | 10605xxx |
| ArkUI 项目偏好 (严格于官方) | struct 内禁普通方法 (用箭头函数字段 / `@Builder`); struct 内禁 `get` accessor; struct 字段名避开 CommonAttribute 方法名 | project-pref |

## Lint job 现状 (强制执行)

| Lint 引擎 | 规则数 | Baseline | 详细 |
|---|---|---|---|
| v1 (regex) | 25 规则 | 0 errors / 285 warnings | [`scripts/audit-arkts-strict.mjs`](../../scripts/audit-arkts-strict.mjs) |
| v0.3 AST (推荐) | **34 规则 + 63 单元测试** | 0 errors / **253 warnings** (90 个是 fix 后的真问题,对应 audit §4.9/§4.10 god-class) | [`scripts/arkts-lint/`](../../scripts/arkts-lint/) + CI |

CI 已接入: [`.github/workflows/arkts-lint.yml`](../../.github/workflows/arkts-lint.yml)

## API 用法边界

当前是否可用由 `build-profile.json5` 配置的 SDK 与官方文档共同决定。旧文档中“API 12+ 一律不能用”的说法已过期；但任何高于当前 SDK 或当前设备/模型约束不支持的 API 仍然不能引入。

| 特性 | API | 备注 |
|---|---|---|
| `.stateStyles()` 基础态 | API 7 ✓ | 可用 |
| `.stateStyles()` `selected` 子态 | API 10+ | 按当前 SDK/官方文档核对后使用 |
| `.blur()` / `visualEffect` / `backgroundFilter` | API 12+ | 按当前 SDK/官方文档核对后使用 |
| `@kit.ArkTS.JSON` 模块 | API 12+ | 优先沿用项目既有 JSON 策略；使用前核对 SDK |
| `@ComponentV2` / `@Local` / `@Param` / `@ObservedV2` / `@Trace` | API 12+ | 本项目默认仍用 V1；迁移需专项设计 |
| `AgentExtensionAbility` | API 24+ | 当前 SDK 已达到 API 24；使用前仍须核对应用能力配置与官方文档 |

## API 用法注意

- `Image.rotate({ angle })` 接**对象** (`{angle: number}`),不是 number
- ArkUI 1.1 默认响应 `@State`,`.translate()` 与 `.offset()` 都可用,但 `.translate()` 参与 transformation chain
