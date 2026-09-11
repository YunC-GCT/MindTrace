/**
 * NoteDaoInterface.ets — NoteDao 接口定义
 *
 * 路径: agents/src/main/ets/models/NoteDaoInterface.ets
 * 职责: 定义 agents 端 NoteDao 适配契约,供 entry 通过 NoteDaoAdapter 注入实现
 * 依赖: common KnowledgeUnit, NoteGenerationCommitResult
 *
 * 数据流:
 *   KnowledgeUnitWriteService → NoteDaoAdapter → NoteDaoInterface → NoteDao
 *
 * ArkTS 1.1 strict 适配:
 *   - 可选方法用 ? 标记,避免实现端被迫实现不需要的能力
 */
import { KnowledgeUnit, NoteGenerationCommitResult } from 'common';

export interface NoteCommitResult {
  commitKey: string;
  rowId: number;
  noteId: string;
  version: number;
  duplicate: boolean;
  success?: boolean;
  errorCode?: string;
  errorMessage?: string;
}

export interface NoteDaoInterface {
  insert(unit: KnowledgeUnit): Promise<number>;
  insertWithCommitKey?(unit: KnowledgeUnit, commit: NoteGenerationCommitResult): Promise<NoteCommitResult>;
  update?(unit: KnowledgeUnit, expectedVersion: number): Promise<NoteCommitResult>;
  updateWithCommitKey?(unit: KnowledgeUnit, expectedVersion: number, commit: NoteGenerationCommitResult): Promise<NoteCommitResult>;
}
