/**
 * ClarificationRegistry.ets — 澄清 run 的活跃表 + 失败落库（AiService 拆分切片 4 的共享依赖）
 *
 * 路径: entry/src/main/ets/services/ai/ClarificationRegistry.ets
 * 职责: 维护「正在跑的澄清 run → CancellationToken」映射；提供澄清生成失败时的 run 状态落库。
 * 依赖: common 类型 / NoteGenerationRepository。
 *
 * 为什么单独抽：草稿生命周期（DraftPipeline）与澄清流程（Slice 5）都需要这张表，
 * 放在任何一方都会造成反向依赖；先作为两个能力域的共享注册表。
 */
import {
  CancellationToken,
  Logger,
  NoteContextClarification,
  NoteGenerationRecovery,
  NoteGenerationRepository as NoteGenerationRepositoryContract,
} from 'common';

const log: Logger = new Logger('ClarificationRegistry');

export class ClarificationRegistry {
  static readonly activeRuns: Map<string, CancellationToken> = new Map<string, CancellationToken>();

  static async markGenerationFailed(
    repository: NoteGenerationRepositoryContract,
    recovery: NoteGenerationRecovery,
  ): Promise<void> {
    const clarification: NoteContextClarification | undefined = recovery.run.clarification;
    if (clarification === undefined || clarification.status !== 'selected') { return; }
    const latest: NoteGenerationRecovery | undefined = await repository.restore(recovery.run.id);
    if (latest === undefined || latest.run.status === 'cancelled' || latest.run.status === 'committed') { return; }
    // A failed execution does not revoke the user's confirmed topic.
    latest.run.status = 'failed';
    latest.run.stopReason = latest.run.stopReason ?? 'topic_generation_failed';
    latest.run.updatedAt = Date.now();
    await repository.saveRun(latest.run, latest.sources);
    recovery.run = latest.run;
  }
}
