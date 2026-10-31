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
import { planRagQuery, RagQueryPlan } from './RagQueryPlan';

const log: Logger = new Logger('RagRetrieval');
const DB_NAME: string = 'MindTrace.db';
const FTS_TABLE: string = 'note_fts';
const PROBE_SEED_TEXT: string = '函数在一点的连续性 极限 连续函数';
const PROBE_QUERY: string = '连续性';
const KIT_PROBE_TIMEOUT_MS: number = 8000;

export interface RagHit {
  unitId: string;
  title: string;
  content: string;
  subject: string;
  chapter: string;
  score?: number;
}

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

  /** 只测 Kit（getRetriever + retrieveRdb 真查询），供带超时的真机探针单独调用。 */
  static async kitDiagnostic(context: common.UIAbilityContext): Promise<string> {
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
      const retriever: retrieval.Retriever = await retrieval.getRetriever(config);
      const bm25: retrieval.Bm25Strategy = { bm25Weight: 1.0 };
      const recall: retrieval.InvertedIndexRecallCondition = {
        ftsTableName: FTS_TABLE,
        fromClause: FTS_TABLE,
        primaryKey: ['unit_id'],
        responseColumns: ['title', 'content', 'subject', 'chapter'],
        invertedIndexStrategies: [bm25],
        recallName: 'note-bm25',
      };
      const condition: retrieval.RetrievalCondition = {
        recallConditions: [recall],
        resultCount: 5,
      };
      let records: retrieval.RdbRecords | undefined = undefined;
      let firstError: string = '';
      try {
        // 档1：只给召回条件，不显式指定策略（默认策略）
        const plainCondition: retrieval.RetrievalCondition = { recallConditions: [recall], resultCount: 5 };
        records = await retriever.retrieveRdb(PROBE_QUERY, plainCondition);
      } catch (error1) {
        const e1: Error = error1 as Error;
        firstError = e1.message;
      }
      if (records === undefined) {
        // 档2：显式 BM25 策略（权重 0.5，避开 1.0 边界）
        const bm25Half: retrieval.Bm25Strategy = { bm25Weight: 0.5 };
        const recall2: retrieval.InvertedIndexRecallCondition = {
          ftsTableName: FTS_TABLE,
          fromClause: FTS_TABLE,
          primaryKey: ['unit_id'],
          responseColumns: ['title', 'content', 'subject', 'chapter'],
          invertedIndexStrategies: [bm25Half],
          recallName: 'note-bm25',
        };
        const condition2: retrieval.RetrievalCondition = { recallConditions: [recall2], resultCount: 5 };
        try {
          records = await retriever.retrieveRdb(PROBE_QUERY, condition2);
        } catch (error2) {
          const e2: Error = error2 as Error;
          return 'kitOk=0 err1=' + firstError + ' err2=' + e2.message;
        }
      }
      let firstKey: string = '';
      if (records.records.length > 0) {
        firstKey = records.records[0].primaryKey;
      }
      return 'kitOk=1 hits=' + records.records.length.toString() + ' first=' + firstKey;
    } catch (error) {
      const e: Error = error as Error;
      return 'kitOk=0 err=' + e.message;
    }
  }

  /** 自管 FTS5 探针：证明不依赖 Kit 也能做全文检索。 */
  private static async probeFts5(result: RagProbeResult): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      result.kitMessage = 'store-null';
      return;
    }
    try {
      await store.executeSql('DROP TABLE IF EXISTS ' + FTS_TABLE);
      await store.executeSql('CREATE VIRTUAL TABLE ' + FTS_TABLE
        + " USING fts5(title, content, unit_id UNINDEXED, subject UNINDEXED, chapter UNINDEXED, tokenize='trigram')");
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

  /**
   * RAG 检索一期：自管 FTS5（trigram）。
   * - ≥3 字：MATCH（rank 排序）
   * - <3 字：LIKE 子串 fallback
   * 任何失败返回空数组（由调用方回退 note.search）。
   */
  static async search(query: string, topK: number): Promise<RagHit[]> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      return [];
    }
    const trimmed: string = query.trim();
    if (trimmed.length === 0 || topK <= 0) {
      return [];
    }
    const plan: RagQueryPlan = planRagQuery(trimmed);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      if (plan.mode === 'fts') {
        resultSet = await store.querySql(plan.sql, [trimmed, topK]);
      } else {
        const pattern: string = '%' + trimmed + '%';
        resultSet = await store.querySql(plan.sql, [pattern, pattern, topK]);
      }
      const hits: RagHit[] = [];
      while (resultSet.goToNextRow()) {
        const hit: RagHit = {
          unitId: resultSet.getString(resultSet.getColumnIndex('unit_id')),
          title: resultSet.getString(resultSet.getColumnIndex('title')),
          content: resultSet.getString(resultSet.getColumnIndex('content')),
          subject: resultSet.getString(resultSet.getColumnIndex('subject')),
          chapter: resultSet.getString(resultSet.getColumnIndex('chapter')),
        };
        hits.push(hit);
      }
      return hits;
    } catch (error) {
      log.warn('rag search failed query=' + trimmed + ' err=' + (error as Error).message);
      return [];
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
  }

  private static format(result: RagProbeResult): string {
    return 'fts5Ok=' + (result.fts5Ok ? '1' : '0')
      + ' ftsHits=' + result.ftsHits.toString()
      + ' kitRetrieverOk=' + (result.kitRetrieverOk ? '1' : '0')
      + ' kit=' + result.kitMessage;
  }
}
