# MathMind 模型切换架构

> 对应需求 v3.1 §F16（11 子需求）：内置模型切换 + 用户自定义模型 + 降级链排序  
> 当前状态：T3 LlmTool 内部有降级链，但**用户不可见、不可切换、不可管理**

---

## 一、缺口分析

| 需求 | v3.1 描述 | 当前有无 | 缺口 |
|------|----------|---------|------|
| F16.1 | 3 内置模型选择 UI | ❌ | T3 内部硬编码降级链，无 UI |
| F16.2 | 默认 DeepSeek（硅基流动） | ✅ | T3 默认首选 SiliconFlow/DeepSeek-V3 |
| F16.3 | 用户偏好持久化 | ⚠️ | UserPrefAgent 有 modelConfig 字段，但**尚未实现读写** |
| F16.4 | 切换即刻生效 | ❌ | 无切换入口 |
| F16.5 | 降级链自定义排序 | ❌ | 降级链固定在代码里 |
| F16.6 | 模型能力查询 UI | ❌ | Provider 有接口但未暴露 |
| F16.7 | 成本显示 | ❌ | T3 无调用计数 |
| **F16.8** | **用户添加自定义模型** | ⚠️ | OpenAICompatProvider 已建，但**用户无法配置** |
| **F16.9** | **用户管理模型（启用/禁用/删除）** | ❌ | |
| **F16.10** | **降级链拖拽排序** | ❌ | |
| **F16.11** | **连接测试** | ⚠️ | ILLMProvider 有 `testConnection()` 接口，但**从未调用** |

---

## 二、需要的改动

```
用户操作                     代码层                        数据层
─────────                  ─────────                     ────────
ModelSettingsPage ──→ SettingsViewModel ──→ UserPrefAgent.set()
   │                       │                       │
   │ 点击"测试连接"         │ call testConnection()   │
   │ 切换默认模型           │ set defaultProvider     │ → RDB user_prefs.modelConfig
   │ 添加自定义API          │ add provider            │
   │ 拖拽降级链             │ set degradationOrder    │
   │                       │                       │
   ▼                       ▼                       ▼
下次 LLM 调用 ────→ T3 LlmTool.readUserConfig() ─→ 读 modelConfig
                          │
                          ├ 按 degradationOrder 排序 providers
                          ├ 按启用状态过滤（disabled 跳过）
                          └ 按序尝试：①→超时→②→超时→③
```

## 三、数据流

```
┌─────────────────────────────────────────────────────────────┐
│ ModelSettingsPage（F3.8）                                    │
│                                                              │
│  当前默认: ● 小艺 Kit                                        │
│  ── 内置模型 ──                                              │
│  ○ 小艺 Kit（系统免费）         [默认]                        │
│  ● 硅基流动 DeepSeek-V3        API Key: sk-xxx [测试连接] ✅ │
│  ○ 盘古（已禁用）              [启用]                         │
│  ── 自定义模型 ──                                            │
│  ● 我的 DeepSeek    Endpoint: api.ds.com  [测试连接] [删除]  │
│  [+ 添加自定义模型]                                          │
│  ── 降级链顺序 ──                                            │
│  ☰ ① 硅基流动 DeepSeek                                      │
│  ☰ ② 小艺 Kit                                               │
│  ☰ ③ 我的 DeepSeek                                          │
│  [保存顺序]                                                  │
└──────────────────┬──────────────────────────────────────────┘
                   │ 保存时调用
                   ▼
┌──────────────────────────────────────────────────────────────┐
│ UserPrefAgent.set(userId, {                                   │
│   modelConfig: {                                              │
│     defaultProvider: "siliconflow",                          │
│     degradationOrder: ["siliconflow","xiaoyi_kit","my_ds"],  │
│     providers: {                                              │
│       "xiaoyi_kit":    { type:"builtin", enabled:true  },     │
│       "siliconflow":   { type:"builtin", enabled:true,        │
│                          apiKey:"sk-xxx" },                  │
│       "pangu":         { type:"builtin", enabled:false },     │
│       "my_ds":         { type:"custom",  enabled:true,        │
│                          endpoint:"https://api.ds.com/v1",   │
│                          modelName:"deepseek-chat",          │
│                          apiKey:"sk-yyy" }                   │
│     }                                                         │
│   }                                                           │
│ })                                                            │
└──────────────────┬──────────────────────────────────────────┘
                   │ 下次 LLM 调用时
                   ▼
┌──────────────────────────────────────────────────────────────┐
│ T3 LlmTool.chat(prompt)                                       │
│                                                               │
│ 1. config = UserPrefAgent.get(userId).modelConfig            │
│ 2. enabledProviders = config.providers.filter(p => p.enabled)│
│ 3. 按 config.degradationOrder 排序                            │
│ 4. 按序尝试每个 Provider:                                     │
│    for provider in order:                                     │
│      try { return provider.chat(prompt, 5s) }                │
│      catch { continue }                                      │
│ 5. 全部失败 → RDB 兜底 → Mock                                │
└──────────────────────────────────────────────────────────────┘
```

## 四、需要改的文件

| 文件 | 改动 | 工作量 |
|------|------|--------|
| `UserPrefAgent.ets` | 补全 ModelConfig 读写（9字段→含 modelConfig 完整Schema） | 小 |
| `LlmTool.ets` | 改为从 UserPrefAgent 读配置、动态排序 Provider | 中 |
| `SettingsViewModel.ets` | **新建** · 模型CRUD + 测试连接 + 降级链排序逻辑 | 中 |
| `ModelSettingsPage.ets` | **新建** · 模型管理 UI（参考 F3.8 布局） | 大 |
| `ARCHITECTURE.md` | 补充模型切换章节 | 小 |

---

## 五、MVP 初赛实现建议

初赛（7-26 前）只需保障：
1. **F16.2 默认 小艺Kit** ✅ 已实现
2. **F16.5 硬编码降级链** ✅ 已实现（小艺→DeepSeek→RDB→Mock）
3. **F16.3 偏好存储** → UserPrefAgent 补 modelConfig 字段即可（1h）

F16.8-F16.11（自定义模型/拖拽排序/测试连接）延至 S1 复赛。

---

*关联: v3.1 需求 F16 · T3 LlmTool.ets · UserPrefAgent.ets*
