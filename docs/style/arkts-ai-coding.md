# ArkTS / ArkUI — AI Coding Checklist

> **用途**: agent 在写任何 `.ets` 之前的 60 秒预检清单。目标是减少“写完才被编译器打回”的往返，不是替代完整规则。
> **权威源**: [`arkts-1.1.md`](./arkts-1.1.md)（40+ 官方规则 + ArkUI 项目约束 + 验证命令）· [`file-header-template.md`](../agents/file-header-template.md) · `scripts/arkts-lint/`
> **适用**: MindTrace 的 5 个 module（`entry` / `common` / `agents` / `skill` / `cardservice`）；SDK 基线以 `build-profile.json5` 为准（当前 6.1.1 / API 24）。

---

## 0. 预检顺序

1. 读 [`CONTEXT.md`](../../CONTEXT.md) 的相关词条（尤其 `Dispatcher` / `KnowledgeUnit` / `StreamEvent` / `Reply Body`）。
2. 读本页；需要细节再查 [`arkts-1.1.md`](./arkts-1.1.md) 对应小节；需要机器可读的规则清单用 [`arkts-rules.json`](./arkts-rules.json)。
3. 新文件先套 [`file-header-template.md`](../agents/file-header-template.md) 的文件头。
4. 改完跑 `node scripts/agent-gate/index.mjs`；它会串起 lint / naming / link / doc-trace。
5. 交付时贴 gate 的 `RESULT: PASS`（或失败项）；没有 gate 输出的“完成”不算完成。

---

## 1. 最高频编译阻断（先扫这一张表）

| # | 规则 | ❌ 不要写 | ✅ 改成 |
|---|---|---|---|
| 1 | `arkts-no-any-unknown` | `function f(x: any)` / `let v: unknown` | 显式类型；catch 用 `(e as Error).message ?? String(e)` |
| 2 | `arkts-no-structural-typing` | 用形状兼容代替显式类型 | 先声明 `interface`，再 `const x: Foo = { ... }` |
| 3 | `arkts-no-untyped-obj-literals` | `const opt = { a: 1 }` | `const opt: Opt = { a: 1 }` |
| 4 | `arkts-no-destruct-decls` | `const { a, b } = obj` | `const a = obj.a; const b = obj.b` |
| 5 | `arkts-no-destruct-params` | `function f({ a, b }: Opt)` | `function f(opt: Opt)`，函数体内取字段 |
| 6 | `arkts-no-destruct-assignment` | `[a, b] = pair` | `a = pair[0]; b = pair[1]` |
| 7 | `arkts-no-var` | `var x = 1` | `let x: number = 1` / `const` |
| 8 | `arkts-no-func-expressions` | `arr.map(function (x) { ... })` | 箭头函数 `arr.map((x: T): U => ...)` |
| 9 | `arkts-no-nested-funcs` | 函数体内再 `function helper()` | 提到模块顶层，或 `const helper = (...) => ...` |
| 10 | `arkts-no-for-in` | `for (const k in obj)` | `for (const k of Object.keys(obj))` |
| 11 | `arkts-no-delete` | `delete obj.prop` | 重新构造对象，或把字段设为 `undefined`（类型允许时） |
| 12 | `arkts-no-type-query` / `arkts-no-is` | `typeof x` 当类型；`x is T` | 运行时 `typeof` 判断 + `x as T` |
| 13 | `arkts-as-casts` | `<T>x` | `x as T` |
| 14 | `arkts-no-types-in-catch` | `catch (e: Error)` | `catch (e)` 后 `(e as Error)` |
| 15 | `arkts-limited-throw` | `throw 'message'` | `throw new Error('message')` / `throw new LlmError(...)` |
| 16 | `arkts-no-props-by-index` | `obj['key']` | 显式字段，或 `Map<string, T>` |
| 17 | `arkts-no-standalone-this` | 把方法当函数传丢 `this` | 箭头函数字段捕获 `this` |
| 18 | `arkts-no-jsx` | JSX | `@Builder` / 组件组合 |
| 19 | `arkts-no-symbol` / `no-generators` / `no-with` | `Symbol()` / `function*` / `with` | 用 `string` key / 普通循环 / 重构 |
| 20 | `arkts-no-class-literals` / `no-call-signatures` / `no-indexed-signatures` | 类字面量 / 可调用接口 / `[k: T]: V` | 显式类 / 单方法接口 / `Map` |

> 完整 34 条 lint 规则与官方 error code 见 [`arkts-1.1.md`](./arkts-1.1.md) §官方 strict-mode 规则总表。lint 引擎的实现是 `scripts/arkts-lint/`，规则 ID 与本文一致。

---

## 2. ArkUI 硬约束（项目偏好，严格于官方）

### 2.1 struct 内禁普通方法

```ts
// ❌
@Component
struct Card {
  @State count: number = 0
  inc(): void { this.count++ }
}

// ✅ 箭头函数字段
@Component
struct Card {
  @State count: number = 0
  inc = (): void => { this.count++ }
}

// ✅ 或 @Builder（只用于 UI 片段）
@Component
struct Card {
  @Builder
  label() { Text('ok') }
}
```

### 2.2 struct 内禁 `get` accessor

```ts
// ❌
get count(): number { return this._count }

// ✅ 直接暴露 @State，或在构造时算好
@State count: number = 0
```

### 2.3 字段名避开 CommonAttribute 方法名

不要用 `rotate` / `translate` / `scale` / `opacity` / `backgroundColor` / `focusable` / `enabled` / `clickable` / `id` / `key` / `tag` / `geometry` 作字段名——会遮蔽链式属性。

```ts
// ✅
rotDeg: number = 0
transX: number = 0
scaleVal: number = 1
bgCol: string = '#fff'
```

### 2.4 装饰器与状态

