/**
 * NoteDaoAdapter.ets — agents 侧 NoteDaoInterface 的 entry 适配器
 *
 * 路径: entry/src/main/ets/adapters/NoteDaoAdapter.ets
 * 职责: 把 agents 的 NoteDaoInterface 转成 entry 的 KnowledgeUnitWriteService 调用；
 *       提供 insert / update / commitKey 写入与 queryById 读取。
 * 依赖: common (KnowledgeUnit / NoteGenerationCommitResult)、agents (NoteDaoInterface)、
 *       services/KnowledgeUnitWriteService。
 */
// MindTrace - entry-side NoteDao adapter for agents/ NoteDaoInterface
// 2026-09-05 · D2 Ticket #5
import { KnowledgeUnit, NoteGenerationCommitResult } from 'common';
import { NoteCommitResult, NoteDaoInterface } from 'agents';
import { KnowledgeUnitWriteResult } from 'common';
import { KnowledgeUnitWriteService } from '../services/KnowledgeUnitWriteService';

export class NoteDaoAdapter implements NoteDaoInterface {
  private service: KnowledgeUnitWriteService;

  constructor(service: KnowledgeUnitWriteService) {
    this.service = service;
  }

  async insert(unit: KnowledgeUnit): Promise<number> {
    const result: KnowledgeUnitWriteResult = await this.service.create(unit, 'capture_graph');
    console.info('[NoteDaoAdapter] insert completed rowId=' + result.rowId.toString() + ' category=' + unit.category);
    for (const warning of result.warnings) {
      console.warn('[NoteDaoAdapter] post-commit warning: ' + warning);
    }
    return result.rowId;
  }

  /** 幂等复用/回执需要 title/subject：把写服务的读取能力暴露给 agents 侧。 */
  async queryById(id: string): Promise<KnowledgeUnit | null> {
    return await this.service.queryById(id);
  }

  async insertWithCommitKey(unit: KnowledgeUnit, commit: NoteGenerationCommitResult): Promise<NoteCommitResult> {
    const result: KnowledgeUnitWriteResult = await this.service.createWithCommitKey(
      unit,
      commit.generationMetadata ?? commit.runId,
      commit,
    );
    for (const warning of result.warnings) {
      console.warn('[NoteDaoAdapter] post-commit warning: ' + warning);
    }
    return {
      commitKey: commit.commitKey,
      rowId: result.rowId,
      noteId: result.unit.id,
      version: result.unit.version,
      duplicate: result.duplicate === true,
      success: result.committed,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
    };
  }

  async update(unit: KnowledgeUnit, expectedVersion: number): Promise<NoteCommitResult> {
    const result: KnowledgeUnitWriteResult = await this.service.update(unit, expectedVersion, 'manual_edit');
    return {
      commitKey: '', rowId: result.rowId, noteId: result.unit.id, version: result.unit.version, duplicate: false,
      success: result.committed, errorCode: result.errorCode, errorMessage: result.errorMessage,
    };
  }

  async updateWithCommitKey(
    unit: KnowledgeUnit,
    expectedVersion: number,
    commit: NoteGenerationCommitResult,
  ): Promise<NoteCommitResult> {
    const result: KnowledgeUnitWriteResult = await this.service.updateWithCommitKey(
      unit,
      expectedVersion,
      commit.generationMetadata ?? '',
      commit,
    );
    return {
      commitKey: commit.commitKey,
      rowId: result.rowId,
      noteId: result.unit.id,
      version: result.unit.version,
      duplicate: result.duplicate === true,
      success: result.committed,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
    };
  }
}
