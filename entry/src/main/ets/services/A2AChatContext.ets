/**
 * A2AChatContext.ets — A2A 聊天回合的上下文构建（RAG 证据注入）
 *
 * 路径: entry/src/main/ets/services/A2AChatContext.ets
 * 职责: 小艺端A2A 的普通对话在调用 ReplyService 前，复用 App 对话同款
 *       NoteEvidenceService 检索本机笔记，把证据上下文注入 ReplyContext，
 *       并对模型输出做引用校验（防止编造不存在的 noteId/version）。
 *       记忆/学习画像需要会话 ID，A2A 目前无会话，留空（后续 P1 再评估）。
 * 依赖: NoteEvidenceService（内部走 RagRetrievalService→FTS，失败回退 note.search）。
 *
 * 约束:
 *   - 证据构建最多等 1200ms；超时/异常降级为空上下文，不阻断聊天（和 App 对话一致）；
 *   - 返回 evidence 供调用方在回答后做 sanitizeAnswer。
 */

import { createNoteEvidenceService } from './EvidenceComposition';
import { DatabaseHelper } from 'common';
import { EmbeddingRuntime } from './EmbeddingRuntime';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { common } from '@kit.AbilityKit';
import type { NoteEvidenceContext } from 'common';
import type { ReplyContext } from 'agents/src/main/ets/chat/Index';
import type { NoteEvidenceService } from 'agents/src/main/ets/evidence/Index';

const TAG: string = 'MindTraceA2A';
const DOMAIN: number = 0xA2A0;
const EVIDENCE_TIMEOUT_MS: number = 1200;
// 稠密向量要在检索里多一次 HTTP 往返；沿用 1200ms 会把证据整段砍掉。
const EVIDENCE_TIMEOUT_DENSE_MS: number = 2500;
const EVIDENCE_TOP_K: number = 5;

export interface A2AChatContextResult {
  replyContext: ReplyContext;
  evidence: NoteEvidenceContext | undefined;
  citations: number;
  degraded: boolean;
  reason: string;
}

export class A2AChatContext {
  /** 构建聊天回合上下文（证据注入；超时/失败自动降级为空证据）。 */
  static async build(query: string, memoryContext: string = '',
    initContext?: common.Context): Promise<A2AChatContextResult> {
    const fallback: A2AChatContextResult = {
      replyContext: {
        memoryContext: memoryContext,
        learnerProfileContext: '',
        userContent: query,
        evidenceContext: '',
      },
      evidence: undefined,
      citations: 0,
      degraded: true,
      reason: 'evidence-skipped',
    };
    const trimmed: string = query.trim();
    if (trimmed.length === 0) {
      return fallback;
    }
    // 扩展进程的消息可能先于 prepare() 里的 DB 初始化到达；先等库就绪再检索，
    // 否则 getStore() 为空会走成 search-failed。失败时仍按降级路径继续。
    if (initContext !== undefined) {
      try {
        await DatabaseHelper.init(initContext);
      } catch (e) {
        // DB 不可用时证据检索会自行降级，不阻断聊天。
      }
    }
    try {
      const service: NoteEvidenceService = createNoteEvidenceService();
      const dense: boolean = EmbeddingRuntime.isDense();
      const timeoutMs: number = dense ? EVIDENCE_TIMEOUT_DENSE_MS : EVIDENCE_TIMEOUT_MS;
      const evidence: NoteEvidenceContext = await A2AChatContext.withTimeout(
        service.build(trimmed, { topK: EVIDENCE_TOP_K }), timeoutMs);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'A2A_EVIDENCE mode=' + (dense ? 'dense' : 'lexical')
          + ' citations=' + evidence.citations.length.toString()
          + ' degraded=' + (evidence.degraded ? '1' : '0')
          + ' reason=' + evidence.reason);
      return {
        replyContext: {
          memoryContext: memoryContext,
          learnerProfileContext: '',
          userContent: query,
          evidenceContext: evidence.contextText,
        },
        evidence: evidence,
        citations: evidence.citations.length,
        degraded: evidence.degraded,
        reason: evidence.reason,
      };
    } catch (e) {
      hilog.warn(DOMAIN, TAG, '%{public}s', 'A2A_EVIDENCE failed: ' + (e as Error).message);
      return fallback;
    }
  }

  /** 回答后做引用校验：删掉证据里不存在的 [noteId=... version=...] 引用。 */
  static sanitize(evidence: NoteEvidenceContext | undefined, answer: string): string {
    if (evidence === undefined || evidence.citations.length === 0) {
      return answer;
    }
    try {
      return createNoteEvidenceService().sanitizeAnswer(evidence, answer);
    } catch (e) {
      return answer;
    }
  }

  /** Promise.race 超时：证据检索超时按无证据回答。 */
  private static withTimeout(task: Promise<NoteEvidenceContext>, timeoutMs: number): Promise<NoteEvidenceContext> {
    return new Promise<NoteEvidenceContext>((resolve: (value: NoteEvidenceContext) => void,
      reject: (reason: Error) => void): void => {
      let settled: boolean = false;
      const timer: number = setTimeout((): void => {
        if (settled) {
          return;
        }
        settled = true;
        reject(new Error('evidence timeout'));
      }, timeoutMs);
      task.then((value: NoteEvidenceContext): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        resolve(value);
      }).catch((error: Error): void => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(error);
      });
    });
  }
}
