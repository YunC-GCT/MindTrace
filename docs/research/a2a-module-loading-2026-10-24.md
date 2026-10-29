# 从 HSP 导入「含类型导出的模块」为何在模块加载期 SyntaxError

> 调研日期：2026-10-24 · 目标工程：`D:/HMgent/MindTrace`（Stage 模型 / targetSdk 26 / compatibleSdk 6.1.1(24)）
> 设备：MRO-W00，API 26（`param get const.ohos.apiversion` → 26）
> 来源优先级：本机 SDK 源码与构建产物 > OpenHarmony 源码/文档仓库 > 推断（显式标注）

---

## 0. 结论摘要

| 问题 | 结论 | 关键依据 |
|---|---|---|
| `export type` / `import type` 在 .ets 里能用吗？ | **能编译**（本工程有 21 处在用且正常运行），但**官方 ArkTS 迁移指南把 `import type` 列为禁止写法**（规则 `arkts-no-special-imports`），属"能跑但不保证"的灰区 | 实测 + `arkts-more-cases.md` §arkts-no-special-imports |
| 类型导出会在运行时存在吗？ | **不存在**。type-only 导入/导出在生成 abc 时被完全擦除，不进运行时导出表 | 语义 + 本工程 21 处 `import type ... from 'common'` 指向纯类型名仍正常 |
| 被当值导入会怎样？ | 若某个编译路径没擦除（典型：.ts 路径下 loader 会把 `import type` 降级为普通 `import`），运行期**链接阶段**抛 `ErrorType::SYNTAX_ERROR`，消息 `the requested module '<record>' does not provide an export name '<name>' which imported by '<importer>'`，**早于任何模块体执行** | `arkcompiler_ets_runtime/ecmascript/module/js_module_source_text.cpp:836-846` |
| 本次崩溃的真实成因 | **不是类型语法**。`common` HSP 的编译产物停留在 2026-10-23 11:50，**根本不含 `OnDeviceLlm` 这条 module record**；而 01:26 的提交让 HAP 侧 `import { OnDeviceLlm } from 'common'` → 链接期找不到导出 → SyntaxError → 扩展进程在 `onCreate` 前就被 appspawn 回收 | 见 §1 证据 3/4/5，§6 判定 |
| 为什么去掉 `@ohos.file.fs` 没用 | 因为崩溃与 `OnDeviceLlm.ets` 的**内容无关**：这个文件从未被编译进 HSP，改它不会改变任何产物 | 同上 |
| HSP 的 barrel 有代价吗？ | 有。`import { X } from 'common'` 编译成**一条** `@normalized:.../Index&` 记录请求，加载时按 ESM 语义实例化并求值 Index 的**全部** re-export 依赖图 | `entry.pa` 实测 + 运行时代码 |
| AgentExtensionAbility 能用 HSP / filesDir 吗 | 能。HSP 是 bundle 级动态共享包，"与宿主应用同进程"，与是否 UI 进程无关；`AgentExtensionContext` 继承 `ExtensionContext`→`Context`，有 `filesDir` | `in-app-hsp.md`、`js-apis-inner-application-context.md` |

**一句话**：这次不是"类型导入不被 ArkTS 支持"，而是**跨包链接时目标 HSP 里没有那个运行时导出**。类型语法只是让这个错误更隐蔽——它让"本该存在的导出"在源码层看起来天然存在。

---

## 1. 现场取证（本机一手证据，全部可复现）

| # | 证据 | 观察结果 | 出处 |
|---|---|---|---|
| 1 | 归一化模块请求 | HAP 里 `from 'common'` 被编译成 **一条** `@normalized:N&common&&common/src/main/ets/Index&` | `entry/build/default/intermediates/loader/default/loader.json` → `hspNameOhmMap`；反汇编 `entry/.../ets/modules.abc` 见 `MODULE_REQUEST_ARRAY: { 0 : @normalized:N&common&&common/src/main/ets/Index& }` |
| 2 | HAP 内部相对导入同样走 `@normalized:` | `@normalized:N&&&entry/src/main/ets/services/ReplyService&`（moduleName/bundleName 为空段） | 同上 |
| 3 | **HSP 产物里没有 `OnDeviceLlm`** | 反汇编 `common/.../ets/modules.abc` 得到 53 个 record，`llm.*` 下只有 `CancellationToken / LlmClient / LlmConfig / LlmErrorBodyFormatter / LlmGuard / LlmOutputRules / LlmResponseParser / LlmTypes / providers`，**无 `llm.OnDeviceLlm`**；全文件 `grep -c OnDevice` = **0** | `ark_disasm.exe --quiet common/.../modules.abc common.pa`，`.record &common.src.main.ets.llm.*&` 列表 |
| 4 | HSP 编译产物时间戳远早于源码 | `common/.../loader_out/default/ets/modules.abc`、`sourceMaps.map`、`loader.json` 全部 = **2026-10-23 11:50**；`OnDeviceLlm.ets` = 10-24 01:52；`Index.ets` = 10-24 01:20 | `ls --time-style=full-iso`；整个 `common/build` 下无 10-24 的编译输出（仅 23 个 config/generated 元数据文件） |
| 5 | 构建系统把 common 判为 up-to-date | 01:55 的构建里 `common:default@PreBuild/GenerateMetadata/MergeProfile/...` 全部 `up-to-date`，且日志中**从未出现** `common:default@CompileArkTS` | `.hvigor/outputs/build-logs/build.log`（2026-10-24T01:55） |
| 6 | 设备上的包就是这次 01:55 安装的 | `bm dump` → `updateTime: 1792778136468` = **2026-10-24 01:55:36** | `hdc shell bm dump -n com.example.mindtrace` |
| 7 | 当前磁盘上的 HAP 是"回退后"的产物 | `entry.pa` 里 `grep -c OnDevice` = **0**（说明 01:55 那次编的是已回退的源码） | `ark_disasm` of `entry/.../modules.abc` |
| 8 | 普通 shell 读不到 faultlog | `ls /data/log/faultlog/faultlogger` → `Permission denied`（`uid=2000(shell)`，即使带 `1007(log)` 组） | `hdc shell` 实测 |
| 9 | 类型导入在工程里是常态且可用 | `entry/src/main/ets` 中 `import type { ... } from 'common'` 共 **21 处**，全部指向 `Index.ets` 只用 `export type` 暴露的类型（如 `ReminderFacade`、`NoteGenerationRoute`、`StreamEvent`），App 正常启动 | `grep -rn "import type" ... \| grep "from 'common'"` |
| 10 | **扩展进程本身能加载 HSP** | 现场 `ps -ef` 显示 `com.example.mindtrace:agent`（PID 56767，02:30:26 启动）**正在运行**，而该版本 `AgentExtAbility.ets` 里 `import { LlmConfig } from 'common'` 照常工作 | `hdc shell ps -ef \| grep mindtrace` |

