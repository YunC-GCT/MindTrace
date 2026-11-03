/**
 * NoteReviewEvidenceProviders.ets — 复习链的默认证据提供者（entry 实现）
 *
 * 路径: entry/src/main/ets/services/NoteReviewEvidenceProviders.ets
 * 职责: 把 entry 的 NoteEvidenceService 适配成 agents 的 NoteReviewEvidenceProvider；
 *       RDB / RAG / 图谱查询仍留在这里
 * 依赖: agents（NoteReviewEvidenceProvider 契约）、common、./NoteEvidenceService
 *
 * 数据流:
 *   ConversationPortsProduction → 本适配器 → NoteEvidenceService → RAG / RDB
 */
import {
  NoteEvidenceCitation,
  NoteEvidenceContext,
  NoteEvidenceOptions,
  NoteEvidenceStreamFilterPort,
} from 'common';
import { NoteReviewEvidenceProvider } from 'agents';
import type { NoteEvidenceService } from 'agents';

export class DefaultNoteReviewEvidenceProvider extends NoteReviewEvidenceProvider {
  private readonly service: NoteEvidenceService;

  constructor(service: NoteEvidenceService) {
    super();
    this.service = service;
  }

  async build(query: string, options?: NoteEvidenceOptions): Promise<NoteEvidenceContext> {
    return await this.service.build(query, options);
  }

  formatSources(context: NoteEvidenceContext): string {
    return this.service.formatSources(context);
  }

  sanitizeAnswerStrict(citations: NoteEvidenceCitation[], answer: string): string {
    return this.service.sanitizeAnswerStrict(citations, answer);
  }

  createStrictStreamFilter(citations: NoteEvidenceCitation[]): NoteEvidenceStreamFilterPort {
    return this.service.createStrictStreamFilter(citations);
  }

  hasVerifiedCitation(citations: NoteEvidenceCitation[], answer: string): boolean {
    return this.service.hasVerifiedCitation(citations, answer);
  }
}
