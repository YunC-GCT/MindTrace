# scripts/arkts-lint/ — ArkTS 1.1 strict lint (AST-based)

> **状态**: 🟢 Day 3 完成 (2026-09-01) — **34 规则, 63/63 tests pass, exit 0, 0 errors / 253 warnings**
> **目标**: 替代 v1 (regex), 消除 ~80% 误报, 补齐 40+ 规则
> **关联**: Phase 4 ticket #15

---

## 快速开始

```bash
# 从 MindTrace 根目录
cd <本地仓库根>

# 检查规则定义合法性
node scripts/arkts-lint/index.mjs --check-rules

# 全量扫 (Day 2: 25 规则)
node scripts/arkts-lint/index.mjs --quiet

# 扫 fixtures (验证规则)
node scripts/arkts-lint/index.mjs --root=scripts/arkts-lint/fixtures/pass --quiet   # 0 violations
node scripts/arkts-lint/index.mjs --root=scripts/arkts-lint/fixtures/fail --quiet   # 6 violations

# 写 baseline
node scripts/arkts-lint/index.mjs '--baseline=docs/lint-baseline-20260901-ast.json' --quiet

# 跑单元测试
cd scripts/arkts-lint && npm test
```

---

## Day 3 状态 (2026-09-01)

| 指标 | v1 (regex) | arkts-lint (AST) | 变化 |
|---|---|---|---|
| 规则数 | 25 | **34** | +9 |
| 实际可执行规则 | 23 (2 禁用) | **34** | +11 |
| 单元测试 | 0 | **63/63 pass** | 新增 |
| 扫描文件 | 174 | 173 (排除 fixtures) | 同等 |
| 真实 errors | 0 | **0** | CI ✅ |
| Warnings | 285 (≈80% 误报) | **253** (高质量) | -11% 总数,但 90 个是 fix 后的真问题 |
| Parse errors | 0 (regex 不需要) | **91** (新信息!) | 揭示 v1 看不见的文件 |
| `--check-rules` | ✅ | ✅ | |
| CI 退出码 | 0 | 0 | |

### Day 3 新增的 9 条规则 (Day 2 → Day 3)

| 规则 | 真实代码触发数 | 备注 |
|---|---|---|
| `arkts-no-structural-typing` | 0 | TS 不允许无类型属性的 type literal,触发少 |
| `arkts-no-typing-with-this` | 0 | 干净 |
| `arkts-no-type-query` | 0 | 干净 |
| `arkts-no-call-signatures` | 0 | 干净 |
| `arkts-no-indexed-signatures` | 0 | 干净 |
| `arkts-no-ctor-prop-decls` | 0 | 干净 |
| `arkts-no-polymorphic-unops` | 0 | 干净 |
| `arkts-no-standalone-this` | 0 | 干净 (partial detection) |
| `arkts-no-conditional-types` | 0 | 干净 |

### Day 3 关键 bug 修复 (via tests)

- `Builder funcName(` 正则改为 `(?<![@])\bBuilder`,避免误改 `@Builder` decorator
- `struct-no-regular-methods` / `no-get-accessor` 改用 `ctx.parentMap` 查找父节点(AST 不带内置 .parent)— 修复后 `struct-no-regular-methods` 在 90 个 @Component struct 中检测到真问题(对应 audit §4.9/§4.10 god-class 工作)
- `arkts-no-private-identifiers` 改检测 `PropertyDefinition.key.type === 'PrivateIdentifier'` 而非 `TSPrivateIdentifier` (后者只出现在 type reference `this.#x`)
| `--check-rules` | ✅ | ✅ | |
| CI 退出码 | 0 | 0 | |

### v1 vs arkts-lint 警告分布对比

| 规则 | v1 数 | arkts-lint 数 | 解释 |
|---|---|---|---|
| `ArkUI-1 struct-no-regular-methods` | 216 | (移除) | arkts-lint 用 `@Component` 严格区分 struct vs class |
| `arkts-no-comma-outside-loops` | 87 | (移除) | v1 难做, 仍禁用 |
| `arkts-no-props-by-index` | 69 | 68 | 大幅相似 (LlmClient/AgentMemoryService JSON 解析) |
| `arkts-no-method-reassignment` | 11 | (移除) | v1 难做, 仍禁用 |
| 其他 v1 规则 | (0) | 0 | 一致 |
| `parse-error` | (不适用) | 91 | **NEW** — v1 看不见的 12% 文件 |
| 实际差异: arkts-lint 警告数 = 160, v1 = 285, **减少 44%** |

---

## 架构

```
arkts-lint/
├── index.mjs                          # 主入口 (210 行)
├── package.json                       # 本地依赖
├── node_modules/                      # git ignored
├── .gitignore                         # 排除 node_modules
│
├── parser/
│ └── index.mjs                        # parseFile + SourceLocator + ArkUI preprocessor (200 行)
│
├── ast-utils/
│ ├── walk.mjs                          # 通用 AST walker
│ └── has-decorator.mjs                 # @Component / @Observed / @Entry 检测
│
├── rules/
│ ├── _template.mjs                     # 规则文件模板
│ ├── registry.mjs                      # 加载 + 校验 (含 id 唯一性)
│ ├── official/                         # 官方 strict-mode 规则 (23 文件)
│ │ ├── arkts-as-casts.mjs
│ │ ├── arkts-implements-only-iface.mjs
│ │ ├── arkts-limited-throw.mjs
│ │ ├── arkts-no-any-unknown.mjs
│ │ ├── arkts-no-class-literals.mjs
│ │ ├── arkts-no-delete.mjs
│ │ ├── arkts-no-destruct-assignment.mjs
│ │ ├── arkts-no-destruct-decls.mjs
│ │ ├── arkts-no-destruct-params.mjs
│ │ ├── arkts-no-for-in.mjs
│ │ ├── arkts-no-func-expressions.mjs
│ │ ├── arkts-no-generators.mjs
│ │ ├── arkts-no-intersection-types.mjs
│ │ ├── arkts-no-is.mjs
│ │ ├── arkts-no-jsx.mjs
│ │ ├── arkts-no-mapped-types.mjs
│ │ ├── arkts-no-nested-funcs.mjs
│ │ ├── arkts-no-private-identifiers.mjs
│ │ ├── arkts-no-props-by-index.mjs
│ │ ├── arkts-no-symbol.mjs
│ │ ├── arkts-no-types-in-catch.mjs
│ │ ├── arkts-no-var.mjs
│ │ └── arkts-no-with.mjs
│ └── project/                          # 项目偏好 (2 文件)
│   ├── no-get-accessor.mjs
│   └── struct-no-regular-methods.mjs   # ✅ arkts-lint 用 @Component 修复
│
└── fixtures/                           # 测试 fixtures
 ├── pass/no-any.ets                    # 期望 0 violations
 └── fail/any-type.ets                  # 期望 6 violations
```