**时间线**（`git log`）：

```
10-23 11:50  common HSP 最后一次编译（产物时间戳）
10-24 01:20  common/src/main/ets/Index.ets 修改
10-24 01:26  bb18bfc feat(llm): route on-device first and mark degradation explicitly
10-24 01:52  common/src/main/ets/llm/OnDeviceLlm.ets 最后修改
10-24 01:55  构建 + 安装（bm dump updateTime 01:55:36）——此时 HSP 仍是 10-23 产物
10-24 01:57  1dcc4b7 fix(a2a): keep the extension dependency-light and raise the reply timeout（回退）
```

---

## 2. Q1：ArkTS/ArkCompiler 对 ESM 的支持边界

### 2.1 `export type` / `import type` 的实际可用性

- **编译器接受**。`common/src/main/ets/Index.ets` 里有大量 `export type { ... } from './models/...'`，而 `common` 在 10-23 成功编译出 `modules.abc`（证据 3/4）。同样，`entry` 里 21 处 `import type { ... } from 'common'` 编译通过且运行正常（证据 9）。
- **.ets 不是 es2abc 直接吃的后缀**。本机 es2abc 的 `--extension` 只接受 `js | ts | as | abc`：
  `C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/bin/ark/build-win/bin/es2abc.exe --help`
  即 `.ets` 先由 ets-loader 转换，再按 **TypeScript 语义**编译。这解释了为什么 type-only 的擦除行为与 TS 一致。

### 2.2 官方立场：`import type` 是**明令不建议**的写法

OpenHarmony 文档仓库 `zh-cn/application-dev/quick-start/arkts-more-cases.md` §`arkts-no-special-imports`（约 2249–2264 行）：

```
## arkts-no-special-imports
改为使用普通import { ... } from '...' 导入类型。
**应用代码**
import type {A, B, C, D } from '***'
**建议改法**
import {A, B, C, D } from '***'
```

同仓库 `introduction-to-arkts.md:2462-2465` 只对注解（annotation）额外强调"由于注解不是类型，因此禁止使用 `type` 符号进行导入和导出"，反过来说明**普通类型**用 `import type` 在语法层面是被识别的。

> 结论：`import type` / `export type` 在 API 26 的 .ets 里**语法可用、语义按 TS 擦除**，但 ArkTS 官方迁移指南把它归入「特殊导入」，要求写成普通 `import`。工程里能用，是因为 ArkTS linter 的该条规则在当前配置下未作为 error 拦截（本工程 `code-linter.json5` 只启用了 `@performance/recommended` 与 `@typescript-eslint/recommended`，没有 ArkTS 语法规则集）。
> **未找到一手来源**说明"`export type` 有独立的 ArkTS 规则名"；`arkts-no-special-imports` 的示例只覆盖 `import type`。

### 2.3 type-only 与运行时的关系：三个不同的报错阶段

| 阶段 | 发生什么 | 报什么 |
|---|---|---|
| **ArkTS linter（编译期）** | 命中 `arkts-no-special-imports` | lint 诊断（error/warn 取决于规则集）；本工程未启用 → 静默通过 |
| **loader/AST 变换（编译期）** | 关键风险点：`.ts` 编译路径会调用 `ts.getTypeExportImportAndConstEnumTransformer`，它的作用就是**把 `import type` 降级成普通 `import`**（因为目标模块格式不认 type 修饰符） | 不报错。但产物里就留下了一条真实的、指向"运行时不存在"的导入 |
| **模块链接（运行期，实例化阶段）** | ECMAScript 规范 15.2.1.17.4 `InitializeEnvironment`：`ResolveExport` 返回 null/ambiguous | `SyntaxError`（见 §5.1 源码）——**这是本工程 exit 254 + `Reason:SyntaxError` 的唯一对得上的阶段** |

