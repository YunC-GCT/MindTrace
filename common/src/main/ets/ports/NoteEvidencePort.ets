/**
 * NoteEvidencePort.ets — 证据检索与引文过滤的只读端口
 *
 * 路径: common/src/main/ets/ports/NoteEvidencePort.ets
 * 职责: 让对话 / 复习链路在不依赖 RDB、DAO 与 RAG 实现的前提下消费证据；
 *       实现（NoteEvidenceService）留在 entry，由组合根注入
 * 依赖: ../models/NoteEvidenceModels
 *
 * 数据流:
 *   用户问题 → NoteEvidencePort.build → NoteEvidenceContext → 回答 / 流式过滤
 */
import type {
  CitationVersionRef,
  NoteEvidenceCitation,
  NoteEvidenceContext,
  NoteEvidenceOptions,
} from '../models/NoteEvidenceModels';

/** 流式引文过滤：逐段写入 delta，返回可以安全输出的文本；结束时 flush 余量。 */
export interface NoteEvidenceStreamFilterPort {
  push(delta: string): string;
  flush(): string;
}

export interface NoteEvidencePort {
  build(query: string, options?: NoteEvidenceOptions): Promise<NoteEvidenceContext>;
  formatRetrievalStatus(context: NoteEvidenceContext): string;
  formatSources(context: NoteEvidenceContext): string;
  sanitizeAnswer(context: NoteEvidenceContext, answer: string): string;
  createStreamFilter(context: NoteEvidenceContext | undefined): NoteEvidenceStreamFilterPort;
  createStrictStreamFilter(citations: NoteEvidenceCitation[]): NoteEvidenceStreamFilterPort;
  hasVerifiedCitation(citations: NoteEvidenceCitation[], answer: string): boolean;
}

/** 严格过滤只需要版本句柄，单独导出便于调用方构造。 */
export type NoteEvidenceCitationRef = CitationVersionRef;
