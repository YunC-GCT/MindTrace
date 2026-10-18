# MathMind 四层目录：模板 → 精简拍照 → 完整拍照 → MVP

> 模板: `D:\Math_Mind` — DevEco Studio Hello World（4 源文件）  
> 精简拍照: D1 链 7 文件改动（3学科×3类型，砍关联/图谱/确认）  
> 完整拍照: D1 链 10 文件改动（14学科×7类型，含关联/图谱/确认弹窗）  
> MVP: 含 S1 延后模块的完整比赛交付  
>   
> 🚫 = 初赛砍掉 · ⭐ = 新增/重写 · 🔧 = 改动 · ⏳ = S1/S2 预留

---

## 一、模板目录 —— DevEco Studio Hello World

> 路径: `D:\Math_Mind` · 4 个源文件

```
D:\Math_Mind/
├── AppScope/app.json5
├── build-profile.json5                        # SDK 6.1.1, 1模块(entry)
├── entry/
│   ├── src/main/
│   │   ├── module.json5
│   │   ├── ets/
│   │   │   ├── entryability/EntryAbility.ets  # 生命周期 (48行)
│   │   │   ├── entrybackupability/EntryBackupAbility.ets
│   │   │   └── pages/Index.ets               # Hello World (23行)
│   │   └── resources/
│   └── src/ohosTest/
└── oh_modules/
```

---

## 二、精简拍照链目录 —— D1 最小通线（7文件）

> 原则：相机拍照+列表显示 · 主Agent单意图 · 3学科×3类型 · 模板+真值检验 · 不确认/不关联/不图谱

```
MathMind/
│
├── AppScope/app.json5
├── build-profile.json5                        # 5模块: entry/common/agents/skill/cardservice
│
├── common/src/main/ets/
│   ├── constants/
│   │   ├── ApiConstants.ets
│   │   ├── AppConstants.ets
│   │   └── LlmConfig.ets                      # ⭐ 全局DeepSeek默认配置
│   ├── models/
│   │   └── KnowledgeUnit.ets                  # ✅ 26字段数据契约
│   ├── utils/
│   │   ├── TextUtils.ets
│   │   ├── DateUtils.ets
│   │   └── ColorUtils.ets
│   └── DatabaseHelper.ets                     # RDB 建表
│
├── agents/src/main/ets/
│   ├── core/
│   │   └── Dispatcher.ets                     # 🔧 A4 · 单意图→D1 路由
│   ├── agents/
│   │   ├── TypeClassifier.ets                 # ⭐ A5 · ML Kit OCR + 3×3分类
│   │   ├── KnowledgeModel.ets                 # ⭐ A6 · 3模板+真值检验+入库
│   │   ├── ContextLink.ets                    # 🚫 S1 · 语义关联
│   │   ├── RecallGraphAgent.ets               # 🚫 S1 · 图谱构建
│   │   ├── ReviewAgent.ets
│   │   ├── SearchAgent.ets
│   │   ├── UserPrefAgent.ets
│   │   ├── VersionAgent.ets
│   │   ├── RecycleAgent.ets
│   │   ├── FavoriteAgent.ets
│   │   └── ExportAgent.ets
│   ├── mcp/tools/
│   │   ├── OcrTool.ets
│   │   ├── LlmTool.ets                        # 默认 DeepSeek(SiliconFlow)
│   │   ├── SearchTool.ets
│   │   └── EmbeddingTool.ets                  # 🚫 S1 · 向量化
│   └── providers/
│       ├── ILLMProvider.ets
│       ├── XiaoyiKitProvider.ets
│       ├── SiliconFlowProvider.ets
│       └── OpenAICompatProvider.ets
│
├── entry/src/main/ets/
│   ├── entryability/EntryAbility.ets
│   ├── pages/
│   │   ├── Index.ets                          # 4 Tab 壳
│   │   ├── HomePage.ets                       # 首页(笔记列表+进度环+月历)
│   │   ├── NotesPage.ets                      # 笔记Tab(搜索+过滤)
│   │   ├── ReviewPage.ets                     # 复习Tab(计划/卡片/图谱)
│   │   ├── MePage.ets                         # 我的(统计+菜单)
│   │   └── PageStubs.ets
│   ├── fullpages/
│   │   ├── NewNotePage.ets                    # 🚫 S1 · 确认弹窗
│   │   ├── LoginPage.ets
│   │   ├── NoteDetailPage.ets
│   │   ├── ErrorDetailPage.ets
│   │   ├── NewPlanPage.ets
│   │   ├── StatisticsPage.ets
│   │   ├── FavoritesPage.ets
│   │   ├── ModelSettingsPage.ets
│   │   ├── AppearancePage.ets
│   │   ├── HelpPage.ets
│   │   ├── UpdatePage.ets
│   │   └── AgreementPage.ets
│   ├── overlays/
│   │   ├── CameraOverlay.ets                  # ⭐ 相机+相册→imageUri
│   │   ├── AiChatOverlay.ets
│   │   ├── NoteDetailOverlay.ets
│   │   ├── ErrorDetailOverlay.ets
│   │   └── DrawerOverlay.ets
│   ├── components/
│   │   ├── shared/SharedComponents.ets
│   │   ├── home/ notes/ review/ errors/ ai/ ocr/ settings/
│   ├── viewmodels/
│   │   ├── HomeViewModel.ets
│   │   ├── NotesViewModel.ets
│   │   ├── ReviewViewModel.ets
│   │   ├── MeViewModel.ets
│   │   ├── AiChatViewModel.ets
│   │   ├── NoteDetailViewModel.ets
│   │   └── OtherViewModels.ets
│   ├── services/
│   │   ├── ApiClient.ets                      # ⭐ HTTP request()实现
│   │   ├── AiService.ets                      # ⭐ capture(imageUri)→Dispatcher
│   │   ├── NoteService.ets
│   │   ├── ErrorService.ets
│   │   ├── ReviewService.ets
│   │   ├── PlanService.ets
│   │   ├── KgService.ets
│   │   ├── AuthService.ets
│   │   ├── CoreServices.ets
│   │   └── OtherServices.ets
│   ├── stores/
│   │   ├── AppStore.ets
│   │   ├── AuthStore.ets
│   │   └── OverlayStore.ets
│   ├── database/
│   │   ├── NoteDao.ets                        # 🔧 INSERT + queryById
│   │   ├── ErrorDao.ets
│   │   ├── FavoriteDao.ets
│   │   ├── PlanDao.ets
│   │   ├── ReviewDao.ets
│   │   ├── RelationDao.ets
│   │   └── UserPrefsDao.ets
│   ├── router/AppRouter.ets
│   └── mock/MockData.ets
│
├── skill/src/main/ets/SkillAbility.ets        # 小艺卡片入口
├── cardservice/src/main/ets/FormAbility.ets   # 桌面卡片
│
└── docs/
    ├── D1_CAPTURE_CHAIN.md                    # 拍照链设计+分工
    ├── DIRECTORY_MAP.md                       # 本文档
    ├── AGENT_ARCH_v3.1.md
    ├── API_SPEC.md
    ├── FRONTEND_ARCH_ADJUST.md
    ├── MODEL_SWITCH_ARCH.md
    ├── TWO_AXIS_CLASSIFICATION.md
    └── LOCAL_VS_API_STRATEGY.md
```