- 默认用 **V1**：`@State` / `@Prop` / `@Link` / `@Provide` / `@Consume` / `@Watch` / `@Builder` / `@Observed` / `@ObjectLink`。
- **不要**在未做专项设计时引入 `@ComponentV2` / `@Local` / `@Param` / `@Event` 等 V2 装饰器（API 12+，项目仍以 V1 为主）。
- `@State` 只放**驱动 UI 的最小状态**；大对象、DAO、Service、LlmClient 实例不要塞进 `@State`。
- 父传子用 `@Prop`（单向）或 `@Link`（双向）；跨层用 `@Provide` / `@Consume`，不要层层透传。

### 2.5 build() 里不要做重活

`build()` 可能被频繁调用。不要在其中：

- 读文件 / 查数据库 / 发网络请求 / `await`
- 大循环、复杂排序、正则解析
- 创建 Web 组件或启动定时器

放到 `aboutToAppear()`、ViewModel 或 `TaskPool`；`build()` 只做纯投影。

### 2.6 长列表用 `LazyForEach`

- 超过一屏的列表：`List` + `LazyForEach` + `IDataSource`（参考 `SubjectNoteList`）。
- 小规模静态列表才用 `ForEach`。
- `LazyForEach` 的 key 必须稳定，不要用数组下标做业务 key。

---

## 3. 工程结构约束（比语法更容易翻车）

| 约束 | 说明 |
|---|---|
| **5 module** | `entry`（HAP）+ `common` / `agents` / `skill` / `cardservice`（HSP）；不要新建第 6 个模块 |
| **跨 module import 用完整路径** | `from 'common/src/main/ets/Index'`，不能 `from 'common/Index'` |
| **HSP 的 `oh-package.json5` 必须有 `main`** | 缺了会报 `Cannot find module` |
| **HSP `module.json5` 禁 `pages` / `abilities` / `mainElement` / `extensionAbilities` / `skills`** | 这些是 HAP 字段 |
| **一个应用只能有一个 `type:entry`** | 其他 HAP 用 `type:feature` |
| **`.ets` 必须是 UTF-8 无 BOM** | 用 `write_file` 创建；BOM 会让 hvigor 报“字节错位”伪错 |
| **新文件套文件头模板** | 文件名、路径、职责、依赖、数据流 |
| **不要新建已废弃目录** | `entry/src/main/ets/components/`、`entry/src/main/ets/atoms/`；`shared/atoms` / `shared/molecules` 才是现行 |
| **`mcp/` 不是待改名目录** | `OcrTool` 保留 MCP 语义；CRUD 工具放 `agents/src/main/ets/tools/`（ADR-0010） |

---

## 4. 验证命令（按顺序）

```bash
# 0. 一条命令跑总 gate（推荐；按改动集自动选检查项）
node scripts/agent-gate/index.mjs

# 1. ArkTS 规则扫描（0 errors；warning 逐条判断）
node scripts/arkts-lint/index.mjs --quiet

# 2. lint 引擎自身的 curated 测试（应全绿）
npm --prefix scripts/arkts-lint test

# 3. 全量测试（含既有失败基线，不要新增失败）
node --test scripts/arkts-lint/tests/*.test.mjs

# 4. 命名 / 链接守门
node scripts/naming-lint/index.mjs
node scripts/link-check/index.mjs

# 5. build（DevEco GUI 或 hvigor CLI）
#    Build Hap(s) / APP(s)
```

判读口径：

- `arkts-lint` 的 **error 必须为 0**；warning 先看是否为本文件新增。
- curated `npm test` **329/329** 是当前基线；全量 `node --test` 是 **707 项 / 15 项既有失败**。新增失败要修，不要用“本来就有失败”掩盖。
- build 失败先看第一条 `ArkTS` 报错，不要从最后一条开始猜。

---

## 5. 完成定义（DoD）

- [ ] `node scripts/agent-gate/index.mjs` → `RESULT: PASS`
- [ ] 没有引入 `any` / `unknown` / 解构 / `var` / `for...in` / `delete` / JSX
- [ ] struct 内没有普通方法、没有 `get` accessor、字段名不与 CommonAttribute 冲突
- [ ] `build()` 内没有 I/O、`await`、重计算
- [ ] 新文件有文件头；跨 module import 是完整路径
- [ ] `arkts-lint` 0 error；新增 warning 已解释或修掉
- [ ] `npm --prefix scripts/arkts-lint test` 全绿；全量测试无新增失败
- [ ] `naming-lint` / `link-check` 0 violation
- [ ] build 通过；失败时记录了第一条根因，不是只贴日志

---

## 6. 规则索引（查全文用）

| 主题 | [`arkts-1.1.md`](./arkts-1.1.md) 小节 |
|---|---|
| 类型系统（13 条） | §官方 strict-mode 规则总表 → 类型系统 |
| 控制流（8 条） | §控制流 |
| 变量与声明（5 条） | §变量与声明 |
| 类与对象（9 条） | §类与对象 |
| 模块与函数（5 条） | §模块与函数 |
| ArkUI 项目级 3 条 | §ArkUI 项目级约束（ArkUI-1/2/3） |
| 项目偏好（软约定） | §项目偏好 |
| API 版本矩阵 | §API 版本矩阵 |
| 验证命令与 grep 起点 | §验证命令 |
| 机器可读规则清单 | [`arkts-rules.json`](./arkts-rules.json)（由 `node scripts/arkts-lint/export-rules.mjs` 生成） |
| 多 module 工程规则 | §项目级额外规则 |

> 本页只做“写代码前的压缩记忆”；与 [`arkts-1.1.md`](./arkts-1.1.md) 冲突时，以全文和 lint 规则为准；与 ADR 冲突时，先停下来说明冲突，不要静默覆盖决策。