第一处源码位置：`SDK/openharmony/ets/build-tools/ets-loader/lib/process_kit_import.js`（压缩后单行），原句：

```js
ts.visitEachChild(ts.getTypeExportImportAndConstEnumTransformer(a)(e), p, a)
```

同一文件里对 `isTypeOnly` 的判断（`needSkipTypeSymbolOfNode`）也证明 loader 是"知道"type-only 的——但它只在 `processTs` 分支做降级处理，`.ets` 分支保留原样交给 es2abc 擦除。也就是说：**同一个工程里，`.ts` 与 `.ets` 对 `import type` 的处理路径不同**，这是最容易产生"源码看着是类型导入、产物里却是值导入"的地方。

### 2.4 正确写法（针对跨包）

```ts
// ✅ 值导入：只导入运行时真实存在的绑定
import { LlmConfig, OnDeviceLlm } from 'common';

// ✅ 类型：ArkTS 官方推荐写法（不是 import type）
import { OnDeviceAvailability } from 'common';

// ⚠️ 能编译但官方不推荐；且一旦被降级为值导入就是运行期 SyntaxError
import type { OnDeviceAvailability } from 'common';
```

若某类型在包里**只有 `export type`**（如 `Index.ets:227` 的 `OnDeviceAvailability`、`OnDeviceReply`），跨包建议**在本模块内重新声明该结构**或**把它改为值层可见的 `class`/`enum`**，不要让消费方去 import 一个运行时并不存在的名字。

---

## 3. Q2：HSP 跨包导入的运行时解析规则

### 3.1 编译期：`from 'common'` 只产生一条记录请求

`loader.json` 的 `hspNameOhmMap`：

```json
"hspNameOhmMap": {
  "common": "@normalized:N&common&&common/src/main/ets/Index&",
  "agents": "@normalized:N&agents&&agents/src/main/ets/Index&"
}
```

生成规则来自 SDK：`ets-loader/lib/ark_utils.js`

```js
// getNormalizedOhmUrlByAliasName()
`@normalized:${a.isSO ? "Y" : "N"}&${a.moduleName}&${a.bundleName}&${n}&` + a.version
// getNormalizedOhmUrlByFilepath()
i = a.bundleName + `&${o}/${t}&` + a.version;              // record 名
return n ? i : `${a.isSO?"Y":"N"}&${l||a.moduleName}&` + i; // ohmurl
```

字段含义：`Y|N`（是否 .so）/ `moduleName` / `bundleName` / `<pkgName>/<path>` / `version`。本工程 bundleName 与 version 为空，故 `&&` 双空段。

**要点**：无论你从 `common` 里 import 多少个符号，`module_request` 永远只有 **`.../Index&` 这一条**（证据 1）。逐符号的 `local_name/import_name` 都在这一条记录的导入表里。

### 3.2 运行期：从归一化 URL 到 HSP 的 abc

`arkcompiler_ets_runtime/ecmascript/module/module_path_helper.cpp:386-408`：

```cpp
CString ModulePathHelper::ParseNormalizedOhmUrl(JSThread *thread, CString &baseFileName, const CString &recordName,
    CString requestName)
{
    ASSERT(StringHelper::StringStartWith(requestName, PREFIX_NORMALIZED_NOT_SO)); // "@normalized:N"
    CVector<CString> res = SplitNormalizedOhmurl(requestName);
    if (res.size() != NORMALIZED_OHMURL_ARGS_NUM) { THROW_MODULE_NOT_FOUND_ERROR_WITH_RETURN_VALUE(...); }
    const CString& moduleName = res[NORMALIZED_MODULE_NAME_INDEX];
    const CString& bundleName = res[NORMALIZED_BUNDLE_NAME_INDEX];
    if (!bundleName.empty() && !moduleName.empty()) {
        baseFileName = ConcatHspFileNameCrossBundle(bundleName, moduleName);
    } else if (!moduleName.empty()) {
        baseFileName = ConcatHspFileName(moduleName);          // ← 本工程走这里
    } else if (baseFileName.empty()) { ... }
    const CString& importPath = res[NORMALIZED_IMPORT_PATH_INDEX];
    const CString& version    = res[NORMALIZED_VERSION_INDEX];
    return ConcatUnifiedOhmUrl(bundleName, importPath, version);  // ← 目标 record 名
}
```

配套定义（`module_path_helper.h:86-89, 105, 139-142`）：

```cpp
PREFIX_NORMALIZED              = "@normalized:"
PREFIX_NORMALIZED_SO           = "@normalized:Y"
PREFIX_NORMALIZED_NOT_SO       = "@normalized:N"
PREFIX_NORMALIZED_NOT_CROSS_HAP_FILE = "@normalized:N&&&"
MERGE_ABC_ETS_MODULES          = "/ets/modules.abc"
NORMALIZED_OHMURL_ARGS_NUM = 5;  MODULE_NAME=1; IMPORT_PATH=3;
```

以及 `module_path_helper.cpp:201-236`：

```cpp
// Unified ohmUrl used be cached: [<bundle name>?]&<pkg name + /src/main + path>&[<version>?]
CString ModulePathHelper::ConcatUnifiedOhmUrl(...)
CString ModulePathHelper::ConcatHspFileName(const CString &moduleName)
{ return base::ConcatToCString(BUNDLE_INSTALL_PATH, moduleName, MERGE_ABC_ETS_MODULES); }
```

