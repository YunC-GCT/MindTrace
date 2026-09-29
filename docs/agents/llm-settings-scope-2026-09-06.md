# LLM 设置页重构 — Scope 决策轨迹

> **日期**:2026-09-06
> **分支**:`bugfix/llm-config-audit-2026-09-06`(worktree `mt-llm-config-audit/`)
> **负责人**:主会话(grilling skill 主线程)
> **输入**:用户报告 + 调研后子

---

## 任务来源

用户在 `mt-llm-config-audit/` worktree 中报告 AI 设置页痛点(2026-09-06):

> "目前程序在 ai 设置页面这里,首先页面的设计不敬人意需要进行调整优化计划是默认的一些国内大模型可以填写相关的 key 即可使用,其它一些可以用户自定义...目前的自定义功能有问题现在哪怕输入现有默认厂商的密钥也无法正常的使用"

**用户额外约束**:
- OCR 测试保留,后续会去除完全融入程序内部,所以本次 UI 重构**不能让 OCR 与新 LLM 配置深度耦合**,方便后续剥离

---

## Grilling 16 个 Q 决策轨迹

### Round 1 — 大局决策

| Q | 题目 | 取值 | 备注 |
|---|---|---|---|
| Q1 | 重构范围 | **C 渐进式** | 只做 UI + 数据结构,留扩展点 |
| Q2 | 协议范围 | **A 仅 OpenAI 兼容** | 国内 5 家 100% 覆盖 |
| Q3 | 默认厂商 | **B 5 家** | DeepSeek / 通义 / GLM / Kimi / 豆包 |
| Q4 | 多 provider | **A 单激活** | LlmConfig 单 key 保持 |

### Round 2 — 落地细节

| Q | 题目 | 取值 | 备注 |
|---|---|---|---|
| Q5 | 凭据存储 | **B AssetStoreKit** | 调研强推,独立 PR1 |
| Q6 | P0 bug 路径 | **A 单独 PR** | 1 行字串,用户立即可用 |
| Q7 | 自定义字段 | **A 最小 4 字段** | vendor / baseUrl / model / apiKey |
| Q8 | 默认厂商交互 | **C A + 保留 model 自定义** | 锁定 baseUrl,可改 model |

### Round 3 — 风格 + 节奏 + OCR 约束

| Q | 题目 | 取值 | 备注 |
|---|---|---|---|
| Q9 | UI 风格 | **A 沿用** | dark + MINT + ColorTokens,无 rgba 字面量 |
| Q10 | 验收方式 | **A 单元 + 端到端** | 用户真跑一次 |
| Q11 | spec / ADR 路径 | **A 新 spec + 1-2 ADR** | spec 016 + ADR 0013 + 0014 |
| Q14 | PR 拆分 | **A 4 个独立 PR** | fix / AssetStoreKit / UI / docs |
| + | OCR 约束 | **保留可剥离** | 本次不改,后续 PR 剥离路径 |

### Round 4 — 数据 / 迁移 / 粒度

| Q | 题目 | 取值 | 备注 |
|---|---|---|---|
| Q12 | 默认厂商数据结构 | **A 硬编码常量** | `providers.ets`,与 MockNotes 一致 |
| Q13 | AssetStoreKit 迁移 | **C 兼容读取** | 优先 AssetStoreKit,fallback Preferences |
| Q15 | UI ticket 粒度 | **B 2 ticket** | T1 数据结构调整,T2 UI 重构 |

### Round 4.5 — Seam 范围(调研触发的真新决策)

| Q | 题目 | 取值 | 备注 |
|---|---|---|---|
| Q16 | spec 016 实施的 seam | **A 最小集** | 只做 #2 + #3;#1 / #4 / #5 留 Future work |

---

## 调研摘要

详见 [`docs/research/llm-provider-patterns-2026-09-06.md`](./research/llm-provider-patterns-2026-09-06.md)(493 行)。

