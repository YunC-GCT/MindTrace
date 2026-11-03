/**
 * IngestGateway.ets — 无头整理入口的统一网关（A2A / 分享 / inbox）
 *
 * 路径: entry/src/main/ets/services/IngestGateway.ets
 * 职责: 收一个 AgentIngestRequest，按 mode 选择执行方式：
 *       - inline：当前进程同步整理（A2A 单次整理、系统分享/卡片选图）；
 *       - background：交给 WriteJobScheduler / 直连整理（inbox 兜底、后台补跑）。
 *       图片请求始终 inline（队列只存文本）；OCR 计划仍由 AgentIngestService 提供。
 * 依赖: common (Context / NoteOutcome)、AgentIngestService、AgentIngestRequest、A2APlanModels。
 * 数据流: A2AController / EntryAbility / A2AInboxIngestService → IngestGateway → AgentIngestService
 *
 * 边界: 不解析协议、不拼回执、不持有 UI；mode 是唯一策略点（ADR-0024 §2.1/§2.7）。
 */
import type { common } from '@kit.AbilityKit';
import type { NoteOutcome } from 'common';
import { AgentIngestService } from './AgentIngestService';
import type { AgentTextBatchResult } from './AgentIngestService';
import { AgentIngestRequest, buildIngestRequest } from './AgentIngestRequest';
import type { IngestBatchResult } from './AgentIngestRequest';
import type { A2APlanItem } from './A2APlanModels';

export type IngestMode = 'inline' | 'background';
export const INGEST_MODE_INLINE: IngestMode = 'inline';
export const INGEST_MODE_BACKGROUND: IngestMode = 'background';

export class IngestGateway {
  /** OCR + 按题规划（不写库）；图片入口用。 */
  static async plan(request: AgentIngestRequest): Promise<A2APlanItem[] | null> {
    return await AgentIngestService.planItemsFromRequest(request);
  }

  /**
   * 执行一次整理。图片请求始终 inline（队列只存文本）；文本按 mode 选择：
   * inline → 立即执行（多题时首题回执 + 其余 queuedTexts）；background → 调度器/直连单题。
   */
  static async ingest(context: common.Context, request: AgentIngestRequest,
    mode: IngestMode): Promise<IngestBatchResult> {
    if (request.images.length > 0) {
      const outcome: NoteOutcome = await AgentIngestService.ingestOutcome(context, request);
      const result: IngestBatchResult = { outcomes: [outcome], totalProblems: 1, queuedTexts: [] };
      return result;
    }
    const text: string = request.text.trim();
    if (text.length === 0) {
      throw new Error('empty payload');
    }
    if (mode === INGEST_MODE_BACKGROUND) {
      const outcome: NoteOutcome = await AgentIngestService.ingestSingleText(context, text, 'background');
      const result: IngestBatchResult = { outcomes: [outcome], totalProblems: 1, queuedTexts: [] };
      return result;
    }
    const batch: AgentTextBatchResult = await AgentIngestService.ingestTextBatch(context, text);
    const result: IngestBatchResult = {
      outcomes: batch.outcomes,
      totalProblems: batch.totalProblems,
      queuedTexts: batch.queuedTexts,
    };
    return result;
  }

  /** 纯文本便捷入口：入口层不必自己拼 AgentIngestRequest。 */
  static async ingestText(context: common.Context, text: string, source: string,
    mode: IngestMode): Promise<IngestBatchResult> {
    return await IngestGateway.ingest(context, buildIngestRequest(source, text, []), mode);
  }
}