**解析链**：`@normalized:N&common&&common/src/main/ets/Index&`
→ 拆 5 段 → `baseFileName = /data/storage/el1/bundle/common/ets/modules.abc` → 目标 record = `&common/src/main/ets/Index&`。

即：**整个 HSP 的 abc 文件作为一个单位被加载**（不是按需只取一个文件），然后在这个 abc 里定位 record。若 record 不存在 → `THROW_MODULE_NOT_FOUND_ERROR`；若 record 存在但**导出表里没有你要的名字** → §5.1 的 SyntaxError。

> 说明：本机反汇编里 record 显示为点分形式（`&common.src.main.ets.Index&`），而归一化请求是斜杠形式。两者能对上说明运行期存在归一化名 → record 名的兼容映射（同一份 entry 产物内部相对导入也是这个组合，且 App 正常运行）。**未逐行定位该映射函数**，属推断，但不影响本文结论。

### 3.3 barrel（Index.ets 统一 re-export）会把整棵依赖图求值——是的

- 编译期：`export { X } from './m'` 生成的是 **indirect export entry** + 一条模块依赖；`export * ` 生成 `StarExportEntry`。运行时的模块记录结构里这四类表是分开的：
  `js_module_source_text.h:163-170`（`AddImportEntry / AddLocalExportEntry / AddIndirectExportEntry / AddStarExportEntry`）。
- 运行期：ESM 的实例化与求值都是**沿依赖图递归**的。因此 `import { 任意一个符号 } from 'common'` 会：
  1. 加载 `common/ets/modules.abc`；
  2. 实例化 `Index` 及其**全部** re-export 目标（`ColorTokens`、`MockNotes`、`NoteTaxonomy`、`NoteGenerationModels`、`logger`、`LlmConfig`、`LlmClient`、`ApiKeyVault`、`DatabaseHelper`、`ToolRegistry`、`StateGraph`、`ContentProtocol`、`CardSnapshotStore` …）；
  3. 求值它们（顶层代码执行）。

  证据：`common` 的 abc 里确实包含上述**每一个文件**的 record（`common.pa` 的 53 个 `.record`），说明它们全在同一个依赖闭包里。

- **这就是"扩展进程很脆"的结构性原因**：只要 Index 的依赖图里任何一个模块在扩展进程里求值失败（缺 NAPI、缺 UI 运行时、抛异常），整个 `common` 导入就失败。但注意：那种情况报的是 `Error/TypeError/ReferenceError`，**不是 SyntaxError**——本次现场是 SyntaxError，所以问题不在求值，在链接（§5.1）。

### 3.4 `useNormalizedOHMUrl` 的作用

- 官方要求（`zh-cn/application-dev/quick-start/integrated-hsp.md:24`）：
  > 使用集成态HSP要求使用标准化的OHMUrl格式。需要在工程级的 build-profile.json5 文件中，将 strictMode 下的 `useNormalizedOHMUrl` 字段设置为 true。
- 本工程已开启：`build-profile.json5` → `app.products[0].buildOption.strictMode.useNormalizedOHMUrl: true`，构建日志中每个 session 都有 `useNormalizedOHMUrl: true`（`build.log`）。
- 影响：
  1. **导入写法从"包内物理路径"变为"带 bundle/module/version 的稳定标识"**，HSP 被多 HAP/HSP 复用时不会因为路径差异解析到不同副本（这正是集成态 HSP 的前提）。
  2. 未开启时，跨包引用可能落回 `@bundle:` / 物理路径形式，一旦模块被多份拷贝（HAP 与 HSP 各自打一份），会出现**两份单例**（`LlmConfig.getInstance()` 拿到不同实例）——这是比崩溃更难查的问题。
  3. ⚠️ **它不会替你重建 HSP**。归一化只改"怎么找"，不改"包里有没有"。本次事故正是"找得到包、包里没这个导出"。

### 3.5 HSP 的依赖约束（会影响你怎么拆包）

`in-app-hsp.md`：
- 第 9 行：HSP 是动态共享包，**与宿主应用同进程、同包名、同生命周期**，不能独立上架。
- 第 31 行：HSP 可以依赖其他 HAR/HSP，也可以被 HAP/HSP 依赖，但**不支持循环依赖，也不支持依赖传递**（A→B→C 时 A 不能直接用 C）。
- 第 29/30 行：API 18 起 HSP 可在配置里声明 ExtensionAbility（但不能有入口能力）。

---

## 4. Q3：AgentExtensionAbility 进程的限制

### 4.1 组件模型（一手文档）

`zh-cn/application-dev/reference/apis-ability-kit/js-apis-app-agent-agentExtensionAbility.md`：

- 继承自 `ExtensionAbility`，提供 `onCreate / onConnect / onDisconnect / onDestroy / onData / onAuth`。
- **"本模块接口仅可在 Stage 模型下使用"**。
- **"本模块接口不支持在 har 包中使用"**（即：实现 AgentExtensionAbility 的代码不能放在 HAR 里——这条直接影响"该不该把 Agent 侧代码抽到 HAR"的决策）。
- 首批接口 API 24 起（本工程 target 26，可用）。

