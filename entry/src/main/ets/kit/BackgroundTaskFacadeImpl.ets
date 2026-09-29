/**
 * BackgroundTaskFacadeImpl.ets — 后台短时任务真实实现
 *
 * 路径: entry/src/main/ets/kit/BackgroundTaskFacadeImpl.ets
 * 职责: 通过 @kit.BackgroundTasksKit 的 requestSuspendDelay 完成一次性的后台短时任务
 * 依赖: @kit.BackgroundTasksKit, common BackgroundTaskFacade/BackgroundTaskTag
 *
 * 数据流:
 *   BackgroundTaskFacadeImpl.requestOneShot → requestSuspendDelay → finish(tag)
 *
 * ArkTS 1.1 strict 适配:
 *   - requestIds Map 持有 tag → requestId 映射,避免 finish() 找不到对应任务
 *   - 失败仅 warn, 不抛 throw;业务侧通过 boolean 返回决定是否重试
 */
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { BackgroundTaskFacade, BackgroundTaskTag } from 'common';

export class BackgroundTaskFacadeImpl implements BackgroundTaskFacade {
  private readonly requestIds: Map<BackgroundTaskTag, number> = new Map<BackgroundTaskTag, number>();

  async requestOneShot(tag: BackgroundTaskTag): Promise<boolean> {
    if (this.hasPending(tag)) {
      return false;
    }
    try {
      const info: backgroundTaskManager.DelaySuspendInfo = backgroundTaskManager.requestSuspendDelay(
        'MindTrace:' + tag,
        (): void => this.finish(tag),
      );
      this.requestIds.set(tag, info.requestId);
      return true;
    } catch (e) {
      console.warn('[BackgroundTaskFacadeImpl.requestOneShot] ' + (e instanceof Error ? e.message : String(e)));
      return false;
    }
  }

  hasPending(tag: BackgroundTaskTag): boolean {
    return this.requestIds.has(tag);
  }

  finish(tag: BackgroundTaskTag): void {
    const requestId: number | undefined = this.requestIds.get(tag);
    if (requestId === undefined) {
      return;
    }
    try {
      backgroundTaskManager.cancelSuspendDelay(requestId);
    } catch (e) {
      console.warn('[BackgroundTaskFacadeImpl.finish] ' + (e instanceof Error ? e.message : String(e)));
    }
    this.requestIds.delete(tag);
  }
}

export function getBackgroundTaskFacade(): BackgroundTaskFacade | null {
  const impl: BackgroundTaskFacadeImpl | undefined = AppStorage.get<BackgroundTaskFacadeImpl>('backgroundTaskFacade');
  return impl ?? null;
}
