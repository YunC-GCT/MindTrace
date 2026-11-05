/**
 * A2ASession.ets — 单次 A2A 请求的运行态
 *
 * 路径: entry/src/main/ets/services/A2ASession.ets
 * 职责: 控制器与回答处理器共享的请求状态（token / deadline / 已回话标记 / 模型解析结果）
 * 依赖: common（CancellationToken）、./A2AErrorTaxonomy
 *
 * 数据流: A2AController.runQuery 创建 → AnswerHandler 推进 → settle 收尾
 */
import type { CancellationToken } from 'common';
import type { NoteEvidenceContext } from 'common';

export interface A2ARequestSession {
  taskId: string;
  /** 本轮原始 query：用于会话记忆与回执判定 */
  query: string;
  token: CancellationToken;
  startedAt: number;
  /** 实际发起模型调用的时刻；0 表示尚未调用 */
  requestStartedAt: number;
  deadlineTimer: number;
  responded: boolean;
  requestedModel: string;
  canonicalModel: string;
  attempts: number;
  /** 本轮回合注入的 RAG 证据（回答后做引用校验） */
  evidence?: NoteEvidenceContext;
  /** 会话键：contextId 优先，回退 taskId；用于多轮记忆 */
  conversationKey: string;
}
