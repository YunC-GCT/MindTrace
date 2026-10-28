// MindTrace - D1 拍照链共享类型
// 跨模块传输的入参/出参/中间结果接口
// 创建: Z (W1 块 3 主 agent 业务 - 2026-07-13)

import { KnowledgeUnit } from './CommonTypes';
import { NoteGenerationRequest, NoteGenerationResult, PreparedCandidate, SourceFragment } from './NoteGenerationModels';

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
  // OCR 正文质量: refined 表示 LLM 已完成保守清洗; fallback 表示只保留本地规则结果。
  ocrTextQuality?: 'refined' | 'fallback';
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

// ==================== 溯源 ====================
// 拍照 / 图片 OCR 到 KnowledgeUnit 的来源元数据。
// sourceRegion 当前没有坐标数据时固定为空字符串；
// ocrConfidence 只能来自 OCR 结果本身，工具未返回置信度时为 0，禁止估算。
export interface CaptureProvenance {
  sourceImageId: string;
  sourceRegion: string;
  ocrConfidence: number;
}

// 从 OCR 源片段提取来源图片。多张不同来源图无法用单字段准确表达，返回 undefined 而不是猜一张。
export function captureProvenanceFromFragments(fragments: SourceFragment[]): CaptureProvenance | undefined {
  let imageId: string = '';
  for (const fragment of fragments) {
    if (fragment.kind !== 'ocr') {
      continue;
    }
    const originId: string = fragment.originId.trim();
    if (originId.length === 0) {
      continue;
    }
    if (imageId.length === 0) {
      imageId = originId;
    } else if (imageId !== originId) {
      return undefined;
    }
  }
  if (imageId.length === 0) {
    return undefined;
  }
  return {
    sourceImageId: imageId,
    sourceRegion: '',
    ocrConfidence: 0,
  };
}

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

// ==================== 集合级整理（spec 036 阶段 1）====================
// 一次「整理」= 用户选中的 1..N 张图。集合级只保证「一个 set 一个 run」：
// 顺序执行每一项、共享同一个 RunContext（预算 + 取消），逐项隔离失败、逐项回执。
// 切题（一图多题）与跨图合并不在本切片，见 docs/specs/036-* 阶段 2/3。
export interface CaptureSetRequest {
  // 与 DispatchRequest.source 同域，避免在 dispatchSet 里静默收窄/放宽
  source: 'app' | 'skill' | 'card';
  items: DispatchPayload[];
}

export interface CaptureSetItemResult {
  index: number;
  kind: string;
  success: boolean;
  noteId?: string;
  category?: string;
  errorMessage?: string;
  errorCode?: string;
  // 该组是否因取消而未执行/未完成；取消不是失败，回执里单独计数
  cancelled: boolean;
  durationMs: number;
}

export interface CaptureSetResult {
  total: number;
  done: number;
  failed: number;
  cancelled: number;
  items: CaptureSetItemResult[];
  durationMs: number;
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
