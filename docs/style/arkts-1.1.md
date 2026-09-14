# ArkTS 1.1 Strict — Syntax Rules for MindTrace

> **目的**: 抽取自 [`docs/legacy/mindtrace/research/huawei-arkui-agent-20260901.md` §3](../legacy/mindtrace/research/huawei-arkui-agent-20260901.md#3-arkts-11-strict-mode-constraints),做成**可被任意 agent 直接加载**的语法规则手册。
> **使用方**: AGENTS.md 引用、Lint job (Phase 4 ticket #15) 用本文件生成 grep 模式、新 session 接 MindTrace 时**应加载本文件**再写代码。
> **生成日期**: 2026-09-01 (审计同步)
> **权威源**: <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-migration-background>

---

## ⚠️ Read this first — API 版本 caveat

| `compatibleSdkVersion` | ArkTS 1.1 strict 行为 | MindTrace 当前状态 |
|---|---|---|
| **< 10** | 规则只**警告**,不阻塞构建 | 历史状态 |
| **>= 10** | 规则**编译报错**,强制执行 | 当前项目以 `build-profile.json5` 配置和实际检查结果为准 |

**含义**: MindTrace 当前 API/SDK 基线由 `build-profile.json5`（当前 `6.1.1(24)`）和官方 SDK 文档决定，不再沿用“当前 API 9”的历史假设。无论编译器是否已把某条 strict 规则提升为错误，**Lint job 与 ArkTS check 必须强制**这些规则；使用系统 API 时不得引入高于已配置 SDK 或设备/模型约束不支持的能力。

---

## 官方 strict-mode 规则总表 (40+ 条)

下表按性质分组。**完整 rule ID + error code**, 出处 <https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-migration-background>。

### 类型系统 (Type system) — 13 条

| Rule ID | Error | 禁用 | 替代 |
|---|---|---|---|
| `arkts-no-any-unknown` | 10605008 | `any` 类型、`unknown` 类型 | 显式具体类型; catch 处用 `(e as Error).message ?? String(e)` |
| `arkts-no-structural-typing` | 10605030 | 结构兼容 (structural compatibility) | 显式接口定义 |
| `arkts-no-intersection-types` | 10605019 | `T & U` 交叉类型 | `extends` 继承 |
| `arkts-no-mapped-types` | 10605083 | mapped types | 显式字段声明 |
| `arkts-no-conditional-types` | 10605022 | conditional types (`T extends U ? X : Y`) | 重构为重载或分支 |
| `arkts-no-typing-with-this` | 10605021 | `this` 作为类型 | 用具体类名 |
| `arkts-no-is` | 10605096 | `arg is T` 类型谓词 | `instanceof` + `as` |
| `arkts-no-type-query` | 10605060 | `typeof x` 作为类型 | 用运行时检测 |
| `arkts-no-indexed-signatures` | 10605017 | `[k: T]: V` 索引签名 | 用 `Map<K, V>` |
| `arkts-no-untyped-obj-literals` | 10605038 | 无类型对象字面量 | 加显式 `: { ... }` 类型 |
| `arkts-no-obj-literals-as-types` | 10605040 | `{ a: T }` 当类型 | 用 `interface` |
| `arkts-no-noninferrable-arr-literals` | 10605043 | 不可推断数组字面量 | 加显式类型 |
| `arkts-no-inferred-generic-params` | 10605034 | 不可推断泛型参数 | 显式标注 |

**最常见的代码示例**:

```ts
// ❌ arkts-no-any-unknown
function f(x: any): void { ... }
// ✅
function f(x: Foo): void { ... }

// ❌ arkts-no-is
function isString(x: unknown): x is string { return typeof x === 'string' }
// ✅
function isString(x: Object): boolean {
  return typeof x === 'string'
}
if (isString(x)) {
  const s: string = x as string  // 显式 as
}

// ❌ arkts-no-intersection-types
type Both = A & B
// ✅
interface Both extends A, B {}
```

### 控制流 (Control flow) — 8 条

| Rule ID | Error | 禁用 | 替代 |
|---|---|---|---|
| `arkts-no-for-in` | 10605080 | `for (let k in obj)` | `for (const k of Object.keys(obj))` 或 `forEach` |
| `arkts-no-with` | 10605084 | `with` 语句 | 重构 |
| `arkts-no-comma-outside-loops` | 10605071 | `for` 外逗号运算符 | 分号 |
| `arkts-no-delete` | 10605059 | `delete obj.prop` | 设为 `undefined` 或从对象中过滤 |
| `arkts-as-casts` | 10605053 | `<T>x` 尖括号断言 | `x as T` |
| `arkts-no-polymorphic-unops` | 10605055 | `+` / `-` / `~` 对非数值 | 显式转换 |
| `arkts-no-instanceof-ref-types` | — | `instanceof` 对原始类型 | typeof 检查 |
| `arkts-no-in` | 10605066 | `key in obj` | `Object.keys().includes()` |

**最常见的代码示例**:

```ts
// ❌ arkts-no-for-in (BANNED)
for (const k in obj) {
  console.log(obj[k])
}
// ✅ arkts-no-for-in fix
for (const k of Object.keys(obj)) {
  console.log(obj[k])
}

// ❌ arkts-as-casts (BANNED)
const s = <string>x
// ✅
const s = x as string

// ❌ arkts-no-delete (BANNED)
delete obj.foo
// ✅
obj.foo = undefined
// 或:
const { foo, ...rest } = obj  // 但解构也禁,需手写
const next: typeof obj = {}
for (const k of Object.keys(obj)) {
  if (k !== 'foo') next[k] = obj[k]
}

// ❌ arkts-no-with (BANNED)
with (obj) { foo = bar }
// ✅
obj.foo = obj.bar
```

**重要更正**: C-style `for (let i = 0; i < n; i++)` 是**官方允许**的 (项目偏好 `for...of`/`forEach`/`while` 仅出于可读性)。

### 变量与声明 (Variables & declarations) — 5 条

| Rule ID | Error | 禁用 | 替代 |
|---|---|---|---|
| `arkts-no-var` | 10605005 | `var` | `let` |
| `arkts-no-private-identifiers` | 10605003 | `#privateField` 语法 | `private` 关键字 |
| `arkts-no-symbol` | 10605002 | `Symbol()` | 静态常量或 enum |
| `arkts-no-types-in-catch` | 10605079 | `catch (e: SomeType)` typed catch | `catch (e)` + `(e as Error).message ?? String(e)` |
| `arkts-no-implicit-return-types` | 10605090 | 递归调用隐式返回类型 | 显式标注 |

**最常见的代码示例**:

```ts
// ❌ arkts-no-var
var count = 0
// ✅
let count = 0

// ❌ arkts-no-private-identifiers
class Foo {
  #secret: string = '...'
}
// ✅
class Foo {
  private secret: string = '...'  // TypeScript 风格 private
}

// ❌ arkts-no-types-in-catch
try {
  riskyOp()
} catch (e: SomeError) {
  // ...
}
// ✅
try {
  riskyOp()
} catch (e) {  // e: unknown 通过 (e as Error).message ?? String(e) 兜底
  const msg = (e as Error).message ?? String(e)
}
```

### 类与对象 (Classes & objects) — 9 条

| Rule ID | Error | 禁用 | 替代 |
|---|---|---|---|
| `arkts-no-call-signatures` | 10605014 | 对象类型含 call signature | 显式函数类型 |
| `arkts-no-ctor-signatures-type` | 10605015 | type 含 `new()` 签名 | 用 class |
| `arkts-no-ctor-signatures-iface` | 10605027 | interface 含 `new()` 签名 | 用 abstract class |
| `arkts-no-ctor-prop-decls` | 10605025 | 构造函数参数中声明字段 | 显式类字段 |
| `arkts-no-multiple-static-blocks` | 10605016 | >1 静态 `{}` 块 | 合并 |
| `arkts-no-jsx` | 10605054 | JSX | ArkTS 不支持 (用 `@Builder`) |
| `arkts-no-class-literals` | 10605050 | class 表达式 | class 声明 |
| `arkts-no-func-expressions` | 10605046 | `function` 表达式 | 箭头 `=>` |
| `arkts-no-method-reassignment` | 10605052 | `obj.method = newFn` | 重新设计 |
| `arkts-implements-only-iface` | 10605051 | `class A implements ClassB` | 改为 `implements InterfaceB` |
| `arkts-no-props-by-index` | 10605029 | `obj['key']` 动态访问 | 预定义字段或 `Map.get()` |
| `arkts-identifiers-as-prop-names` | 10605001 | 数字/字符串属性键 | 用 `Map` |
| `arkts-no-standalone-this` | 10605093 | 自由函数 / static 中 `this` | 用具体类名 |

**最常见的代码示例**:

```ts
// ❌ arkts-no-call-signatures
type Callable = { (x: number): string }
// ✅
type Callable = (x: number) => string

// ❌ arkts-no-func-expressions
const f = function(x: number) { return x.toString() }
// ✅
const f = (x: number): string => x.toString()

// ❌ arkts-implements-only-iface (BANNED)
class Foo implements Bar {  // Bar 必须是 interface
}
// ✅
class Foo implements BarInterface {  // BarInterface = interface Bar {}
}

// ❌ arkts-no-ctor-prop-decls
class Foo {
  constructor(public name: string, private age: number) {}
}
// ✅
class Foo {
  private age: number
  constructor(name: string, age: number) {
    this.name = name
    this.age = age
  }
}

// ❌ arkts-no-props-by-index (BANNED)
const value = obj['key']
// ✅
const value = obj.key  // 预定义字段
// 或:
const m: Map<string, T> = new Map()
m.set('key', value)
const v = m.get('key')
```

### 模块与函数 (Modules & functions) — 5 条

| Rule ID | Error | 禁用 | 替代 |
|---|---|---|---|
| `arkts-no-nested-funcs` | 10605092 | 嵌套函数声明 | 顶层箭头 |
| `arkts-no-generators` | 10605094 | `function*` | async/await + Promise |
| `arkts-limited-throw` | 10605087 | `throw "msg"` 非 Error | `throw new Error("msg")` |
| `arkts-no-destruct-assignment` | 10605069 | `[a, b] = arr` 解构赋值 | 索引访问 |
| `arkts-no-destruct-decls` | 10605074 | `let { a, b } = obj` 解构声明 | 临时变量 |
| `arkts-no-destruct-params` | 10605091 | `function f({a, b})` 解构参数 | 显式命名参数 |

**最常见的代码示例**:

```ts
// ❌ arkts-no-destruct-assignment (BANNED)
const [a, b] = arr
// ✅
const a = arr[0]
const b = arr[1]

// ❌ arkts-no-destruct-decls (BANNED)
const { foo, bar } = obj
// ✅
const foo = obj.foo
const bar = obj.bar

// ❌ arkts-no-destruct-params (BANNED)
function process({ input, options }) { ... }
// ✅
function process(req: { input: T, options: U }) {
  const input = req.input
  const options = req.options
}

// ❌ arkts-no-nested-funcs
function outer() {
  function inner() { ... }  // BANNED
}
// ✅
const inner = (): void => { ... }
function outer() {
  inner()
}

// ❌ arkts-limited-throw
throw 'something went wrong'
// ✅
throw new Error('something went wrong')
```

---

## ArkUI 项目级约束 (项目偏好**严格于**官方)

这些不是 ArkTS strict 规则, 而是 MindTrace 项目**额外**约定的硬约束, **任何 .ets 文件必须遵守**:

### ArkUI-1 — struct 内禁普通方法

```ts
// ❌ 普通方法
@Component
struct MyComp {
  @State count: number = 0

  handleClick(): void {  // 普通方法
    this.count++
  }

  build() {
    Button('+').onClick(() => this.handleClick())
  }
}

// ✅ 箭头函数字段 或 @Builder
@Component
struct MyComp {
  @State count: number = 0

  handleClick = (): void => {
    this.count++
  }

  // 或:
  @Builder
  myBuilder() {
    Text('value')
  }

  build() {
    Button('+').onClick(this.handleClick)
  }
}
```

### ArkUI-2 — struct 内禁 `get` accessor

```ts
// ❌ get accessor
@Component
struct MyComp {
  @State private _count: number = 0
  get count(): number { return this._count }  // BANNED
}

// ✅ @State 直接暴露
@Component
struct MyComp {
  @State count: number = 0
}
```

### ArkUI-3 — struct 字段名避开 CommonAttribute 方法名

```ts
// ❌ 字段名与 ArkUI 通用属性同名 (会遮蔽链式调用)
@Component
struct MyComp {
  rotate: number = 0   // 遮蔽 .rotate({angle})
  translate: { x: number, y: number } = { x: 0, y: 0 }  // 遮蔽 .translate({x,y})
  scale: number = 1
  opacity: number = 1
  backgroundColor: string = '#fff'
}

// ✅ 用 rotDeg / transY / etc.
@Component
struct MyComp {
  rotDeg: number = 0
  transX: number = 0
  transY: number = 0
  scaleVal: number = 1
  opVal: number = 1
  bgCol: string = '#fff'
}
```

被遮蔽的方法名清单 (ArkUI 1.1):
- `rotate` / `translate` / `scale` / `opacity` / `backgroundColor` / `focusable` / `enabled` / `clickable` / `id` / `key` / `tag` / `geometry` 等

---

## 项目偏好 (软约定, 不阻塞构建)

以下**官方允许**但 MindTrace 项目偏好,仅出于代码一致性 / 可读性:

| 偏好 | 说明 |
|---|---|
| **`for...of` / `forEach` / `while` 优于 C-style `for`** | 官方允许 C-style `for`, 项目偏好更声明式 |
| **`.translate()` 优于 `.offset()` 用于响应式动画** | 两者都响应 `@State`, `.translate()` 参与 transformation chain |
| **手写 `JSON.stringify` 时只用 plain object/array 字面量** | 不传 class 实例 (避免方法丢失 + 循环引用) |
| **不用 `as const`** | 与 `arkts-no-props-by-index` 隐式冲突, 字面量失去推断类型 |
| **不用 object spread `{...obj, key: 1}`** | 同上, 隐式违反静态类型规则 |

---

## API 版本矩阵 (ArkUI 1.1, MindTrace 当前 SDK 以 build-profile.json5 为准)

| 特性 | API 版本 | MindTrace 当前可用 |
|---|---|---|
| `@State` / `@Prop` / `@Link` / `@Provide` / `@Consume` / `@Watch` / `@Builder` | 7+ | ✅ |
| `@Observed` / `@ObjectLink` | 7+ | ✅ |
| `.translate()` / `.offset()` / `.rotate()` / `.scale()` | 7+ | ✅ |
| `.stateStyles()` 基础态 (focused / pressed / normal / disabled / clicked) | 7 | ✅ |
| `.stateStyles().selected` | **10+** | 按当前 SDK/官方文档核对后使用 |
| `.blur()` / `.backgroundFilter()` / `.foregroundFilter()` / `.visualEffect()` | **12+** | 按当前 SDK/官方文档核对后使用 |
| `@kit.ArkTS.JSON` 模块 | **12+** | 优先沿用项目既有 JSON 策略；使用前核对 SDK |
| `@ComponentV2` / `@Local` / `@Param` / `@Once` / `@Event` / `@Provider` / `@Consumer` / `@Monitor` / `@ObservedV2` / `@Trace` / `@Computed` | **12+** | 本项目默认仍用 V1 (`@State`/`@Prop`/...); 迁移需专项设计 |
| `AgentExtensionAbility` | **24+** | 仅在当前 SDK/应用能力配置和官方文档允许时使用 |
| `@kit.NetworkKit.http.createHttp().requestInStream()` + SSE 手解析 | 7+ | ✅ 用作 LLM 流式 |
| `@kit.AbilityKit` | 7+ | ✅ |
| `@kit.CoreVisionKit` (OCR) | 9+ | ✅ |
| `@kit.ArkData.relationalStore` | 9+ | ✅ |
| `@kit.ArkData.preferences` | 9+ | ✅ |
| `@kit.ImageKit` | 9+ | ✅ |

**版本路径与当前基线**:
- **API 10**: ArkTS strict 强制; + `selected` 态; + 部分 V2 装饰器预演
- **API 12**: `@kit.ArkTS.JSON` 模块; + `@ComponentV2` V2 全套; + Filter / visualEffect
- **API 24（当前基线）**: `AgentExtensionAbility` (HarmonyOS NEXT 5.0+) — 官方智能体能力；是否使用仍取决于应用能力配置与官方文档

---

## 验证命令 (供 lint job 使用)

Phase 4 ticket #15 计划生成 `scripts/audit-arkts-strict.ts`, 用以下 grep 模式扫描代码:

```bash
# 类型系统
grep -rEn '\bany\b' --include='*.ets' .   # arkts-no-any-unknown (排除注释)
grep -rEn '\bunknown\b' --include='*.ets' .   # arkts-no-any-unknown
grep -rEn ':\s*<[A-Z][a-zA-Z0-9_]*>' --include='*.ets' .   # arkts-as-casts (<T>x)
grep -rEn '\bis\s+[A-Z]' --include='*.ets' .   # arkts-no-is (类型谓词)
grep -rEn '\s&\s' --include='*.ets' .   # arkts-no-intersection-types (类型位置)
grep -rEn 'typeof\s+\w+\s*[;,)>]' --include='*.ets' .   # arkts-no-type-query

# 控制流
grep -rEn 'for\s*\(\s*(let|const|var)\s+\w+\s+in\s+' --include='*.ets' .   # arkts-no-for-in
grep -rEn '\bwith\s*\(' --include='*.ets' .   # arkts-no-with
grep -rEn '\bdelete\s+\w+\.' --include='*.ets' .   # arkts-no-delete
grep -rEn ',$' --include='*.ets' .   # arkts-no-comma-outside-loops (粗扫,需手动排除 for)

# 变量声明
grep -rEn '\bvar\s+' --include='*.ets' .   # arkts-no-var
grep -rEn '#\w+\s*:' --include='*.ets' .   # arkts-no-private-identifiers (#field)
grep -rEn '\bcatch\s*\(\s*\w+\s*:' --include='*.ets' .   # arkts-no-types-in-catch
grep -rEn '\bSymbol\s*\(' --include='*.ets' .   # arkts-no-symbol

# 类与对象
grep -rEn 'class\s+\w+\s+implements\s+[A-Z]' --include='*.ets' .   # arkts-implements-only-iface (人工核对)
grep -rEn 'function\s+\w*\s*\(' --include='*.ets' .   # arkts-no-func-expressions (粗扫)
grep -rEn '\b\w+\[\s*['\''\"]' --include='*.ets' .   # arkts-no-props-by-index (粗扫)
grep -rEn 'function\s*\*' --include='*.ets' .   # arkts-no-generators

# 模块与函数
grep -rEn '\{[^}]*=\s*[^}]*\}' --include='*.ets' .   # 解构 (粗扫,误报多)
grep -rEn 'throw\s+["'\'']' --include='*.ets' .   # arkts-limited-throw (非 Error 字面量)
grep -rEn '^\s*function\s+\w+\s*\([^)]*\{[^}]*\}' --include='*.ets' .   # arkts-no-nested-funcs (粗扫)

# ArkUI 项目级
grep -rEn '^\s+(public|private|protected)?\s*\w+\s*\([^)]*\)\s*[:{]' --include='*.ets' entry/src/main/ets/  # ArkUI-1 普通方法 (粗扫)
grep -rEn '^\s+get\s+\w+\s*\(' --include='*.ets' entry/src/main/ets/  # ArkUI-2 get accessor
grep -rEn '^\s+(rotate|translate|opacity|scale|backgroundColor)\s*[:=]' --include='*.ets' entry/src/main/ets/  # ArkUI-3 字段名冲突
```

> **警告**: 上述 grep 模式**只是起点**, 多数含误报 (注释、字符串字面量、嵌套)。真正的 lint 应基于 tsserver / hvigor 的 AST 解析, 不靠 grep。**Phase 4 ticket #15** 计划接入 hvigor lint。

---

## 项目级额外规则 (MindTrace 特定, 不在 ArkTS strict)

这些是 MindTrace 多 module 工程的硬约束, **与 ArkTS 语法无关, 但 agent 必须知道**:

1. **HSP `oh-package.json5` 必备 `main` 字段**: 缺了 build 报 `Cannot find module 'xxx'`
   ```json5
   { "name": "agents", "main": "./src/main/ets/Index.ets" }
   ```
2. **`.ets` 文件 UTF-8 noBOM**: UTF-16 LE BOM 让 hvigorw 报 "18 字节错位" 伪错
3. **每个 module 都需自己的 `build-profile.json5` + `hvigorfile.ts`**: 根的不够
4. **HSP `module.json5` 字段约束**: 禁 `pages`/`abilities`/`mainElement`/`extensionAbilities`/`skills`, 可写 `name`/`type`/`description`/`deviceTypes`/`deliveryWithInstall`/`installationFree`
5. **HSP 跨 module import 必须完整路径**: `from 'common/src/main/ets/Index'` 不能 `from 'common/Index'`
6. **一个鸿蒙应用只能有一个 `type:entry` 模块**: 其他 HAP 用 `type:feature`
7. **obfuscation-rules.txt 必须存在**: 即使 `enable:false` 也要有文件
8. **新 .ets 文件必须用 Write 工具创建**: 避免 PowerShell 5.1/7 中文编码陷阱
9. **`agents/mcp/tools/` 是命名误导**: 项目未运行 MCP server (audit §4.8), 计划改名 `tools/`

---

## 出处 (Sources)

### 一手规则文档

- **[ArkTS 1.1 严格模式迁移背景](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-migration-background)** — 所有 40+ 规则的源头
- **[ArkTS 编码风格指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-coding-style-guide)** — 推荐风格
- **[ArkTS 入门](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-get-started)** — 类型推断基础
- **[@kit.ArkTS JSON 模块](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-json)** — JSON 序列化 (`@kit.ArkTS.JSON` 是 API 12+)

### ArkUI 装饰器

- **[arkts-state-management-overview](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state-management-overview)** — 全套装饰器索引
- **[arkts-state](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state)** / **[arkts-prop](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-prop)** / **[arkts-link](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-link)** / **[arkts-observed-and-objectlink](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-observed-and-objectlink)** / **[arkts-watch](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-watch)** / **[arkts-builder](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-builder)** / **[arkts-provide-and-consume](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-provide-and-consume)** / **[arkts-statestyles](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-statestyles)**
- **[arkts-transformation](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-transformation)** — rotate / translate / scale
- **[arkts-access-restrictions](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-access-restrictions)** — private / public (API 12+)

### HarmonyOS Stage / HAP / HSP

- **[Stage 模型开发概述](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/stage-model-development-overview)**
- **[UIAbility 生命周期](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/uiability-lifecycle)**
- **[HSP (in-app)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/in-app-hsp)** — `oh-package.json5.main` + 跨 module import
- **[HAP package](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hapap-package)** — 签名一致性
- **[Application models](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/application-models)** — Stage vs FA

### Agent / LLM / Streaming (确认 MindTrace 路径)

- **[HTTP 请求](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/http-request)** — `requestInStream` + SSE 手解析 (确认无 SSE SDK)
- **[AgentExtensionAbility](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/agent-extension-ability)** — API 24+ 的端侧智能体扩展能力；当前 SDK 已达到 API 24，但仍须按应用能力配置和官方文档核对后使用

---

## 维护

- **本文档更新触发**: ArkTS 官方规则表变更 / `build-profile.json5` 中 API/SDK 基线变更 / 项目偏好调整
- **当前 MindTrace 状态**: API/SDK 基线以 `build-profile.json5` 为准；这些规则由 lint job 与 ArkTS check 强制。
- **当前维护重点**: 以 `build-profile.json5` 的 `6.1.1(24)` 为基线，持续由 lint job 与 ArkTS check 强制这些规则；基线或官方规则变化时重新核对本文件。

**报告结束**。
