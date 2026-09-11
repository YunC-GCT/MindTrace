// MindTrace - D1 拍照链共享类型
// 跨模块传输的入参/出参/中间结果接口
// 创建: Z (W1 块 3 主 agent 业务 - 2026-07-13)

import { KnowledgeUnit } from './CommonTypes';
import { NoteGenerationRequest, NoteGenerationResult, PreparedCandidate } from './NoteGenerationModels';

// ==================== B2 分类结果 ====================
// B2 classify 入参(Dispatcher 转发,任一字段可单独传)
export interface ClassificationInput {
  ocrText?: string;
  imageBase64?: string;
}

export type NoteCategory = '概念' | '定理' | '公式' | '证明题' | '计算题';

export interface ClassificationResult {
  // 笔记类型(五分类, 与 KnowledgeModel 的 KnowledgeCategory 对齐)
  type: NoteCategory;
  // 学科(LLM 自由判定, 不限制枚举值; 高等代数/数学分析/解析几何 为推荐类别)
  subject: string;
  // 章节(可选,如"微分中值定理" / "行列式")
  chapter?: string;
  // 分类置信度 0.0-1.0,主 agent 用作路由门控
  confidence: number;
  // OCR 文本(图片走 OCR 后才有;纯文本分类时为空, 由 Dispatcher fallback 到 payload)
  ocrText?: string;
}

// ==================== C 真值检验 ====================
// 单条真值问题
export type TruthFlag =
  | '括号不配对'
  | '除零'
  | '恒等式'
  | '矛盾等式'
  | 'LaTeX语法错误'
  | 'OCR置信度低'
  | '无明确题目';

export interface TruthCheckResult {
  // 是否通过(无 flag 即通过)
  passed: boolean;
  // 触发的问题清单
  flags: TruthFlag[];
  // 可选描述(给 UI 显示)
  message?: string;
}

// ==================== D 调度请求/响应 ====================
// 调度请求入参(2026-07-14 升级:payload 改 discriminated union,接 image/text/file)
//   设计动机: 旧版 payload: string 太宽,UI 端要猜"是 base64 / 文本 / 啥?"
//   新版按 kind 显式分流,TypeClassifier / KnowledgeModel 不用再做字符串嗅探
// 图片: 拍照 / 相册,imageUri 给 ML Kit OCR
export interface ImagePayload {
  kind: 'image';
  imageUri: string;
  userText?: string;
}

// 纯文本: 用户手输 / 复制粘贴 / 提取后的文本,无 OCR
export interface TextPayload {
  kind: 'text';
  text: string;
}

// 任意文件: 文档选择器来的,带 mimeType 决定下游解析方式
export interface FilePayload {
  kind: 'file';
  fileUri: string;
  mimeType: string;
  userText?: string;
}

export type DispatchPayload = ImagePayload | TextPayload | FilePayload;

export interface DispatchRequest {
  // 来源标识
  source: 'app' | 'skill' | 'card';
  // 调度入参(2026-07-14 改:从 string 升级为 DispatchPayload)
  payload: DispatchPayload;
  generation?: NoteGenerationRequest;
  preparedCandidate?: PreparedCandidate;
}

// 调度结果出参
export interface DispatchResult {
  success: boolean;
  // 当前固定 'D1' — 未来加 D2 复习 / D3 问答
  route: 'D1';
  data?: KnowledgeUnit;
  classification?: ClassificationResult;
  recognizedText?: string;
  // 失败时填描述
  errorMessage?: string;
  // 处理耗时(毫秒)
  durationMs: number;
  generation?: NoteGenerationResult;
  errorCode?: string;
}

// ==================== 通用 API 响应包装 ====================
// ApiClient.request() 的返回类型
// 后端真实返回结构:{code, message, data, success}
export interface ApiResponse<T = Object> {
  code: number;
  message: string;
  data?: T;
  success: boolean;
}

// 业务错误码(简单 record,避免 ArkTS 对 as const + typeof 衍生类型的限制)
export interface ApiCodeMap {
  OK: 0;
  UNAUTHORIZED: 401;
  FORBIDDEN: 403;
  NOT_FOUND: 404;
  RATE_LIMIT: 429;
  INTERNAL: 500;
  BAD_GATEWAY: 502;
  // 业务码
  INTENT_UNCLEAR: 1001; // 意图不识别
  OCR_FAILED: 2001; // OCR 失败
  CLASSIFY_LOW_CONF: 2002; // 分类置信度 < 0.7
  TEMPLATE_RENDER_FAIL: 3001; // 模板渲染失败
  TRUTH_CHECK_FAIL: 3002; // 真值检验失败
  DB_INSERT_FAIL: 4001; // 入库失败
}

export const API_CODE: ApiCodeMap = {
  OK: 0,
  UNAUTHORIZED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  RATE_LIMIT: 429,
  INTERNAL: 500,
  BAD_GATEWAY: 502,
  INTENT_UNCLEAR: 1001,
  OCR_FAILED: 2001,
  CLASSIFY_LOW_CONF: 2002,
  TEMPLATE_RENDER_FAIL: 3001,
  TRUTH_CHECK_FAIL: 3002,
  DB_INSERT_FAIL: 4001,
};

export type ApiCode = number;

// ==================== 业务阈值 ====================
// 分类置信度门控(主 Agent 用作路由门控,低于此值走 fallback)
export const CLASSIFY_CONFIDENCE_THRESHOLD: number = 0.7;
