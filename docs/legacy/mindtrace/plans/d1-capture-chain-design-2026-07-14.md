# D1 拍照链 — 设计 + 实现 + 今晚分工

> 目标：拍照 → OCR → DeepSeek 3×3 分类 → 模板+真值检验 → 入库 → 显示  
> 默认 LLM：**DeepSeek（SiliconFlow）**，降级：DeepSeek → 小艺Kit → Mock  
> 7 文件 · ~600 行

---

## 一、链时序

```
CameraOverlay  ── 拍照/相册 → imageUri
      │
AiService.capture(imageUri)  ── file→base64
      │
Dispatcher.dispatch()        ── 判断图片 → D1
      │
TypeClassifier.classify()    ── ML Kit OCR → cleanText → DeepSeek 3×3 分类
      │                          → { type, subject, chapter, confidence }
      │
KnowledgeModel.structure()   ── 按 type 选模板 → 真值检验 → NoteDao.insert
      │                          → KnowledgeUnit
      ↓
返回 KnowledgeUnit  →  HomePage 列表头部渲染新卡片
```

**砍掉：** ContextLink(A7)、RecallGraph(A9)、NewNotePage确认弹窗、14学科、7类型

---

## 二、分类体系（3学科 × 3类型）

| | 高等代数 | 数学分析 | 解析几何 |
|---|---------|---------|---------|
| 概念 | ✅ | ✅ | ✅ |
| 计算 | ✅ | ✅ | ✅ |
| 证明 | ✅ | ✅ | ✅ |

**概念** — 定义、性质、基本命题  
**计算** — 涉及数值/符号运算  
**证明** — 需要推理链条的命题

**高等代数** — 矩阵/行列式/线性空间/多项式/特征值  
**数学分析** — 极限/导数/积分/级数/连续  
**解析几何** — 向量/直线/平面/曲线/曲面

### DeepSeek 分类 Prompt

```
你是 MathMind 的分类器。分析以下数学内容，返回 JSON：
{ "type":"概念|计算|证明", "subject":"高等代数|数学分析|解析几何",
  "chapter":"章节名(可选)", "confidence":0.0-1.0 }

概念: 数学定义/性质/基本命题
计算: 涉及数值或符号运算的题目/方法
证明: 需要推理链条的命题

高等代数: 矩阵/行列式/线性空间/多项式/特征值
数学分析: 极限/导数/积分/级数/连续
解析几何: 向量/直线/平面/曲线/曲面

用户输入：{{text}}
只输出JSON，不要解释。
```

---

## 三、三种模板 + 真值检验

### 概念模板
```
## 定义
{OCR原文}
## 性质
(待补充)
```

### 计算模板
```
## 题目
{OCR原文}
## 解法
(待补充)
```

### 证明模板
```
## 命题
{OCR原文}
## 证明
(待补充)
```

### 真值检验（本地，不联网）
1. 括号配对 `( ) [ ] { }` → 不匹配 → warning
2. 除零检测 `/0` `÷0` → error
3. 矛盾等式 `"1=2"` `"0=1"` → error
4. LaTeX `$$` `{ }` 配对检查

结果写入 `truthFlag: 'valid' | 'warning' | 'error'`，error 级 UI 标红。

---

## 四、Agent 通信模式

所有 Agent 在同一鸿蒙进程内，**不走 HTTP，直接 `import` + `new Xxx().method()` 调**。

```
Dispatcher dispatch():
  const classifier = new TypeClassifier()
  const classification = await classifier.classify(base64)
  // ↑ TypeClassifier 内部调 LlmTool.chat(..., { provider: DEFAULT_PROVIDER })

  const model = new KnowledgeModel()
  const unit = await model.structure(ocrText, type, subject, chapter)
  // ↑ KnowledgeModel 如需调 LLM 同样 import DEFAULT_PROVIDER

  return { success: true, route: 'D1', data: unit }
```

