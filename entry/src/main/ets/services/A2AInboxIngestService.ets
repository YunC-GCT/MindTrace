/**
 * A2AInboxIngestService.ets — 把「小艺排进来的待整理原文」用正规写路径入库。
 *
 * 路径: entry/src/main/ets/services/A2AInboxIngestService.ets
 * 职责: 应用回到前台时领取队列，逐条走 AiService.ingestText（Dispatcher → 结构化 → 落库），
 *       单条失败只记日志，不打断同批其它条目。
 * 依赖: AgentInboxQueue、AiService
 *
 * 为什么放在应用进程：notes 库由应用进程独占；扩展进程只负责把原文写进队列文件。
 * 触发时机只有用户回到应用（EntryAbility.onForeground），不跟冷启动抢首帧。
 */

import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from 'common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AgentInboxItem } from './AgentInboxModels';
import { AgentInboxQueue } from './AgentInboxQueue';
import { AiService } from './AiService';

const DOMAIN: number = 0xA2A0;
const TAG: string = 'A2AInbox';

/** 一次消费的结果，只用于日志与后续可能的界面提示。 */
export interface IngestSummary {
  claimed: number;
  done: number;
  failed: number;
}

export class A2AInboxIngestService {
  private static running: boolean = false;
  /** 前台轮询句柄：-1 表示没在轮询。 */
  private static timer: number = -1;

  /**
   * 应用在前台时每 5s 看一眼队列。
   * 为什么需要：用户可能正在应用里，小艺在另一侧把原文排进队列，此时不会再触发 onForeground，
   * 只靠生命周期钩子会漏掉。
   */
  static startWatch(context: common.UIAbilityContext): void {
    if (A2AInboxIngestService.timer !== -1) {
      return;
    }
    A2AInboxIngestService.timer = setInterval((): void => {
      A2AInboxIngestService.consume(context).catch((e: Error): void => {
        hilog.error(DOMAIN, TAG, 'watch consume failed: %{public}s', e.message);
      });
    }, 5000);
  }

  /** 退到后台就停，别在后台空转。 */
  static stopWatch(): void {
    if (A2AInboxIngestService.timer === -1) {
      return;
    }
    clearInterval(A2AInboxIngestService.timer);
    A2AInboxIngestService.timer = -1;
  }

  /** 队列为空时立即返回；有活儿时同一时刻只跑一批（前台反复切换不叠加）。 */
  static async consume(context: common.UIAbilityContext): Promise<IngestSummary> {
    const empty: IngestSummary = { claimed: 0, done: 0, failed: 0 };
    if (A2AInboxIngestService.running) {
      return empty;
    }
    // 库还没就绪（冷启动早期）就先不动队列：留着下次前台再消费，别把待整理原文吞掉。
    if (DatabaseHelper.getStore() === null) {
      hilog.info(DOMAIN, TAG, 'store not ready, keep queue untouched');
      return empty;
    }
    A2AInboxIngestService.running = true;
    let items: AgentInboxItem[] = [];
    try {
      items = await AgentInboxQueue.claim(context);
      if (items.length === 0) {
        return empty;
      }
      hilog.info(DOMAIN, TAG, 'consume start, claimed=%{public}d', items.length);
      const service: AiService = new AiService(context);
      let done: number = 0;
      let failed: number = 0;
      for (let i = 0; i < items.length; i++) {
        try {
          await service.ingestText(items[i].text);
          done += 1;
        } catch (error) {
          failed += 1;
          const message: string = error instanceof Error ? error.message : String(error);
          hilog.error(DOMAIN, TAG, 'ingest failed, id=%{public}s reason=%{public}s', items[i].id, message);
        }
      }
      hilog.info(DOMAIN, TAG, 'consume done, done=%{public}d failed=%{public}d', done, failed);
      const summary: IngestSummary = { claimed: items.length, done: done, failed: failed };
      return summary;
    } finally {
      if (items.length > 0) {
        await AgentInboxQueue.complete(context);
      }
      A2AInboxIngestService.running = false;
    }
  }
}
