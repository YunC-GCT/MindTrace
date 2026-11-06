/**
 * DebugDraftRunner.ets — HITL 草稿链真机自检（仅 e2e 调试入口）
 *
 * 路径: entry/src/main/ets/services/DebugDraftRunner.ets
 * 职责: 跑「生成草稿 → 确认入库」整链，每阶段打 [E2E] 日志，验证 v18 审批哈希与命令终态。
 * 依赖: AiService（generateNoteDraft / confirmDraft）。
 *
 * 数据流: run(ctx) → generateNoteDraft(runId, instruction, sourceText) → confirmDraft(event, candidate) → hilog [E2E]
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from 'common';
import type { KnowledgeUnit, NoteDraftReadyEvent } from 'common';
import { AiService } from './AiService';
import { DRAFT_PROBE_INPUTS } from './DebugDraftCorpus';
import type { DraftProbeInput } from './DebugDraftCorpus';

const TAG: string = 'E2E';
const DOMAIN: number = 0xE2E0;

export class DebugDraftRunner {
  static async run(ctx: common.UIAbilityContext): Promise<void> {
    const service: AiService = new AiService(ctx);
    const runId: string = 'e2e-draft-' + Date.now().toString();
    const startedAt: number = Date.now();
    try {
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=draft start runId=' + runId);
      const event: NoteDraftReadyEvent = await service.generateNoteDraft(
        runId,
        '整理洛必达法则求极限的方法',
        '洛必达法则用于计算 0/0 型与无穷/无穷型极限：在满足条件时，对分子分母分别求导后再取极限。',
      );
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=draft ok ms=' + (Date.now() - startedAt).toString()
          + ' checkpointId=' + event.checkpointId
          + ' hash=' + event.candidateHash.substring(0, 12));
      const confirmStart: number = Date.now();
      hilog.info(DOMAIN, TAG, '%{public}s', 'stage=confirm start');
      const unit: KnowledgeUnit = await service.confirmDraft(event, event.candidate);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=confirm ok ms=' + (Date.now() - confirmStart).toString()
          + ' noteId=' + unit.id + ' title=' + unit.title);
      hilog.info(DOMAIN, TAG, '%{public}s',
        'stage=done ok=1 totalMs=' + (Date.now() - startedAt).toString());
    } catch (error) {
      const e: Error = error as Error;
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=fail ms=' + (Date.now() - startedAt).toString() + ' err=' + e.message);
      hilog.error(DOMAIN, TAG, '%{public}s',
        'stage=done ok=0 totalMs=' + (Date.now() - startedAt).toString());
    }
  }

  /**
   * 生成笔记的相似度对照实验：同题异构（应判重）与相邻主题（不应判重）各生成一次。
   * 判重结果用「笔记总数是否增加」判断——写入口命中重复时不新增行。
   */
  static async runPairs(ctx: common.UIAbilityContext): Promise<void> {
    const store: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    if (store === null) {
      hilog.error(DOMAIN, TAG, '%{public}s', 'stage=done draftPairs=0 err=store-null');
      return;
    }
    const service: AiService = new AiService(ctx);
    const startedAt: number = Date.now();
    let created: number = 0;
    let deduped: number = 0;
    let failed: number = 0;
    for (let i = 0; i < DRAFT_PROBE_INPUTS.length; i += 1) {
      const item: DraftProbeInput = DRAFT_PROBE_INPUTS[i];
      const runId: string = 'e2e-pair-' + Date.now().toString() + '-' + i.toString();
      const itemStart: number = Date.now();
      try {
        const before: number = await DebugDraftRunner.countNotes(store);
        const event: NoteDraftReadyEvent = await service.generateNoteDraft(
          runId, item.instruction, item.sourceText);
        const unit: KnowledgeUnit = await service.confirmDraft(event, event.candidate);
        const after: number = await DebugDraftRunner.countNotes(store);
        const reused: boolean = after === before;
        if (reused) {
          deduped += 1;
        } else {
          created += 1;
        }
        hilog.info(DOMAIN, TAG, '%{public}s',
          'stage=pair group=' + item.group + ' label=' + item.label
            + ' reused=' + (reused ? '1' : '0')
            + ' noteId=' + unit.id + ' title=' + unit.title
            + ' ms=' + (Date.now() - itemStart).toString());
      } catch (error) {
        failed += 1;
        hilog.error(DOMAIN, TAG, '%{public}s',
          'stage=pair group=' + item.group + ' label=' + item.label
            + ' fail=' + (error as Error).message);
      }
    }
    hilog.info(DOMAIN, TAG, '%{public}s',
      'stage=done draftPairs=1 created=' + created.toString() + ' deduped=' + deduped.toString()
        + ' failed=' + failed.toString() + ' totalMs=' + (Date.now() - startedAt).toString());
  }

  private static async countNotes(store: relationalStore.RdbStore): Promise<number> {
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql('SELECT COUNT(*) AS c FROM knowledge_unit', []);
      if (!resultSet.goToFirstRow()) {
        return 0;
      }
      return resultSet.getLong(resultSet.getColumnIndex('c'));
    } finally {
      if (resultSet !== undefined) {
        resultSet.close();
      }
    }
  }
}
