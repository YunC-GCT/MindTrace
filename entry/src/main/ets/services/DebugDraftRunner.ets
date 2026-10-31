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
import type { KnowledgeUnit, NoteDraftReadyEvent } from 'common';
import { AiService } from './AiService';

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
}
