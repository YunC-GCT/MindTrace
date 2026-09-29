/**
 * RendererScheduler.test.ets — RendererScheduler 优先级、预算和生命周期测试
 *
 * 路径: entry/src/test/RendererScheduler.test.ets
 * 职责: 验证纯数据任务排序、视口距离、时间预算、异步完成和销毁保护。
 * 依赖: Hypium, RendererScheduler
 *
 * 数据流:
 *   fake RenderTaskRunner → RendererScheduler → 高度回调/待处理状态
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 fake classes，避免无类型对象字面量和结构化推断。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  RenderTask,
  RenderTaskCompletion,
  RenderTaskCompletionHandler,
  RenderTaskRunner,
  RendererScheduler,
} from '../main/ets/services/RendererScheduler';

class RecordingRenderTaskRunner implements RenderTaskRunner {
  public renderedTasks: RenderTask[] = [];
  public workDurationMs: number = 1;

  render(task: RenderTask, complete: RenderTaskCompletionHandler): void {
    this.renderedTasks.push(task);
    const completion: RenderTaskCompletion = {
      blockId: task.blockId,
      height: task.estimateHeight + 10,
      workDurationMs: this.workDurationMs,
    };
    complete(completion);
  }
}

class DeferredRenderTaskRunner implements RenderTaskRunner {
  public renderedTasks: RenderTask[] = [];
  public callbacks: RenderTaskCompletionHandler[] = [];
  private queuedTasks: RenderTask[] = [];

  render(task: RenderTask, complete: RenderTaskCompletionHandler): void {
    this.renderedTasks.push(task);
    this.queuedTasks.push(task);
    this.callbacks.push(complete);
  }

  completeNext(): void {
    const callback: RenderTaskCompletionHandler | undefined = this.callbacks.shift();
    const task: RenderTask | undefined = this.queuedTasks.shift();
    if (callback === undefined || task === undefined) {
      return;
    }
    const completion: RenderTaskCompletion = {
      blockId: task.blockId,
      height: task.estimateHeight + 12,
      workDurationMs: 10,
    };
    callback(completion);
  }
}

const makeTask = (blockId: string, distanceToViewportScreens: number): RenderTask => {
  return {
    blockId: blockId,
    rawFormulaText: '$$' + blockId + '$$',
    slotHint: 'slot-' + blockId,
    estimateHeight: 40,
    distanceToViewportScreens: distanceToViewportScreens,
  };
};

export default function rendererSchedulerTest(): void {
  describe('RendererScheduler.issue140_priority', () => {
    it('dispatches_visible_then_nearby_and_defers_far_tasks', 0, () => {
      const runner: RecordingRenderTaskRunner = new RecordingRenderTaskRunner();
      const completions: RenderTaskCompletion[] = [];
      const scheduler: RendererScheduler = new RendererScheduler(runner,
        (blockId: string, height: number): void => {
          completions.push({ blockId: blockId, height: height, workDurationMs: 0 });
        });

      scheduler.enqueue(makeTask('far', 2));
      scheduler.enqueue(makeTask('near', 1));
      scheduler.enqueue(makeTask('visible', 0));

      scheduler.dispatchPending();
      expect(runner.renderedTasks.length).assertEqual(1);
      expect(runner.renderedTasks[0].blockId).assertEqual('visible');
      expect(completions.length).assertEqual(1);

      scheduler.dispatchPending();
      expect(runner.renderedTasks.length).assertEqual(2);
      expect(runner.renderedTasks[1].blockId).assertEqual('near');

      scheduler.dispatchPending();
      expect(runner.renderedTasks.length).assertEqual(2);
      expect(scheduler.hasEligiblePending()).assertFalse();
      expect(scheduler.hasPending()).assertTrue();
      scheduler.updateViewportDistance('far', 1);
      scheduler.dispatchPending();
      expect(runner.renderedTasks.length).assertEqual(3);
      scheduler.dispose();
    });

    it('checks_the_work_budget_after_each_completed_unit', 0, () => {
      const runner: RecordingRenderTaskRunner = new RecordingRenderTaskRunner();
      runner.workDurationMs = 10;
      const changedBlockIds: string[] = [];
      const scheduler: RendererScheduler = new RendererScheduler(runner,
        (blockId: string, _height: number): void => { changedBlockIds.push(blockId); }, 3, 16);

      scheduler.enqueue(makeTask('first', 0));
      scheduler.enqueue(makeTask('second', 0));
      scheduler.enqueue(makeTask('third', 0));
      scheduler.dispatchPending();

      expect(runner.renderedTasks.length).assertEqual(2);
      expect(changedBlockIds.join(',')).assertEqual('first,second');
      expect(scheduler.pendingCount()).assertEqual(1);

      scheduler.dispatchPending();
      expect(runner.renderedTasks.length).assertEqual(3);
      expect(changedBlockIds.join(',')).assertEqual('first,second,third');
      scheduler.dispose();
    });

    it('ignores_late_completion_after_dispose', 0, () => {
      const runner: DeferredRenderTaskRunner = new DeferredRenderTaskRunner();
      const changedBlockIds: string[] = [];
      const scheduler: RendererScheduler = new RendererScheduler(runner,
        (blockId: string, _height: number): void => { changedBlockIds.push(blockId); });
      scheduler.enqueue(makeTask('late', 0));
      scheduler.dispatchPending();
      scheduler.dispose();
      const completion: RenderTaskCompletion = {
        blockId: 'late',
        height: 100,
        workDurationMs: 1,
      };
      runner.callbacks[0](completion);
      expect(changedBlockIds.length).assertEqual(0);
    });

    it('requests_another_tick_after_an_async_unit_completes_with_pending_work', 0, () => {
      const runner: DeferredRenderTaskRunner = new DeferredRenderTaskRunner();
      const pendingRequests: number[] = [];
      const changedBlockIds: string[] = [];
      const scheduler: RendererScheduler = new RendererScheduler(runner,
        (blockId: string, _height: number): void => { changedBlockIds.push(blockId); },
        1, 16, (): void => { pendingRequests.push(1); });

      scheduler.enqueue(makeTask('first', 0));
      scheduler.enqueue(makeTask('second', 0));
      expect(scheduler.dispatchPending()).assertTrue();
      expect(runner.renderedTasks.length).assertEqual(1);
      runner.completeNext();
      expect(changedBlockIds.join(',')).assertEqual('first');
      expect(pendingRequests.length).assertEqual(1);
      scheduler.dispatchPending();
      expect(runner.renderedTasks.length).assertEqual(2);
      scheduler.dispose();
    });
  });
}