**关键事实**:
- **Q5:B(AssetStoreKit)被调研强力背书**:TEE + AES256-GCM,正是 Token 类凭据
- **LlmClient 已对齐真 SSE 流式**(`requestInStream + on('dataReceive')`),spec 005 落地,本 spec 不动
- **`LlmCaller` interface 已在 LlmGuard.ets** — 已有 adapter 雏形,Q16:A 不再抽象
- **5 个 seam 候选**:Adapter 抽象 / 凭据 AssetStoreKit / factory + 预设表 / 配置 snapshot / Anthropic 协议;**本次只做 #2 + #3**,其他留 Future work

---

## 产出文件清单(本批次)

| 文件 | 类型 | 内容 |
|---|---|---|
| `docs/specs/016-llm-settings-redesign.md` | 主 spec | 背景 / 目标 / 非目标 / 涉及文件 / 公共接口 / 测试 / 验收 / 顺序 / 可逆性 / OCR 约束 |
| `docs/adr/0013-llm-provider-presets.md` | ADR | 5 厂商预设决策 + 候选方案(4 个)+ 影响 |
| `docs/adr/0014-asset-store-kit-migration.md` | ADR | AssetStoreKit 迁移决策 + 候选方案(4 个)+ 影响 |
| `docs/agents/tickets/llm-settings/pr0-fix-pro-model.md` | Ticket | PR0:1 行字串修复 |
| `docs/agents/tickets/llm-settings/pr1-asset-store-kit-upgrade.md` | Ticket | PR1:ApiKeyVault 新建 + LlmConfig 委托改造 |
| `docs/agents/tickets/llm-settings/pr2-t1-llm-config-data.md` | Ticket | PR2-T1:providers.ets + LlmConfig 新增 4 方法 |
| `docs/agents/tickets/llm-settings/pr2-t2-ui-redesign.md` | Ticket | PR2-T2:UI 重组 + ViewModel 清理 |
| `docs/agents/llm-settings-scope-2026-09-06.md`(本文) | 状态 | Q1-Q16 轨迹 + 调研摘要 + 文件清单 |

---

## 前沿状态(grilling skill "frontier empty" 检查)

✅ **Q1-Q16 全部 settled**,无未决子问题。grilling session 收尾,进入实施阶段。

---

## 下一步