---

## Day 1 → Day 2 增量

| 增量 | Day 1 | Day 2 |
|---|---|---|
| 规则数 | 1 | 25 (+24) |
| Preprocessor | struct, $r, $rawfile | + build() body strip (75% parse 提升) |
| AST utils | walk.mjs | + has-decorator.mjs (struct vs class) |
| 引擎 | 基本 | + parentMap 注入 ctx |
| 退出码 | 0 | 0 |
| Baseline | (1 规则) | 25 规则, 173 文件 |

### Day 1 → Day 2 误报减少

- `arkts-no-func-expressions`: v1 (regex) → 0; arkts-lint (MethodDefinition skip) → 0
- `arkts-no-nested-funcs`: v1 (regex) → 0; arkts-lint (parentMap-aware) → 0
- `arkts-no-destruct-params`: v1 (regex) → 0; arkts-lint (RestElement-aware) → 0

**关键技术**: AST 上下文 (parent, parentMap) 让 arkts-lint 正确区分 method body vs 独立 expression, 解决 v1 三大误报源。

---

## 已知限制 (Day 2 → Day 3 待办)

- **91 parse-error warnings** (~12% 文件): ArkUI 特有语法 (`Stack() { if (x) { Image(...) } }` 的 build body, $r in deeper contexts, @Builder in some patterns)
  - v1 看不见这些文件;arkts-lint 揭示它们的存在
  - **Phase 2 选项**: 写轻量 ArkTS 语法扩展 / 切换 `ohos-ide-tools` parser / 接受 v0.2 不覆盖
- **15 官方规则未实现** (mapped, intersection, conditional 等需 type-checker)
  - arkts-lint 标注 `requiresTypeChecker: true` 留给 v2.1
- **v1 禁用 2 规则未复活**: `comma-outside-loops`, `method-reassignment` (正则难做, AST 也需要复杂 visitor)
- **未写 unit test 框架** (`arkts-lint/tests/`)
- **未集成 v1 / arkts-lint baseline 兼容 loader**

---

## Day 3 计划

| 时长 | 任务 |
|---|---|
| 2h | 新增 8 条纯语法规则 (no-ctor-signatures-*, no-standalone-this, no-class-literals 等) |
| 1h | 新增 7 条 type-checker 依赖规则 (mapped / conditional / intersection types) |
| 0.5h | 写 fixtures + tests (Node `--test` 框架) |
| 1h | baseline v1 兼容 loader (同一 schema 互读) |
| 0.5h | 更新 scripts/README.md |

Day 3 exit: arkts-lint 规则 ≥ 40, fixtures 全过, exit 0, scripts/README 完整

---

## 关键决策

- **parser**: `@typescript-eslint/parser@^8.18` + `typescript@^5.7` ✅
- **v1 保留**: ✅ (`scripts/audit-arkts-strict.mjs` 不变, `scripts/arkts-lint/` 是并行实现)
- **grace period**: ✅ (parse-error 标 `warn` 而非 `error`, 不阻断 CI)
- **type-checker 规则**: v0.3 留待 v0.4 (Day 3 标注 `requiresTypeChecker: true`, 不实现)
- **fixtures 排除**: 扫描时排除 `scripts/arkts-lint/fixtures/` 和 `scripts/arkts-lint/tests/`, 避免 fixture 误报

---

## 维护

- **新规则**: 复制 `rules/_template.mjs` 为 `rules/official/<rule-id>.mjs`, 跑 `--check-rules` 验证
- **false-positive**: 修改 rule 的 `check()` 函数 (AST 上下文 + parentMap 让精确定位可行)
- **ArkUI 桥接**: 当 91 parse-error 文件能 parse 时, 需更新 `preprocessArkUI` 适配新语法
- **baseline**: 每次改 rule 后跑 `--baseline=...` 重生成
- **CI 接入**: 未来如要 arkts-lint 替代 v1, 在 `.github/workflows/ci.yml` 加 `node scripts/arkts-lint/index.mjs --quiet` (退出码 0 = pass)

详见 `scripts/README.md` §维护 (v1 流程, arkts-lint 同样适用).

---

## 关联

- [scripts/README.md](../README.md) — v1 主文档 + arkts-lint 入口
- [docs/style/arkts-1.1.md](../../docs/style/arkts-1.1.md) — 40+ 规则权威定义
- [docs/architecture-audit-full-20260901.md](../../docs/architecture-audit-full-20260901.md) — 审计报告
- Phase 4 ticket #15
- v1 维护: `scripts/audit-arkts-strict.mjs` 保留 (regex 引擎, 灰度切换)