`zh-cn/application-dev/application-models/agent-extension-ability.md`：注册方式 `"type": "agent"` + `metadata: ohos.extension.agent → $profile:agent_config`，与工程 `entry/src/main/module.json5` 一致。

### 4.2 进程

- `module.json5` 的 `extensionAbilities[].process` 可指定进程名，但文档明确：**仅 PC/2in1 与 Tablet 生效，API 14 起**（`module-configuration-file.md:325`），并指向"进程模型定义 · 静态指定进程"。
- 本工程 `AgentExtAbility` **没有配 `process` 字段**，但现场 hilog 显示进程名为 `com.example.mindtrace:agent`、由 `appspawn` 拉起。
  → **推断**：`:agent` 进程由 AgentRuntime/系统侧按扩展类型分配，不是应用配置出来的。未找到一手文档说明该命名规则，标注为推断。

### 4.3 能否加载 HSP

- 能。HSP 的加载单位是**应用（bundle）**，不是进程；`in-app-hsp.md:9` 明确"HSP 与宿主应用同进程，具有相同的包名和生命周期"，第 22 行"运行时按需加载"。
- **本机实测（2026-10-24 02:30）**：`ps -ef` 显示 `com.example.mindtrace:agent`（PID 56767）正在运行，而当前代码里 `AgentExtAbility.ets` 就是 `import { LlmConfig } from 'common'`。→ **扩展进程加载 HSP 完全没问题**，出问题的是"包里有没有那个导出"。
- 注意：HSP 的 `Index.ets` 若 re-export 了 UI 强相关模块，扩展进程会连带求值它们（§3.3）。当前之所以没炸，是因为这些模块的顶层代码不依赖 UI 运行时；这是"侥幸成立"，不是"有约束保证"。

### 4.4 是否有独立沙箱 filesDir

- 有。`AgentExtensionContext` 继承 `ExtensionContext`（`js-apis-inner-application-agentExtensionContext.md:10`），`ExtensionContext`→`Context`；`Context` 的 `filesDir` 字段见 `js-apis-inner-application-context.md:51`（"文件目录，详情参考应用沙箱目录"）。
- 同一应用的所有进程共享**同一个应用沙箱**（el2/base/<bundle>），所以 `filesDir` 路径与 UI 进程一致——这也是 `ModelRouter(filesDir, ...)` 这种构造在扩展进程里能复用的原因。

### 4.5 能否使用 NAPI 系统模块

- 没有一手文档说"扩展进程禁止 NAPI"。相反：扩展进程本来就要加载 `@kit.AgentFrameworkKit`（`createA2AServer`），这已经是 NAPI 形态的 Kit。
- 但**具体能力受 SELinux/进程类型与 Kit 白名单约束**，不同 Kit 可能要求 UI 进程或特定权限。**未找到一手来源**给出"AgentExtensionAbility 进程可用的 Kit 清单"，此处不做结论。
- 已知的一条硬约束来自文档：该类型**不能放在 HAR 包**里（§4.1）。

### 4.6 与 UI 进程的差异（汇总）

| 维度 | UI 进程（entry） | `:agent` 扩展进程 | 依据 |
|---|---|---|---|
| ArkUI / 页面 | 有 | 无（无 `loadContent`、无 UI 上下文） | 扩展模型定义，`agent-extension-ability.md` |
| HSP | 可加载 | 可加载（同一 bundle） | `in-app-hsp.md:9` |
| filesDir / 沙箱 | 同一沙箱 | 同一沙箱 | `context.md:51` |
| 生命周期 | UIAbility | ExtensionAbility（onCreate/onConnect/onData…） | `js-apis-app-agent-agentExtensionAbility.md` |
| 崩溃可见性 | 有窗口、易发现 | **静默**：进程被 appspawn 回收，只留 hilog/faultlog | 现场 + `jscrash.md` |
| 模块加载代价 | 已经付过一次（UI 启动） | **从零再付一次**：Index 全图求值 | §3.3 |

---

## 5. Q4：这类「模块加载期 SyntaxError」的报错语义与取证

### 5.1 语义（一手源码）

`openharmony/arkcompiler_ets_runtime` · `ecmascript/module/js_module_source_text.cpp:830-847`：

```cpp
// i. Let resolution be ? importedModule.ResolveExport(in.[[ImportName]], « »).
ResolvedMultiMap resolvedMap;
JSHandle<JSTaggedValue> resolution =
    SourceTextModule::ResolveExport(thread, importedModule, importName, resolvedMap);
RETURN_IF_ABRUPT_COMPLETION(thread);
// ii. If resolution is null or "ambiguous", throw a SyntaxError exception.
if (resolution->IsNull() || resolution->IsString()) {
    CString requestMod = ModulePathHelper::ReformatPath(GetModuleName(importedModule.GetTaggedValue()));
    CString msg = "the requested module '" + requestMod + GetResolveErrorReason(resolution) +
        ConvertToString(thread, importName.GetTaggedValue());
    if (!module->GetEcmaModuleRecordNameString().empty()) {
        CString recordStr = ModulePathHelper::ReformatPath(module->GetEcmaModuleRecordNameString());
        msg += "' which imported by '" + recordStr + "'";
    } else {
        msg += "' which imported by '" + module->GetEcmaModuleFilenameString() + "'";
    }
    THROW_ERROR(thread, ErrorType::SYNTAX_ERROR, msg.c_str());
}
```

