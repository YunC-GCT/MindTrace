# PR0 — fix(common): normalizeModel 不再把 DEFAULT_MODEL 本身视为 reserved keyword

> **分支**:`bugfix/llm-config-audit-2026-09-06`(已存在)
> **Spec**:[016](../specs/016-llm-settings-redesign.md)
> **工作量**:1 行删除 + 1 个 RED 测试套件
> **风险**:极低
> **顺序**:第 1 个 PR(可独立先做,用户立即可用)

## 为什么

用户报告"哪怕输入现有默认厂商的密钥也无法正常的使用"(2026-09-06)。原假设 PRO_MODEL 名字错误,实测为 ticket #9 修复副作用。

### 真实根因(诊断结论)

`common/src/main/ets/llm/LlmConfig.ets:225-247` 的 `normalizeModel`:

```ts
private normalizeModel(v: string): string {
  const t: string = v.trim();
  if (t.length === 0) {
    return DEFAULT_MODEL;
  }
  const lower: string = t.toLowerCase();
  if (
    lower === DEFAULT_MODEL ||        // ← 这里!ticket #9 副作用
    lower.indexOf('v3') >= 0 ||
    lower.indexOf('flash') >= 0 ||
    lower.indexOf('deepseek-chat') >= 0 ||
    lower.indexOf('deepseek-reasoner') >= 0 ||
    lower.indexOf('r1') >= 0
  ) {
    throw new LlmError(
      `LlmConfig.normalizeModel: input "${v}" matches a reserved keyword; ` +
      `DEFAULT_MODEL is enforced. Reserved keywords: v3, flash, deepseek-chat, ` +
      `deepseek-reasoner, r1, and the DEFAULT_MODEL value itself.`,
      'NORMALIZE_KEYWORD_REJECTED'
    );
  }
  return t;
}
```

**ticket #9**(spec 009)修复了 keyword 静默覆盖 → 改为抛 `NORMALIZE_KEYWORD_REJECTED`,但**错误地把 `DEFAULT_MODEL` 本身也加进了 reserved 列表**。

### 触发链路

1. 用户在 AI 设置页选 DeepSeek 默认 + 填真实 key + 点 "测试连接"
2. ViewModel.test() 调用 `llm.saveAll(endpoint, resolveModel(), ...)`
3. `resolveModel()` 默认返回 `PRO_MODEL = "deepseek-v4-pro"`(来自 `AiSettingsViewModel.ets:7`)
4. `LlmConfig.DEFAULT_MODEL = "deepseek-v4-pro"`(来自 `LlmConfig.ets:18`)
5. `saveAll` → `normalizeModel("deepseek-v4-pro")` → 命中 `lower === DEFAULT_MODEL` → **抛 `NORMALIZE_KEYWORD_REJECTED`**
6. ViewModel.test() catch → 显示 "连接失败: NORMALIZE_KEYWORD_REJECTED..."
7. 用户看到"密钥无法使用",实际是**保存默认模型就被拒**(因为保存默认 = 用户保存的就是 `DEFAULT_MODEL`)

→ 用户**根本无法用默认厂商**调用 LLM,即使填了正确的 key。

## 修复

```diff
private normalizeModel(v: string): string {
  const t: string = v.trim();
  if (t.length === 0) {
    return DEFAULT_MODEL;
  }
  const lower: string = t.toLowerCase();
  if (
-   lower === DEFAULT_MODEL ||
    lower.indexOf('v3') >= 0 ||
    lower.indexOf('flash') >= 0 ||
    lower.indexOf('deepseek-chat') >= 0 ||
    lower.indexOf('deepseek-reasoner') >= 0 ||
    lower.indexOf('r1') >= 0
  ) {
    throw new LlmError(...);
  }
  return t;
}
```

**关键逻辑**:
- 空输入 → 默认值(已有)
- `DEFAULT_MODEL` 本身 → **允许**(用户保存的就是默认,不需要重新输入)
- 命中 v3/flash/deepseek-chat/deepseek-reasoner/r1 → 抛 `NORMALIZE_KEYWORD_REJECTED`(ticket #9 精神保留)

## 测试

新增 RED 测试:`scripts/arkts-lint/tests/llm-config-allow-default-model.test.mjs`

4 个测试用例:
1. `normalizeModel` 不再把 `DEFAULT_MODEL` 本身视为 reserved
2. ticket #9 的其他 keyword 守卫必须保留(v3/flash/deepseek-chat/deepseek-reasoner/r1)
3. `normalizeEndpoint` 不应有同样的 bug(`DEFAULT_ENDPOINT` 不抛)
4. 端到端:`PRO_MODEL`(`AiSettingsViewModel.ets`)必须等于 `LlmConfig.DEFAULT_MODEL`(否则 test() 流程会被 P0 bug 阻断)

## 验收

- [ ] 1 行删除(`lower === DEFAULT_MODEL ||`)
- [ ] `llm-config-allow-default-model.test.mjs` 4 个测试全绿
- [ ] 现有所有 arkts-lint 测试通过(回归):`llm-config-throw.test.mjs` / `llm-client-api.test.mjs` / 等
- [ ] 端到端冒烟:用户填 DeepSeek 真实 key + 选默认厂商 → 测试连接 → 返回 "已配置 / 连接正常"

## 回滚

`git revert` 即可。1 行删除,无副作用(无数据迁移)。

## 相关

- [spec 009](../specs/009-llm-config-throw-on-silent-override.md) — ticket #9 原始修复精神
- [scope §附录 D](../llm-settings-scope-2026-09-06.md) — 真实根因诊断详细报告
- [spec 016](../specs/016-llm-settings-redesign.md) — 主 spec(本 ticket 是 spec 016 的一部分)

## 最后更新

2026-09-06