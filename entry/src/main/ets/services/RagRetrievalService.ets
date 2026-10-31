/**
 * RagRetrievalService.ets — RAG 检索（复用 @kit.DataAugmentationKit 的 retrieval）
 *
 * 路径: entry/src/main/ets/services/RagRetrievalService.ets
 * 职责: 用系统 DataAugmentationKit 的 retrieval 通道，直接在我们自己的 MindTrace.db 上做
 *       FTS/BM25 检索；本期提供设备能力探针与 search() 基础能力，供 NoteEvidenceService 切换召回。
 * 依赖: @kit.DataAugmentationKit (retrieval) / @kit.ArkData (relationalStore) / common DatabaseHelper
 *
 * 约束:
 *   - **只允许 entry 进程 import 本文件**（红线 11：受限 Kit 不得进扩展进程 / 不得经 common barrel）。
 *   - FTS 表未就绪、Kit 不可用、查询异常时一律抛/降级，由调用方回退既有 note.search。
 *
 * 数据流（目标态）:
 *   knowledge_unit 写入/更新/删除 → note_fts（schema v19）
 *   NoteEvidenceService.build(query) → RagRetrievalService.search(query, topK)
 *     → ItemInfo(primaryKey=unit_id, columns, score) → join knowledge_unit → NoteEvidenceCitation
 */
import { retrieval } from '@kit.DataAugmentationKit';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DatabaseHelper, Logger } from 'common';

const log: Logger = new Logger('RagRetrieval');
const DB_NAME: string = 'MindTrace.db';
const FTS_TABLE: string = 'note_fts';
const PROBE_SEED_TEXT: string = '函数在一点的连续性 极限 连续函数';
const PROBE_QUERY: string = '连续';
const KIT_PROBE_TIMEOUT_MS: number = 8000;

export interface RagProbeResult {
  fts5Ok: boolean;
  ftsHits: number;
  kitRetrieverOk: boolean;
  kitMessage: string;
}

export class RagRetrievalService {
  /**
   * 设备能力探针（双路，均带兜底，不阻塞）：
   *  ① 自管 RDB FTS5：建 `note_fts` → 插种子 → `MATCH` 查询（不依赖 Kit）
   *  ② Kit retrieval：`getRetriever` 加 8s 超时（真机实测该 Promise 可能永不 resolve）
   */
  static async probe(context: common.UIAbilityContext): Promise<string> {
    const result: RagProbeResult = { fts5Ok: false, ftsHits: 0, kitRetrieverOk: false, kitMessage: 'not-run' };
    await RagRetrievalService.probeFts5(result);
    await RagRetrievalService.probeKit(context, result);
    return RagRetrievalService.format(result);
  }

  /** 只测自管 FTS5（供带超时的真机探针单独调用）。 */
  static async fts5Diagnostic(): Promise<string> {
    const result: RagProbeResult = { fts5Ok: false, ftsHits: 0, kitRetrieverOk: false, kitMessage: '' };
    await RagRetrievalService.probeFts5(result);
    return result.kitMessage.length > 0
      ? 'fts5Ok=0 ftsHits=0 err=' + result.kitMessage
      : 'fts5Ok=' + (result.fts5Ok ? '1' : '0') + ' ftsHits=' + result.ftsHits.toString();
  }

  /** 只测 Kit getRetriever（供带超时的真机探针单独调用）。 */
  static async kitDiagnostic(context: common.UIAbilityContext): Promise<string> {
    const result: RagProbeResult = { fts5Ok: false, ftsHits: 0, kitRetrieverOk: false, kitMessage: '' };
    await RagRetrievalService.probeKit(context, result);
    return 'kitRetrieverOk=' + (result.kitRetrieverOk ? '1' : '0') + ' kit=' + result.kitMessage;
  }

  /** 自管 FTS5 探针：证明不依赖 Kit 也能做全文检索。 */
  private static async probeFts5(result: RagProbeResult): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      result.kitMessage = 'store-null';
      return;
    }
    try {
      await store.executeSql('CREATE VIRTUAL TABLE IF NOT EXISTS ' + FTS_TABLE
        + ' USING fts5(title, content, unit_id UNINDEXED, subject UNINDEXED, chapter UNINDEXED)');
      await store.executeSql('DELETE FROM ' + FTS_TABLE);
      await store.executeSql('INSERT INTO ' + FTS_TABLE
        + ' (title, content, unit_id, subject, chapter) VALUES (?, ?, ?, ?, ?)',
        ['极限与连续', PROBE_SEED_TEXT, 'rag-probe-unit', '数学分析', '连续性']);
      const rs: relationalStore.ResultSet = await store.querySql(
        'SELECT unit_id FROM ' + FTS_TABLE + ' WHERE ' + FTS_TABLE + ' MATCH ?', [PROBE_QUERY]);
      let hits: number = 0;
      while (rs.goToNextRow()) {
        hits += 1;
      }
      rs.close();
      result.fts5Ok = true;
      result.ftsHits = hits;
    } catch (error) {
      const e: BusinessError = error as BusinessError;
      result.kitMessage = 'fts5 err=' + (e.message !== undefined ? e.message : String(error));
      log.warn('rag fts5 probe failed: ' + result.kitMessage);
    }
  }

  /** Kit 探针：加超时（真机实测 getRetriever 可能挂起不 resolve）。 */
  private static async probeKit(context: common.UIAbilityContext, result: RagProbeResult): Promise<void> {
    try {
      const dbConfig: retrieval.DbConfig = {
        name: DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
      };
      const channel: retrieval.ChannelConfig = {
        channelType: retrieval.ChannelType.INVERTED_INDEX_DATABASE,
        context: context,
        dbConfig: dbConfig,
      };
      const config: retrieval.RetrievalConfig = { channelConfigs: [channel] };
      const timeout: Promise<retrieval.Retriever> = new Promise<retrieval.Retriever>(
        (resolve: (value: retrieval.Retriever) => void, reject: (reason: Error) => void): void => {
          setTimeout((): void => {
            reject(new Error('getRetriever timeout ' + KIT_PROBE_TIMEOUT_MS.toString() + 'ms'));
          }, KIT_PROBE_TIMEOUT_MS);
        });
      const retriever: retrieval.Retriever = await Promise.race([retrieval.getRetriever(config), timeout]);
      result.kitRetrieverOk = true;
      result.kitMessage = 'getRetriever ok';
    } catch (error) {
      const e: Error = error as Error;
      result.kitRetrieverOk = false;
      result.kitMessage = 'getRetriever failed: ' + e.message;
      log.warn('rag kit probe failed: ' + result.kitMessage);
    }
  }

  private static format(result: RagProbeResult): string {
    return 'fts5Ok=' + (result.fts5Ok ? '1' : '0')
      + ' ftsHits=' + result.ftsHits.toString()
      + ' kitRetrieverOk=' + (result.kitRetrieverOk ? '1' : '0')
      + ' kit=' + result.kitMessage;
  }
}