`js_module_source_text.h:196-201`：

```cpp
inline static CString GetResolveErrorReason(const JSHandle<JSTaggedValue> &resolution)
{
    ASSERT(resolution->IsNull() || resolution->IsString());
    return resolution->IsNull() ? "' does not provide an export name '"
                                : "' provide an ambiguous export name '";
}
```

**要点**：

1. 这是 `InitializeEnvironment`（规范 15.2.1.17.4）里的动作，属于**链接/实例化阶段**，**早于模块体求值**。
   → 这就是"`onCreate` 首行 hilog 一条都不打印"的根本原因：类定义都还没执行到，方法更不会进。
2. 错误类型被**硬编码为 `ErrorType::SYNTAX_ERROR`**，与"源码有语法错误"无关。任何"导入了一个不存在的导出"都会长成 SyntaxError。
3. 完整消息形如：
   ```
   the requested module '@normalized:N&common&&common/src/main/ets/Index&'
   does not provide an export name 'OnDeviceLlm'
   which imported by '&entry.src.main.ets.services.ModelRouter&'
   ```
   （record 名由 `ReformatPath` 处理，实际日志里通常是点分形式。）
4. SDK 侧同一句话的旁证（构建期警告，`ets-loader/lib/fast_build/ark_compiler/bytecode_obfuscator.js` · `createWarnings()`）：
   > `The requested module 'xxxx' does not provide an export name 'x' which is imported by 'xxxxx'.`
   —— 官方在"字节码混淆可能导致导出名不一致"的警告里用的就是这条运行时错误原文，说明它在鸿蒙生态里就是"导出对不上"的通用症状。

### 5.2 faultlog 的路径、命名与权限

`zh-cn/application-dev/dfx/jscrash-guidelines.md`：

- 第 22 行：崩溃日志由 Hiview 生成，存放在 **`/data/log/faultlog/faultlogger`**。
- 第 38 行：DevEco Studio 会把该目录下的日志收集到 **FaultLog** 面板，按进程名/故障/时间分类。
- 第 44-50 行（方式三，需打开开发者选项）：
  ```text
  hdc file recv /data/log/faultlog/faultlogger 本地路径
  ```
  文件名格式：**`jscrash-进程名-进程UID-毫秒级时间.log`**。
- 第 2 种方式：`HiAppEvent` 订阅崩溃事件，用 `external_log` 字段直接读日志内容（`hiappevent-watcher-crash-events.md`）。

**本机实测的权限事实**（重要，避免浪费时间）：

```
$ hdc shell id
uid=2000(shell) gid=2000(shell) groups=...,1007(log),...
$ hdc shell ls /data/log/faultlog/faultlogger
ls: /data/log/faultlog/faultlogger/: Permission denied
```

→ 走 `hdc file recv` 需要开发者选项/更高权限；日常最快的是 **DevEco Studio → FaultLog 面板**（按进程名筛 `:agent`），或 `HiAppEvent` 订阅。

### 5.3 hilog 过滤

`zh-cn/application-dev/dfx/hilog.md`：
- 第 30 行：`hdc shell hilog` 在线查看。
- 参数（75-77 行）：`-L/--level`（D/I/W/E/F）、`-D/--domain`、`-T/--tag`。

针对本类问题（日志在进程起来之前就打完了，要"抓历史"而不是"等它再崩"）：

```bash
# 抓模块加载/进程拉起相关（appspawn 的 exit code、faultlogger 的 Reason）
hdc shell hilog -x | grep -Ei "appspawn|Faultlogger|Reason:|SyntaxError"

# 只看某个 tag（本工程扩展用 MindTraceA2A）
hdc shell hilog -T MindTraceA2A

# 只看错误级
hdc shell hilog -L E
```

> 注：`hilog` 的环形缓冲区会滚动，崩溃后要尽快抓；进程还没执行到 `hilog.info` 时，只能靠 `appspawn`/`Faultlogger_Base` 这两类系统日志定位到"哪个进程、什么 Reason"。

### 5.4 拿到真正的 JS 栈

崩溃日志（jscrash-*.log）里的 `Stacktrace` 段是源码级栈，但**模块链接错误往往没有业务栈**（错误发生在任何函数调用之前），此时日志里的 `Error message` 字段就是 §5.1 那句话——**它已经直接告诉你是哪个 record、哪个导出名**。这比栈更有用。

行号映射：`jscrash.md` 的堆栈格式说明（约 247-303 行）给出 `at <方法名> (<模块名|依赖模块名|版本号>:<行>:<列>)`，release 包需用 `sourceMaps.map` 反解；本工程 debug 构建直接在 `entry/build/default/intermediates/loader_out/default/ets/sourceMaps.map`。

---

## 6. 对本工程的判定与修复

### 6.1 判定

四条现场事实用同一个机制即可全部解释，且与产物证据吻合：