### 7 文件明细

| # | 文件 | 操作 | 核心内容 | 行数 |
|---|------|------|---------|------|
| 1 | `entry/overlays/CameraOverlay.ets` | ⭐ | 相机预览+快门+相册按钮 | ~80 |
| 2 | `entry/services/ApiClient.ets` | ⭐ | HTTP request() + JWT注入 + 重试 | ~80 |
| 3 | `entry/services/AiService.ets` | ⭐ | capture(imageUri)→base64→Dispatcher | ~50 |
| 4 | `agents/core/Dispatcher.ets` | 🔧 | 判断输入类型→D1路由→串联 A5+A6 | ~40 |
| 5 | `agents/agents/TypeClassifier.ets` | ⭐ | ML Kit OCR + DeepSeek 3×3分类 | ~150 |
| 6 | `agents/agents/KnowledgeModel.ets` | ⭐ | 3模板+真值检验+NoteDao INSERT | ~120 |
| 7 | `entry/database/NoteDao.ets` | 🔧 | SQL INSERT + queryById | ~60 |

### 数据流

```
CameraOverlay → imageUri → AiService.capture()
  → Dispatcher.dispatch()
    → TypeClassifier.classify(base64)   // OCR + DeepSeek 3×3分类
    → KnowledgeModel.structure(...)     // 模板 + 真值检验 + 入库
  ← KnowledgeUnit
→ HomePage 列表头部渲染新卡片
```

> 所有 Agent 同进程直接 `import` + `new Xxx().method()` 调用，不走 HTTP/MCP。  
> LLM 统一读 `common/constants/LlmConfig.ets`：默认 DeepSeek(SiliconFlow)。

### 🚫 本阶段预留

| 🚫 文件 | 用途 | 启用 |
|---------|------|------|
| `ContextLink.ets` (A7) | 笔记语义关联 | S1 |
| `RecallGraphAgent.ets` (A9) | 知识图谱 | S1 |
| `NewNotePage.ets` | 低置信确认弹窗 | S1 |
| `ConfirmOverlay.ets` | 通用确认弹窗 | S1 |
| `EmbeddingTool.ets` (T2) | 文本向量化 | S1 |
| 14学科/7类型 | 完整分类体系 | S1 |

---

## 三、完整拍照链目录 —— D1 全功能（10文件）

> 在精简链基础上加回：14学科×7类型 · 确认弹窗 · 语义关联 · 图谱 · L2兜底（S1 复赛）

与精简链（②）文件完全相同，以下 7 处发生变化：

