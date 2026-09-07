# 前端错误降级与边界摸底 — 2026-09-06

> **Date:** 2026-09-06 晚
> **Scope:** MindTrace entry 错误处理结构 + 降级路径 + 用户反馈
> **方法**: grep `try/catch` + `throw` + `console/hilog/Logger` + 错误字面量, 全机提取
> **配套**: [`frontend-interaction-states-2026-09-06.md`](./frontend-interaction-states-2026-09-06.md) 五态摸底 (本档是其 error 态深挖)

---

**TL;DR:** 错误处理"两极分化" — **99 处 catch, 18 处有结构化日志 (≈18%), 81 处直接吞 `_e`**; 错误分类**完全不存在**, 全是字符串 Toast 即丢即忘; 用户感知只有 Toast 一条路, 没有"重试"按钮、没有红色错误横幅、没有分级 (网络错 vs LLM 错 vs IO 错) 区分; **降级路径稀缺**: 仅 LlmClient `extractContent` 文本为空回退 `reasoning_content` 算有降级 (但可能把思维链当正文), 其余 catch 一律 Toast 离场。

---

## 1. 错误处理规模

| 指标 | 数值 | 备注 |
|---|---|---|
| `try { } catch` 出现处 | 99 | entry 模块 |
| 有结构化日志 (`console.error` / `hilog.error` / `Logger`) | 18 | ≈18% |
| 直接吞 `_e` (无日志) | ≈81 | 82% |
| 错误字面量 (中英文错误消息) | 15+ | 散落各页, 风格不一致 |
| Error 枚举 / 分类常量 | **0** | 无 |
| Retry 按钮 / 重试入口 | **0** | 用户失败后只能重做操作 |

---

## 2. 错误分类缺失 (按业务失败源)

### 2.1 网络失败
- LLM 调用失败 (api.deepseek.com) → LlmClient: throw 普通 Error / LlmError, 上层 Toast 提示
- OCR 服务失败 (127.0.0.1:8000) → OcrTool: throw + retry 2 次, 上层 Toast
- **没有任何"离线"判断**: 移动网络/Wi-Fi 切换无感知, 失败原因无法定位

### 2.2 LLM 错误
- API key 错 (401) / 限流 (429) / 服务端 (5xx) → 一律 Toast "Failed"
- **context too long / 输出截断** 未单独提示
- DeepSeek 思考模式失败 → reasoning_content 路径被 fallback 用, **可能把思维链当正文返回** (C2 已知坑)

### 2.3 OCR 错误
- 图片无法识别 (空文本 / 错误) → OcrTool throw "未获取到照片"
- **未告诉用户"为什么"**: 光线差 / 角度偏 / 公式太复杂 — 用户不知道是图的问题还是服务的问题

### 2.4 IO 错误
- NoteDao 写失败 (磁盘满 / 权限) → Toast "保存失败"
- imageUri 复制失败 (ImageUriResolver) → throw, 上层 Toast "图片准备失败"
- ChatSession preferences 写失败 → try/catch 包裹, 不影响 UI

### 2.5 服务不可用
- OCR 服务未启动 (port 8000 无响应) → OcrTool retry 后失败, Toast 含糊
- **没有"启动 OCR 服务"的引导**: 用户不知道有 `tools/ocr_service/start.bat`

---

## 3. 降级路径盘点

### 3.1 真有降级的 2 处

| 位置 | 降级行为 | 风险 |
|---|---|---|
| `common/.../llm/LlmClient.ets:180-184` extractContent | 文本空 → 回退 `reasoning_content` | ⚠ 思维链当正文 (C2 已知坑) |
| `common/.../llm/LlmClient.ets:293-301` 首字节超时 | 8s 内无首字节 → 抛 STREAM_FAILED | ⚠ 用户等 8s 才反馈, 期间无进度 |

### 3.2 缺降级的高风险点

| 场景 | 当前 | 应有 |
|---|---|---|
| LLM 限流 (429) | Toast "Failed" | "请求过于频繁, X 秒后重试" + 自动 retry with backoff |
| OCR 识别空 | Toast "未获取到照片" | "光线可能不足, 换个角度重试" + 重新拍照快捷按钮 |
| RDB 写失败 | Toast "保存失败" | "存储空间不足, 请清理后再试" + 错误日志 |
| 网络断开 | Toast "Failed" | 顶部红色横幅 + 网络恢复自动 retry |
| API key 失效 | Toast "Failed" | "API Key 失效, 点击跳转设置" |