**所有 Agent 的 LLM 调用统一读 `common/constants/LlmConfig.ets`：**

```typescript
export const DEFAULT_PROVIDER = 'siliconflow'   // DeepSeek
export const DEFAULT_MODEL = 'deepseek-ai/DeepSeek-V3'
export const CLASSIFY_TEMPERATURE = 0.1
export const LLM_TIMEOUT_MS = 5000
```

换模型改 `DEFAULT_PROVIDER` 一行全局生效。

---

## 五、Dispatcher 今晚实现（精简版）

`Dispatcher` 不是 HTTP 服务端，是 App 内部的一个路由类。

```typescript
import { TypeClassifier, ClassificationResult } from '../agents/TypeClassifier'
import { KnowledgeModel } from '../agents/KnowledgeModel'

export class Dispatcher {

  async dispatch(req: DispatchRequest): Promise<DispatchResult> {
    const t0 = Date.now()
    try {
      // 判断图片 → 分类
      const classifier = new TypeClassifier()
      const classification = await classifier.classify(req.payload)

      // 建模 + 入库
      const model = new KnowledgeModel()
      const unit = await model.structure(
        req.payload,
        classification.type,
        classification.subject,
        classification.chapter
      )

      return { success: true, route: 'D1', data: unit, traceId: req.traceId ?? '', durationMs: Date.now() - t0 }
    } catch (e) {
      return { success: false, route: 'D1', errorMessage: String(e), traceId: req.traceId ?? '', durationMs: Date.now() - t0 }
    }
  }
}
```

**今晚 Dispatcher 不做的：**
- L1 关键词匹配（只有一个意图）
- L2 DeepSeek 兜底
- 6 路路由
- MCP 总线
- 4 级降级（失败直接抛异常）
- Trace 日志

---

## 六、今晚任务分工（7 文件，串行依赖 A→B→C→D→E）

| 顺序 | 文件 | 内容 | 验证 |
|------|------|------|------|
| A1 | `NoteDao.ets` | INSERT + queryById | 写入 → 返回 rowId → 查回 |
| A2 | `ApiClient.ets` | HTTP request() + JWT + 重试 | curl /health |
| B1 | `OcrTool.ets` | ML Kit OCR | 传公式图 → 返回文本 |
| B2 | `TypeClassifier.ets` | OCR → DeepSeek 3×3 分类 | "求行列式" → {type:"计算", subject:"高等代数"} |
| C | `KnowledgeModel.ets` | 3模板 + 真值检验 + NoteDao.insert | 文本+分类 → KnowledgeUnit → DB |
| D | `Dispatcher.ets` | 接起 B2→C | dispatch(base64) → KnowledgeUnit |
| E1 | `AiService.ets` | capture(imageUri)→base64→Dispatcher | 日志见 note.id |
| E2 | `CameraOverlay.ets` | 相机+快门+相册→调 AiService | 拍照 → 日志见 note.id |

**时间线：** A(40min) → B(1h) → C(40min) → D(40min) → E(40min) ≈ **4h，19:00→23:00**

---

## 七、LLM 配置

| 配置项 | 值 |
|--------|-----|
| Provider | SiliconFlow / DeepSeek-V3 |
| 模型 | `deepseek-ai/DeepSeek-V3` |
| API | `https://api.siliconflow.cn/v1/chat/completions` |
| Temperature | 0.1（分类） |
| Timeout | 5s |
| 降级链 | DeepSeek → 小艺Kit → Mock |
| 配置位置 | `common/constants/LlmConfig.ets` |

---

## 八、验证标准（端到端）

```
1. App 首页点 [+] → 拍照/选图
2. 拍"求极限 lim(x→0) sinx/x"
3. 等 2-3s
4. 首页顶部出现：【计算】求极限 lim(x→0) sinx/x
5. 点卡片 → 模板正文（## 题目 / ## 解法 / ## 答案）
```
