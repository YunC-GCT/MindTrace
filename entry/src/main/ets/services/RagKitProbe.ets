/**
 * RagKitProbe.ets — DataAugmentationKit retrieval 专用探针（仅调试 harness 使用）
 *
 * 路径: entry/src/main/ets/services/RagKitProbe.ets
 * 职责: 只做 Kit 能力探测（getRetriever + retrieveRdb 诊断）；与生产检索链路解耦，
 *       避免 NoteEvidenceService/常规测试因受限 Kit（@kit.DataAugmentationKit）无法加载。
 * 依赖: @kit.DataAugmentationKit / @kit.ArkData / @kit.AbilityKit / common DatabaseHelper。
 *
 * 真机结论（2026-10-31）：getRetriever 14ms OK；retrieveRdb 报 1021201002 数值参数越界（暂缓）。
 */
import { retrieval } from '@kit.DataAugmentationKit';
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const DB_NAME: string = 'MindTrace.db';
const FTS_TABLE: string = 'note_fts';
const PROBE_QUERY: string = '连续性';

export class RagKitProbe {
  /** getRetriever + retrieveRdb 诊断；返回可读字符串，绝不抛出。 */
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
      const bm25: retrieval.Bm25Strategy = { bm25Weight: 0.5 };
      const recall: retrieval.InvertedIndexRecallCondition = {
        ftsTableName: FTS_TABLE,
        fromClause: FTS_TABLE,
        primaryKey: ['unit_id'],
        responseColumns: ['title', 'content', 'subject', 'chapter'],
        invertedIndexStrategies: [bm25],
        recallName: 'note-bm25',
      };
      const condition: retrieval.RetrievalCondition = { recallConditions: [recall], resultCount: 5 };
      const records: retrieval.RdbRecords = await retriever.retrieveRdb(PROBE_QUERY, condition);
      return 'kitOk=1 hits=' + records.records.length.toString();
    } catch (error) {
      return 'kitOk=0 err=' + (error as Error).message;
    }
  }
}