---

## 4. 错误反馈现状样本 (15 处中抽 5)

| 位置 | 字面量 |
|---|---|
| `CameraOverlay.ets:94` | "未获取到照片" |
| `CameraOverlay.ets:118` | "未选择图片" |
| `NoteDetailOverlay.ets:371` | "摘要和正文至少填写一项" (校验) |
| `NoteDetailOverlay.ets:550` | "分享功能暂未开放" (feature flag) |
| `AiSettingsPage.ets:46` | "已保存" / "保存失败" |
| `AiSettingsPage.ets:61` | "请先输入 API Key" (前置校验) |
| `NotesPage.ets:54` | "笔记加载失败" |
| `NotesPage.ets:75` | "搜索功能开发中" |

**问题**: 中英文混杂 (Failed / 失败 / 加载失败), 风格不统一, 长度不规整 (8-12 字), 没用 i18n (后述)。

---

## 5. 评级

| 维度 | 评 | 备注 |
|---|---|---|
| 错误捕获覆盖率 | ✓ (99 处) | 业务代码几乎全 wrap |
| 结构化日志 | ✗ (18%) | 多数 catch 吞 `_e` |
| 错误分类 | ✗ (0) | 缺业务级 ErrorKind 枚举 |
| 用户感知分级 | ✗ (全 Toast) | 没有 ErrorBanner / 重试按钮 / 分级提示 |
| 降级路径 | △ (极少) | LlmClient 2 处, 业务侧零 |
| 错误字面量风格 | △ | 中英混杂, 待 i18n 收口 |
| Retry 自动恢复 | ✗ (0) | 失败需用户手动重做 |

---

## 6. 应有但缺的结构

### 6.1 ErrorKind 枚举 (建议)
```typescript
// common/.../errors/AppError.ets
export enum ErrorKind {
  NETWORK_OFFLINE = 'network_offline',
  NETWORK_TIMEOUT = 'network_timeout',
  LLM_AUTH_FAIL = 'llm_auth_fail',
  LLM_RATE_LIMIT = 'llm_rate_limit',
  LLM_CONTEXT_TOO_LONG = 'llm_context_too_long',
  LLM_OUTPUT_INVALID = 'llm_output_invalid',
  OCR_NOT_RECOGNIZED = 'ocr_not_recognized',
  OCR_SERVICE_DOWN = 'ocr_service_down',
  RDB_WRITE_FAIL = 'rdb_write_fail',
  RDB_READ_FAIL = 'rdb_read_fail',
  FILE_NOT_FOUND = 'file_not_found',
  UNKNOWN = 'unknown',
}
```

### 6.2 ErrorBus (建议)
```typescript
// common/.../errors/ErrorBus.ets
class ErrorBus {
  publish(error: AppError)  // 顶层 UI 监听, 弹 ErrorBanner
  subscribe(cb) → unsubscribe
}
```

### 6.3 ErrorBanner 组件 (建议)
- 顶部固定显示, 区分 severity (info / warn / error)
- 文案模板: `[图标] [分类名] [用户可读消息] [重试/查看详情 按钮]`
- 自动消失 (3-5s) 或用户手动关闭

### 6.4 LlmClient 改造 (建议)
- 把 12 种 LlmErrorKind 映射到 ErrorKind
- 加 retry-with-backoff (1s / 2s / 4s)
- 401/429 触发自动跳设置页

---

## 7. 与现有契约的冲突

- **不冲突**: 与 spec 012 / ADR-0008-0012 / CONTEXT.md 无明确接口
- **机会**: ErrorBus 改造时可与 KnowledgeUnit 复用 CaptureGraphError 的结构 (kind/message/step/retriable/cause)

---

## 8. 待补充资料

§5 第 6/7 项不变, 新增:
9. **真机演示中可能触发的失败清单**: 评委会演示时若遇失败, 当前 Toast 含糊到什么程度? (用于 ErrorBanner 文案设计)
10. **OCR 服务是否在真机演示中启动**: `tools/ocr_service/start.bat` 在 demo 前是否会被执行? 若不, OcrTool 失败是必然

---

## Last updated

2026-09-06 晚
