/**
 * KnowledgeUnitEmbeddingEffect.ets — 写后补建向量
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitEmbeddingEffect.ets
 * 职责: 笔记提交后为它的 rag_chunk 计算并写入向量。放在 post-commit 而不是事务内：
 *       向量计算是纯 CPU 工作，塞进事务会拉长写锁持有时间；缺失也可由补建自愈，
 *       不像 FTS 那样会造成检索永久漏召回。
 * 依赖: @kit.ArkData、common（KnowledgeUnit / KnowledgeUnitPostCommitEffect）、./NoteEmbeddingService。
 */
import { relationalStore } from '@kit.ArkData';
import { KnowledgeUnit, KnowledgeUnitPostCommitEffect } from 'common';
import { NoteEmbeddingService } from './NoteEmbeddingService';

export class KnowledgeUnitEmbeddingEffect implements KnowledgeUnitPostCommitEffect {
  name: string = 'note-embedding';
  private store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async run(unit: KnowledgeUnit): Promise<void> {
    await NoteEmbeddingService.embedUnit(this.store, unit.id);
  }
}
