// MindTrace - common 共享类型定义
// 所有 module 跨边界传输的接口与枚举集中在此处
// 创建: Z (W1 块 2 - 2026-07-04)

// ==================== 难度等级 ====================
export enum DifficultyLevel {
  EASY = 1, // 简单 - 5 分钟回忆
  MEDIUM = 2, // 中等 - 10 分钟回忆
  HARD = 3, // 困难 - 30 分钟回忆
  EXPERT = 4, // 专家级 - 60 分钟以上
}

// ==================== 置信度等级(间隔重复评分)====================
export enum ConfidenceLevel {
  FORGOT = 0, // 完全忘记
  HARD = 1, // 困难回忆
  NORMAL = 2, // 正常回忆
  EASY = 3, // 轻松回忆
  PERFECT = 4, // 完美回忆
}

// ==================== 复习状态 ====================
export enum ReviewStatus {
  NEW = 'new', // 新加入,未复习
  LEARNING = 'learning', // 学习中(短期间隔)
  REVIEW = 'review', // 长期复习中
  GRADUATED = 'graduated', // 已毕业(掌握)
  LAPSED = 'lapsed', // 遗忘,需重学
}

// ==================== 意图类型(3 入口)====================
export enum IntentType {
  // 主 App
  APP_REVIEW = 'app_review', // 复习入口
  APP_QUERY = 'app_query', // 提问入口
  APP_KG_EXPLORE = 'app_kg_explore', // 知识图谱浏览
  APP_HISTORY = 'app_history', // 历史记录
  APP_SETTINGS = 'app_settings', // 设置

  // 小艺 Skill
  SKILL_QUICK_REVIEW = 'skill_quick_review', // 快速复习
  SKILL_ASK = 'skill_ask', // 问答
  SKILL_ADD = 'skill_add', // 添加知识点
  SKILL_CARD = 'skill_card', // 卡片查看
  SKILL_FLASH = 'skill_flash', // 闪卡
  SKILL_VOICE_QUERY = 'skill_voice_query', // 语音提问
  SKILL_REMIND = 'skill_remind', // 复习提醒

  // 元服务卡片
  CARD_TODAY = 'card_today', // 今日待复习
  CARD_STREAK = 'card_streak', // 连续打卡
  CARD_NEW = 'card_new', // 新知识点
  CARD_PROGRESS = 'card_progress', // 进度总览
}

// ==================== 知识单元(核心数据)====================
export interface KnowledgeUnit {
  id: string; // 唯一标识(UUID)
  title: string; // 标题
  content: string; // 完整内容
  summary: string; // 简洁概览；完整公式、推导和原文保存在 content
  tags: string[]; // 标签
  subject: string; // 学科（独立于 tags，如"高等数学"/"线性代数"）
  category: string; // 题型分类（五选一："概念"/"定理"/"公式"/"证明题"/"计算题"）
  chapter: string; // 章节/知识点短语（独立于 source，如"微分中值定理"）
  difficulty: DifficultyLevel; // 难度
  source: string; // 来源标记(camera_capture/manual/file_import)
  sourceImageId?: string; // 溯源: 来源图片 ID(无图片时为空)
  sourceRegion?: string; // 溯源: 来源区域(图片坐标/裁剪区域序列化字符串)
  ocrConfidence?: number; // 溯源: OCR 置信度(未知为 0)
  createdAt: number; // 创建时间戳
  updatedAt: number; // 更新时间戳

  // 间隔重复状态
  reviewStatus: ReviewStatus;
  nextReviewAt: number; // 下次复习时间戳
  intervalDays: number; // 当前间隔天数
  easeFactor: number; // SM-2 算法的易度因子(默认 2.5)
  repetitions: number; // 连续正确次数

  // KG 关联
  prerequisites: string[]; // 前置知识点 ID 列表
  related: string[]; // 相关知识点 ID 列表
  embedding: number[]; // 向量嵌入(可选,空时不做语义检索)

  // 元数据
  userId: string; // 所属用户
  version: number; // 乐观锁版本号
}

// ==================== 复习记录 ====================
export interface ReviewRecord {
  id: string;
  unitId: string; // 关联的知识单元
  reviewedAt: number; // 复习时间戳
  confidence: ConfidenceLevel; // 评分
  durationMs: number; // 耗时(毫秒)
  oldInterval: number; // 复习前间隔
  newInterval: number; // 复习后间隔
  note: string; // 复习笔记(可选)
}

// ==================== 知识图谱节点 ====================
export interface KGNode {
  id: string;
  unitId: string; // 关联 KnowledgeUnit.id
  label: string; // 显示标签
  cluster: string; // 聚类标签
  centrality: number; // 中心度(0-1)
  x: number; // 布局坐标
  y: number;
}

// ==================== 知识图谱边 ====================
export interface KGEdge {
  from: string; // 源节点 ID
  to: string; // 目标节点 ID
  type: 'prerequisite' | 'related' | 'derived'; // 边类型
  weight: number; // 权重(0-1)
}

// ==================== Agent 任务 ====================
export interface AgentTask {
  id: string;
  type: IntentType;
  payload: Record<string, string>; // 输入参数(JSON 字符串)
  priority: number; // 1-10,数字越大越优先
  deadline: number; // 截止时间戳
  caller: string; // 调用方(entry/skill/cardservice)
  createdAt: number;
}

// ==================== Agent 响应 ====================
export interface AgentResponse {
  taskId: string;
  success: boolean;
  data: Record<string, string>; // 输出结果(JSON 字符串)
  errorMessage: string; // 失败时填值
  durationMs: number;
  agentName: string; // 实际处理的 Agent
}

// ==================== API 错误 ====================
export interface ApiError {
  code: number;
  message: string;
  retryable: boolean; // 是否可重试
}