1. `common` HSP 的编译产物停在 **10-23 11:50**，其中**没有 `OnDeviceLlm` 这条 record**（证据 3/4/5）；
2. 01:26 的提交让 HAP 侧 `import { LlmConfig, OnDeviceLlm } from 'common'`，编译成 `@normalized:.../Index&` 的一条导入，导入表里含 `OnDeviceLlm`；
3. 运行期链接 Index 的导出表 → 找不到 `OnDeviceLlm` → `ErrorType::SYNTAX_ERROR`（§5.1）→ 发生在 `onCreate` 之前 → 扩展进程被 appspawn 回收（exit 254），UI 进程同理直接起不来；
4. 去掉 `OnDeviceLlm.ets` 里的 `@ohos.file.fs` 不改变任何产物（该文件根本没进 HSP），所以"改了还是崩"——**症状与文件内容无关**。

即：**根因是 HSP 未随源码重建（增量构建/安装链路复用旧 HSP），而不是 ArkTS 不支持 `export type` / `import type`。**

### 6.2 立即验证（不改业务代码，10 分钟）

```bash
# 本仓库根目录没有 hvigorw wrapper（只有 hvigor/hvigor-config.json5），用 DevEco 自带的：
HV="/c/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw"

# 1) 彻底重建（清掉 common 的增量缓存），确认产物时间戳变新
"$HV" clean --no-daemon
"$HV" assembleHap --mode module -p product=default --no-daemon
ls -l --time-style=full-iso common/build/default/intermediates/loader_out/default/ets/modules.abc
#    期望：时间戳 = 现在

# 2) 确认 OnDeviceLlm 进了 HSP（ark_disasm 是原生程序，路径要给 C:/ 形式，不能用 /tmp）
AD="/c/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/ark_disasm.exe"
PA="C:/Users/$USERNAME/AppData/Local/Temp/common.pa"
"$AD" --quiet common/build/default/intermediates/loader_out/default/ets/modules.abc "$PA"
grep -c "OnDeviceLlm" "$PA"      # 期望 >= 1

# 3) 重装后复跑，若仍崩，读 faultlog 的 Error message 看它说的导出名是什么
```

如果重建后仍崩，且日志里的导出名**不是** `OnDeviceLlm`，再按 §5.1 的消息逐字比对——那就是另一条缺失导出。

### 6.3 结构性建议

1. **HSP 重建纪律**：任何对 `common` 源码（含 `Index.ets` 增删导出）的改动，必须确认 `common:default@CompileArkTS` 真的执行、且 `modules.abc` 时间戳更新后再安装。把这条写进构建脚本/CI（`scripts/` 下已有 lint 脚本，可加一条产物时间戳断言）。
2. **别让 barrel 成为唯一入口**：`Index.ets` 现在 re-export 了 40+ 模块，`import` 任意符号都会拉起全图求值（§3.3）。扩展进程这类"轻进程"应只依赖**拆小的子入口**（如 `common/llm/OnDeviceLlm` 这类子路径，编译期 `getOhmUrlByExternalPackage` 支持 `pkg/xxx` 前缀匹配），而不是整个 `Index`。
3. **类型不要跨包"只存在于类型层"**：`OnDeviceAvailability` / `OnDeviceReply` 这类纯接口，消费方要么本地重声明，要么改成 `class`/`enum`（运行时可见），避免"源码有、产物没有"的认知错位。
4. **写普通 import**：按 `arkts-no-special-imports`，把 `import type { X } from 'common'` 统一改成 `import { X } from 'common'`（值层不存在时编译器/打包器会立刻暴露，而不是留到运行期链接）。
5. **构建产物自检**：在 `scripts/` 加一个"期望导出清单"检查（反汇编 `modules.abc` 后断言关键 record/符号存在），把这类问题拦在安装前。

---

## 7. 未确证 / 推断清单

| 项 | 状态 |
|---|---|
| `:agent` 进程名由系统/AgentRuntime 分配（应用未配 `process`） | **推断**。依据：`module.json5` 无 `process` 字段 + 现场进程名 `:agent` + `process` 字段文档限定 PC/2in1/Tablet。未找到一手文档描述命名规则。 |
| AgentExtensionAbility 进程可用的 Kit/NAPI 清单 | **未找到一手来源**。仅能确认该组件不能在 HAR 中实现（API 文档）。 |
| 归一化 OHM URL → 点分 record 名的具体映射函数 | **未逐行定位**。已确认两端格式（`@normalized:N&common&&common/src/main/ets/Index&` vs `&common.src.main.ets.Index&`）以及同产物内相对导入同样走归一化且运行正常，故映射存在；具体实现未读到。 |
| `export type` 是否有独立 ArkTS linter 规则名 | **未找到**。`arkts-no-special-imports` 的官方示例只覆盖 `import type`。 |
| hvigor 为何把改动过的 `common` 判为 up-to-date | **未确证**。可观测事实：`common:default@CompileArkTS` 在日志中完全缺席、`common/build` 下无 10-24 编译输出。属增量缓存未失效，具体触发条件需 clean 后对照复现。 |
| 崩溃当次 HAP 的 abc | 已被 01:55 的回退构建覆盖（`entry.pa` 中 `OnDevice` 计数为 0），无法直接反查当时 HAP 的导入表。判定依赖 HSP 产物 + 运行时错误语义。 |

---

## 8. 来源清单

### 本机 SDK（`C:/Program Files/Huawei/DevEco Studio/sdk/default`）

