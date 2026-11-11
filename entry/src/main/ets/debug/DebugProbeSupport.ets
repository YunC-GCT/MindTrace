/**
 * DebugProbeSupport.ets — 调试探针的共享工具
 *
 * 路径: entry/src/main/ets/debug/DebugProbeSupport.ets
 * 职责: 超时包装、RDB 计数、图片落地与检索重试等调试脚本共用能力
 * 依赖: @kit.AbilityKit / @kit.ArkData / common
 *
 * 数据流: 各 Debug*Probes → 本文件 → 定时器 / 文件 / RDB
 */
/**
 * DebugCaptureRunner.ets — 批量链路自检（仅调试入口可见时使用）
 * 路径: entry/src/main/ets/debug/DebugCaptureRunner.ets
 * 职责: 用 rawfile 里的样例题图跑完「取图 → OCR → 结构化 → 落库 → 卡片快照」整链，
 *       每个阶段打一条 [E2E] 日志，失败不中断后续图（与批量入口的语义一致）。
 * 依赖: AiService / CardSnapshotService / CoreVisionImageSearchIndex / ResourceManager / CoreFileKit / CaptureReceipt
 * 数据流: run(ctx) → getRawFileContent('debug/math-N.png') → cacheDir 下的 file:// →
 *        AiService.capture() → CardSnapshotService.refresh() → hilog [E2E]
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { DatabaseHelper, ImageSearchIndexRegistry } from 'common';
import type { CaptureSetItemResult, CaptureSetPreview, CaptureSetProblem, CaptureSetResult, ImageSearchHit, KnowledgeUnit, NoteOutcome } from 'common';
import { AiService } from '../services/AiService';
import { CardSnapshotService } from '../services/CardSnapshotService';
import { CoreVisionImageSearchIndex } from '../services/CoreVisionImageSearchIndex';
import { CaptureReceipt, CaptureReceiptStore } from '../services/CaptureReceipt';
import { RagHit, RagRetrievalService } from '../services/RagRetrievalService';
import { RagKitProbe } from '../services/RagKitProbe';
import { AgentIngestService, AgentTextBatchResult } from '../services/AgentIngestService';
import { A2AChatContext, A2AChatContextResult } from '../services/A2AChatContext';

import { NoteDao } from '../database/NoteDao';
import { RunStoreDao } from '../database/RunStoreDao';
import { A2AInboxIngestService, IngestSummary } from '../services/A2AInboxIngestService';
import { AgentInboxQueue } from '../services/AgentInboxQueue';
import { A2AImageContextStore } from '../services/A2AImageContextStore';
import { buildInboxItem } from '../services/AgentInboxModels';
import { WRITE_JOB_RUN_PREFIX } from '../services/WriteJobEvents';
import { WriteJobFlags, WriteJobScheduler, WriteJobStats } from '../services/WriteJobScheduler';
import { WRITE_JOB_PERSIST_ENABLED, WRITE_JOB_UI_ENABLED, WriteJobPersistenceFlags } from '../services/WriteJobConfig';
import { AgentJobPersistence } from '../services/WriteJobPersistence';
import { WriteJobBootstrap } from '../services/WriteJobBootstrap';
import { AgentJobDao } from '../database/AgentJobDao';
import { AgentImagePart } from '../services/AgentImageParts';
import { AgentIngestRequest, buildIngestRequest, INGEST_SOURCE_XIAOYI } from '../services/AgentIngestRequest';
import {
  A2APlan,
  A2APlanItem,
  buildA2APlanItems,
  formatA2APlanProgress,
  formatA2APlanSummary,
  nextPlanItem,
  remainingPlanCount,
} from '../services/A2APlanModels';
import { A2APlanStore } from '../services/A2APlanStore';

import { createNoteEvidenceService } from '../services/EvidenceComposition';
import { NoteEvidenceContext } from 'common';
import { AppIntentDecision, classifyAppIntentLocal } from 'agents/src/main/ets/chat/Index';
import { LegacyDedupeEntry, LegacyDuplicateGroup, LegacySubjectInput, groupExactDuplicates, groupNearDuplicates, normalizeLegacySubject, isDuplicateOf } from 'agents/src/main/ets/note/Index';
import type { NoteEvidenceService } from 'agents/src/main/ets/evidence/Index';

const TAG: string = 'E2E';
const DOMAIN: number = 0xE2E0;
const CAPTURE_TIMEOUT_MS: number = 150000;
const CARD_TIMEOUT_MS: number = 15000;

export class DebugProbeSupport {
  static async countRows(store: relationalStore.RdbStore, table: string): Promise<number> {
    try {
      const rs: relationalStore.ResultSet = await store.querySql('SELECT COUNT(*) AS c FROM ' + table, []);
      try {
        if (rs.goToFirstRow()) {
          return rs.getLong(rs.getColumnIndex('c'));
        }
        return 0;
      } finally {
        rs.close();
      }
    } catch (error) {
      return -1;
    }
  }

  /** RAG 能力探针：FTS5 与 Kit 各自带超时，保证一定给出结论。 */

  static isSearchDegraded(): boolean {
    const index = ImageSearchIndexRegistry.require();
    if (index instanceof CoreVisionImageSearchIndex) {
      return index.lastSearchDegraded();
    }
    return false;
  }

  /** search 失败等 500ms 再试一次：索引刚写入时首次检索可能不返回 */

  static async searchWithRetry(query: string): Promise<ImageSearchHit[]> {
    let lastError: string = '';
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        return await ImageSearchIndexRegistry.require().search(query, 5);
      } catch (error) {
        lastError = (error as BusinessError).message ?? 'unknown';
        hilog.warn(DOMAIN, TAG, '%{public}s',
          'search attempt=' + attempt.toString() + ' q=' + query + ' err=' + lastError);
        await DebugProbeSupport.sleep(500);
      }
    }
    throw new Error(lastError);
  }

  static async withTimeout<T>(task: Promise<T>, ms: number, label: string): Promise<T> {
    let timer: number = -1;
    const timeout: Promise<T> = new Promise<T>((_resolve, reject) => {
      timer = setTimeout(() => {
        reject(new Error(label + ' 超时 ' + ms.toString() + 'ms'));
      }, ms);
    });
    try {
      return await Promise.race([task, timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  static async sleep(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), ms);
    });
  }

  /** rawfile → 缓存目录，返回 file:// URI（capture 的 ImageUriResolver 能吃这个形式） */

  static async materialize(ctx: common.UIAbilityContext, rawPath: string): Promise<string> {
    const bytes: Uint8Array = await ctx.resourceManager.getRawFileContent(rawPath);
    const name: string = rawPath.substring(rawPath.lastIndexOf('/') + 1);
    const path: string = ctx.cacheDir + '/e2e-' + name;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, bytes.buffer as ArrayBuffer);
    } finally {
      fileIo.closeSync(file);
    }
    return 'file://' + path;
  }
}

// 036 幂等自检辅助：按题目顺序拼 noteId 串（空值跳过，便于两次提交对比）。
class CaptureSetResultScanner {

}

export { TAG, DOMAIN, CAPTURE_TIMEOUT_MS, CARD_TIMEOUT_MS };
