/**
 * ConversationState.ets — Conversation workflow State 类型定义
 *
 * 路径: entry/src/main/ets/workflows/conversation/ConversationState.ets
 * 职责: 定义 ConversationStep 状态机节点 / ConversationProgressStep 进度上报 / ConversationRequest 三种请求 / ConversationState 状态结构
 * 依赖: ../../services/IntentClassifier (TextIntent)
 *
 * 数据流:
 *   ConversationWorkflow.buildGraph → ConversationState (初始 / 中间 / 结束) → 节点函数 copyState → 下游节点
 *
 * 设计要点:
 *   - P0 (spec 018 / 019): 单后端 + 一处 State 类型; draft 状态六字段仅 regenerate_reply / note_reply 节点写入
 *   - ConversationStep 与 ConversationProgressStep 双层命名: 前者驱动图,后者驱动 UI 进度提示
 *
 * ArkTS 1.1 strict 适配:
 *   - discriminated union 用 type aliases 表达 (无 interface 继承)
 *   - 所有可选字段显式 `?:` 标注,避免 uninitialized 推断
 */

import { TextIntent } from '../../services/IntentClassifier';
import { NoteEvidenceContext } from '../../models/NoteEvidenceModels';
import { ClassificationResult, NoteGenerationRoute } from 'common';

export type ConversationStep =
  | 'START'
  | 'classify_intent'
  | 'classify_image_intent'
  | 'load_reply_context'
  | 'save_reply_input'
  | 'image_reply'
  | 'image_note_reply'
  | 'complete_reply'
  | 'stream_reply'
  | 'note_reply'
  | 'regenerate_reply'
  | 'END';

export type ConversationProgressStep =
  | 'intent_check'
  | 'reply_context_load'
  | 'reply_model_call'
  | 'image_message_save'
  | 'image_recognize'
  | 'image_material_save'
  | 'image_ocr_blank'
  | 'image_note_ocr'
  | 'image_note_draft'
  | 'note_intent_check'
  | 'note_context_load'
  | 'note_source_prepare'
  | 'note_structure_save'
  | 'note_finalize'
  | 'completed';

export interface ImageConversationRequest {
  kind: 'image';
  imageUri: string;
  userContent: string;
  route?: NoteGenerationRoute;
}

export interface TextConversationRequest {
  kind: 'text';
  userContent: string;
  responseMode: 'complete' | 'stream';
  route?: NoteGenerationRoute;
}

export interface RegenerateConversationRequest {
  kind: 'regenerate';
  noteId: string;
  userContent: string;
}

export type ConversationRequest = ImageConversationRequest | TextConversationRequest | RegenerateConversationRequest;

export interface ConversationState {
  request: ConversationRequest;
  sessionId: string;
  currentStep: ConversationStep;
  intent?: TextIntent;
  memoryContext?: string;
  learnerProfileContext?: string;
  // DEV-006: load_reply_context 构造的可追溯检索/图谱证据, 供 complete/stream 引用
  evidence?: NoteEvidenceContext;
  draftRunId?: string;
  draftCheckpointId?: string;
  draftCandidateHash?: string;
  draftStatus?: 'ready-preview' | 'user-edit' | 'confirmed' | 'cancelled' | 'material-failed';
  ocrResult?: ClassificationResult;
  ocrSourceId?: string;
  isOcrBlank?: boolean;
  materialPersistFailed?: boolean;
}