| 路径 | 用途 |
|---|---|
| `openharmony/ets/build-tools/ets-loader/lib/ark_utils.js` | `getNormalizedOhmUrlByFilepath` / `getNormalizedOhmUrlByAliasName`：归一化 OHMUrl 与 record 名的生成规则（`@normalized:Y|N&module&bundle&pkg/path&version`） |
| `openharmony/ets/build-tools/ets-loader/lib/process_kit_import.js` | `ts.getTypeExportImportAndConstEnumTransformer`：`.ts` 路径把 `import type` 降级为普通 import；`needSkipTypeSymbolOfNode` 的 `isTypeOnly` 判定 |
| `openharmony/ets/build-tools/ets-loader/lib/import_path_expand.js` | loader 对 `importClause.isTypeOnly` 的处理分支 |
| `openharmony/ets/build-tools/ets-loader/lib/fast_build/ark_compiler/bytecode_obfuscator.js` | `createWarnings()` 中的运行时错误原文 `does not provide an export name` |
| `openharmony/ets/build-tools/ets-loader/bin/ark/build-win/bin/es2abc.exe --help` | `--extension` 仅 `js|ts|as|abc`（.ets 先经 loader 转换） |
| `openharmony/toolchains/ark_disasm.exe` | 反汇编 `modules.abc` 核对 record / module_request |

### OpenHarmony 源码（GitHub `openharmony/arkcompiler_ets_runtime`）

| 位置 | 内容 |
|---|---|
| `ecmascript/module/js_module_source_text.cpp:830-847` | `ResolveExport` 失败 → `THROW_ERROR(thread, ErrorType::SYNTAX_ERROR, ...)`（链接期） |
| `ecmascript/module/js_module_source_text.h:196-201` | `GetResolveErrorReason()`：`does not provide an export name` / `provide an ambiguous export name` |
| `ecmascript/module/js_module_source_text.h:163-170` | `AddImportEntry/AddLocalExportEntry/AddIndirectExportEntry/AddStarExportEntry`（re-export 的运行时结构） |
| `ecmascript/module/module_path_helper.cpp:386-408` | `ParseNormalizedOhmUrl`：`@normalized:N&module&bundle&pkg/path&version` → HSP abc + record |
| `ecmascript/module/module_path_helper.cpp:201-236` | `ConcatUnifiedOhmUrl`（注释给出 unified ohmurl 格式）、`ConcatHspFileName(module) = BUNDLE_INSTALL_PATH + module + /ets/modules.abc` |
| `ecmascript/module/module_path_helper.h:86-89,105,139-142` | `@normalized:` / `@normalized:N` / `/ets/modules.abc` / 分段索引常量 |

### OpenHarmony 文档（GitHub `openharmony/docs`，`zh-cn/application-dev/`）

| 文件 | 引用点 |
|---|---|
| `quick-start/arkts-more-cases.md` §`arkts-no-special-imports`（约 2249-2264） | 官方要求用普通 `import { ... }` 导入类型 |
| `quick-start/introduction-to-arkts.md:2462-2465` | 注解禁止用 `type` 符号导入导出（反证普通类型可用） |
| `quick-start/in-app-hsp.md:9,22,29-31` | HSP 与宿主同进程/同包名/同生命周期；按需加载；无循环依赖、无依赖传递；API 18 起可声明 ExtensionAbility |
| `quick-start/integrated-hsp.md:24,30,49` | 集成态 HSP 要求 `strictMode.useNormalizedOHMUrl: true` |
| `quick-start/module-configuration-file.md:131,325,502` | `process` 字段语义与生效范围（PC/2in1、Tablet，API 14+） |
| `dfx/jscrash-guidelines.md:22,38,44-50,247-303` | faultlog 路径 `/data/log/faultlog/faultlogger`、文件名 `jscrash-进程名-进程UID-毫秒时间.log`、`hdc file recv`、HiAppEvent、栈格式 |
| `dfx/hilog.md:30,75-77` | `hdc shell hilog`、`-L/-D/-T` 过滤 |
| `reference/apis-ability-kit/js-apis-app-agent-agentExtensionAbility.md` | AgentExtensionAbility 仅 Stage、不支持 HAR、API 24 起 |
| `application-models/agent-extension-ability.md` | `type: "agent"` + `ohos.extension.agent` 注册方式 |
| `reference/apis-ability-kit/js-apis-inner-application-agentExtensionContext.md:10` | 继承 `ExtensionContext` |
| `reference/apis-ability-kit/js-apis-inner-application-context.md:51` | `filesDir` |

### 本仓库构建产物 / 现场

| 路径 | 用途 |
|---|---|
| `entry/build/default/intermediates/loader/default/loader.json` | `hspNameOhmMap` → `@normalized:N&common&&common/src/main/ets/Index&` |
| `entry/build/default/intermediates/loader_out/default/ets/modules.abc` | 反汇编得全部 `module_request` 形态 |
| `common/build/default/intermediates/loader_out/default/ets/modules.abc` | 53 个 record，无 `OnDeviceLlm` |
| `.hvigor/outputs/build-logs/build.log` | `useNormalizedOHMUrl: true`；`common:default@*` 全部 up-to-date；`common:default@CompileArkTS` 缺席 |
| `hdc shell bm dump -n com.example.mindtrace` | `updateTime = 2026-10-24 01:55:36` |
| `hdc shell id` / `ls /data/log/faultlog/faultlogger` | `uid=2000(shell)`；`Permission denied` |