| 文件 | 精简链 | 完整链 |
|------|--------|--------|
| `Dispatcher.ets` | 单意图→D1 | +L2 DeepSeek + 6路分发 + 4级降级 |
| `TypeClassifier.ets` | 3×3分类 | +14学科×7类型 + 决策树R1-R4 |
| `KnowledgeModel.ets` | 3模板 | +7模板 |
| `ContextLink.ets` | 🚫 | ⭐ 恢复 · Jaccard语义关联 |
| `RecallGraphAgent.ets` | 🚫 | ⭐ 恢复 · 图谱 |
| `NewNotePage.ets` | 🚫 | ⭐ 恢复 · 低置信确认弹窗 |
| `ConfirmOverlay.ets` | 🚫 | ⭐ 恢复 · 通用确认弹窗 |

### 完整链分类体系（14×7）

```
        高等代数 数学分析 解析几何 概率论 数理统计 离散数学 常微分方程 复变函数 实变函数 数学物理方法 考研数一 考研数二 考研数三 高中数学
概念      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
定理      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
公式      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
例题      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
错题      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
解法      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
考点      ✅     ✅      ✅     ✅     ✅      ✅       ✅      ✅      ✅       ✅       ✅     ✅     ✅     ✅
```

### ⏳ 完整链阶段预留

| ⏳ 文件 | 用途 | 启用 |
|---------|------|------|
| `EmbeddingTool.ets` (T2) | 向量化语义搜索 | S1 |
| `TokenManager.ets` | JWT管理 | S1 |
| `CaptureModels.ets` | 拍照流程模型 | S1 |
| `CaptureViewModel.ets` | 拍照状态机 | S1 |
| `OcclusionDetector.ets` | 遮挡检测 | S1 |
| `SettingsViewModel.ets` | 设置VM | S2 |
| `ModelStore.ets` | 模型切换 | S2 |
| `RecycleStore.ets` | 回收站状态 | S2 |
| `RecycleBinPage.ets` | 回收站 | S2 |
| `DataExportPage.ets` | 数据导出 | S2 |
| `TagsManagePage.ets` | 标签管理 | S2 |
| `RecycleService.ets` | 回收站API | S2 |
| `FavoriteService.ets` | 收藏API | S2 |
| `ExportService.ets` | 导出API | S2 |

---

## 四、MVP 目录 —— 完整比赛交付

> 在完整链基础上追加 S2 模块

与完整链（③）文件完全相同，以下新增 S2 延后模块：

| ⏳ 文件 | 用途 | 上线条件 |
|---------|------|---------|
| `entry/fullpages/RecycleBinPage.ets` | 回收站（红线#12） | S2 数据量足够时 |
| `entry/fullpages/DataExportPage.ets` | 数据导出（F17） | S2 数据迁移需求 |
| `entry/fullpages/TagsManagePage.ets` | 标签管理（F15） | S2 标签体系成熟后 |
| `entry/services/RecycleService.ets` | 回收站API | 配合 RecycleBinPage |
| `entry/services/FavoriteService.ets` | 收藏API | 收藏功能上线时 |
| `entry/services/ExportService.ets` | 导出API | 配合 DataExportPage |
| `entry/stores/ModelStore.ets` | 模型切换状态（F16） | S2 开放用户切换模型 |
| `entry/stores/RecycleStore.ets` | 回收站状态 | 配合 RecycleBinPage |
| `entry/viewmodels/SettingsViewModel.ets` | 设置VM | S2 设置页功能完整时 |
| `docs/MVP_CHECKLIST.md` | 上线检查清单 | S2 提审前 |

---

## 五、四层汇总

| 维度 | ①模板 | ②精简拍照 | ③完整拍照 | ④MVP |
|------|-------|----------|----------|------|
| **源文件** | 4 | ~75 | ~78 | ~90 |
| **D1 链文件** | 0 | **7** | **7+3** | 7+3 |
| **D1 Agent** | 0 | A4→A5→A6 | A4→A5→A6→A7→A9 | A4→A5→A6→A7→A9 |
| **学科×类型** | — | 3×3 | 14×7 | 14×7 |
| **语义关联** | ❌ | 🚫 | ✅ | ✅ |
| **图谱更新** | ❌ | 🚫 | ✅ | ✅ |
| **确认弹窗** | ❌ | 🚫 | ✅ | ✅ |
| **回收站** | ❌ | ❌ | ❌ | ⏳ |
| **模型切换** | ❌ | ❌ | ❌ | ⏳ |
| **数据导出** | ❌ | ❌ | ❌ | ⏳ |

### 7→10 演变

```
精简链(7)     →     完整链(+3)
─────────           ─────────
CameraOverlay       —
ApiClient           —
AiService           —
Dispatcher          +L2+6路分发
TypeClassifier      +14学科+7类型+决策树
KnowledgeModel      +7模板
NoteDao             —
                    + NewNotePage
                    + ContextLink
                    + RecallGraphAgent
```