1. 用户审阅 8 个产出文件(`docs/specs/016-llm-settings-redesign.md` 是主入口)
2. 确认无误后,按 **PR0 → PR1 → PR2-T1 → PR2-T2 → docs** 顺序实施
3. 每 PR 走 TDD:红绿切片 → 双轴 code-review → squash commit → **不 push**(红线 #1)
4. 端到端冒烟(Q10:A):你真跑一次,DeepSeek + 通义 + 自定义 三场景

---

## 附录 C:5 家厂商 2026-09 时点一手信源调研报告

> 用户反馈"防止选到其已经淘汰的" 后,本次重新做了一手信源调研,替代之前凭印象写的 PROVIDERS 列表。

### C.1 DeepSeek ✅ 一手信源

- **文档**:`https://api-docs.deepseek.com/`
- **baseUrl (OpenAI)**:`https://api.deepseek.com`
- **当前活跃模型**(2026-09):
  - `deepseek-v4-flash`(DeepSeek-V4-Flash-0731,经济型)
  - `deepseek-v4-pro`(DeepSeek-V4-Pro-0813,旗舰,**当前推荐**)
  - `deepseek-v4-flash-vision-exp`(实验,接受图像)
- **关键发现**:`deepseek-v4-pro` **是真实存在的当前推荐模型**!不是虚构。调用方式不变,使用 `deepseek-v4-pro` 字符串即可访问最新版本。

### C.2 通义千问 Qwen ✅ 一手信源

- **文档**:`https://help.aliyun.com/zh/model-studio/developer-reference/compatibility-of-openai-with-dashscope`
- **baseUrl**(OpenAI 兼容):
  - 北京:`https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`
  - 弗吉尼亚:`https://dashscope-us.aliyuncs.com/compatible-mode/v1`
  - 新加坡:`https://{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`
  - 日本(东京):`https://{WorkspaceId}.ap-northeast-1.maas.aliyuncs.com/compatible-mode/v1`
- **⚠️ 重要**:`{WorkspaceId}` 是用户业务空间 ID,需替换为实际值
- **当前顶级模型**(文档示例):`qwen3.8-max`(示例中展示;具体 `qwen3-max` / `qwen3.8-max` / `qwen3-max-preview` 等子型号待用户确认)
- **之前误写**:`qwen-plus` 已升级

### C.3 智谱 GLM ✅ 一手信源

- **文档**:`https://docs.bigmodel.cn/cn/guide/start/migrate-to-glm-new`
- **baseUrl**:`https://open.bigmodel.cn/api/paas/v4/`(推断,OpenAI 兼容路径)
- **当前活跃模型**(2026-09):
  - **GLM-5.3**(Hot,旗舰,1M 上下文 / 128K 输出,**当前推荐**)
  - **GLM-5.3-Flash**(New,经济型)
  - GLM-5.2(上一代)
- **之前误写**:`glm-4-plus` 是 4.x 全系已升级,现在 5.x
- **官方迁移 checklist**:明确要求 "更新模型编码为 `glm-5.3`"

### C.4 月之暗面 Kimi ✅ 一手信源

- **文档**:`https://platform.kimi.com`(替代原 `platform.moonshot.cn`,已重定向)
- **baseUrl**(从 cURL 示例):`https://api.moonshot.cn/v1`
- **当前活跃模型**(2026-09):
  - **K3**(旗舰,1M tokens,**能力最强**)
  - **K2.7 Code**(编程专用)
  - **K2.6**(通用,256k tokens,**稳定通用**)
- **之前误写**:`moonshot-v1-128k` 不是当前推荐!现在 K2.6 / K3 系列
- **选型建议**:用户在 PR2-T1 前确认 defaultModel 是 `kimi-k2.6`(稳定)还是 `kimi-k3`(最强)

### C.5 字节豆包 Doubao ✅ 一手信源

- **文档**:`https://www.volcengine.com/docs/82379` + `https://www.volcengine.com/article/38136`
- **baseUrl**:
  - 普通 API:`https://ark.cn-beijing.volces.com/api/v3`
  - Coding Plan 套餐:`https://ark.cn-beijing.volces.com/api/coding/v3`
- **当前活跃模型**(2026-09):
  - **Doubao-Seed-Code**(编程,推荐)
  - **doubao-seed-1.6**(Seed 1.6 系列)
  - doubao-seed-2.0-code(2.0)
- **之前误写**:`doubao-pro-128k` 已升级
- **注**:豆包在 Ark 平台也支持 DeepSeek-V4 系列和 GLM-5.1(转售)

### C.6 误判说明 — PRO_MODEL

之前 spec/ADR/tickets 中 `PRO_MODEL = "deepseek-v4-pro"` 被误认为"虚构名字",拟改成 `deepseek-chat`。**事实**:`deepseek-v4-pro` 是 DeepSeek 当前推荐的真实模型(详见 C.1)。

→ 原 PR0 修复方向错误。新 PR0 改为"诊断 P0 bug 真实根因"(详见 `tickets/llm-settings/pr0-fix-pro-model.md`)。

---

## 附录 D:P0 bug 真实根因诊断结论

### D.1 根因(已确认)

**`common/src/main/ets/llm/LlmConfig.ets:232`** 的 `normalizeModel`:

```ts
if (
  lower === DEFAULT_MODEL ||    // ← P0 bug: ticket #9 副作用
  lower.indexOf('v3') >= 0 ||
  ...
)
```

`lower === DEFAULT_MODEL` 这一行是 **ticket #9 修复的逻辑错误**。ticket #9 修复精神是"keyword 静默覆盖 → 抛错",但**错误地把 `DEFAULT_MODEL` 本身也加进 reserved 列表**。

### D.2 触发链路(已确认)

1. 用户在 AI 设置页选 DeepSeek 默认 + 填真实 key + 点 "测试连接"
2. `AiSettingsViewModel.test()` 调用 `llm.saveAll(endpoint, resolveModel(), ...)`(line 142-144)
3. `resolveModel()` 默认返回 `PRO_MODEL = "deepseek-v4-pro"`(`AiSettingsViewModel.ets:7`)
4. `LlmConfig.DEFAULT_MODEL = "deepseek-v4-pro"`(`LlmConfig.ets:18`)— 这就是 DeepSeek 当前推荐的真实模型
5. `saveAll` 内部 `normalizeModel("deepseek-v4-pro")` → 命中 `lower === DEFAULT_MODEL` → **抛 `NORMALIZE_KEYWORD_REJECTED`**
6. ViewModel.test() catch → 显示 "连接失败: NORMALIZE_KEYWORD_REJECTED..."
7. 用户看到"密钥无法使用",**实际是保存默认模型就被拒**(因为保存的就是 `DEFAULT_MODEL`)

→ 用户**根本无法用默认厂商**调用 LLM,即使填了正确的 key。

### D.3 候选根因排除(LlmClient 已确认无问题)

读 `LlmClient.ets` 后排除:

- **#1 URL 拼接错** — `resolveEndpointUrl` (line 205-221) 正确处理空 / 含 `/chat/completions` / 含 `/anthropic` 三种情况;默认 baseUrl 会自动补 `/chat/completions`。✅ 无问题
- **#2 Bearer header** — `LlmClient.ets:112` 显式 `'Authorization': \`Bearer ${apiKey}\``,有 `Bearer ` 前缀。✅ 无问题
- **#3 `getEndpoint()` 返回错** — `LlmConfig.ets:103` 直接返回 `cachedEndpoint`,默认 `'https://api.deepseek.com'`。✅ 无问题
- **#5 TLS** — 默认 baseUrl 走标准 HTTPS。✅ 无问题(待用户真机确认)
- **#6 OCR 干扰** — `AiSettingsViewModel.test()` 不调用任何 OCR 代码;`testOcr()` 是独立方法。✅ 无问题
- **#4 syncEndpoint 嗅探错** — 仍可能是潜在问题(ticket #9 精神的另一处违反),但**不是 P0 根因**。修复建议:放在 PR2-T2 里清理(ViewModel 字段结构调整一并做)。

### D.4 修复方案(已就绪)

**1 行删除**:`LlmConfig.ets:232` 的 `lower === DEFAULT_MODEL ||`。

完整诊断报告 + 测试代码详见 `docs/agents/tickets/llm-settings/pr0-fix-pro-model.md`。

### D.5 一手信源

- `LlmClient.ets` line 205-221 `resolveEndpointUrl` — URL 拼接逻辑
- `LlmClient.ets` line 112 — `Authorization: Bearer ${apiKey}`(有 Bearer 前缀)
- `LlmConfig.ets` line 17-18 — DEFAULT_ENDPOINT / DEFAULT_MODEL 常量
- `LlmConfig.ets` line 225-247 — normalizeModel 守卫
- `LlmConfig.ets` line 232 — P0 bug 行(`lower === DEFAULT_MODEL ||`)
- `AiSettingsViewModel.ets` line 7 — `PRO_MODEL = "deepseek-v4-pro"`
- `AiSettingsViewModel.ets` line 135-163 — test() 流程(saveAll → normalizeModel 抛错)
- [spec 009](../specs/009-llm-config-throw-on-silent-override.md) — ticket #9 原始修复精神

---

## 最后更新

2026-09-06