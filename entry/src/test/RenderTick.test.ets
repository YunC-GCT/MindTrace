/**
 * RenderTick.test.ets — RenderTick 生命周期与阶段顺序测试
 *
 * 路径: entry/src/test/RenderTick.test.ets
 * 职责: 验证按需启动、延迟首 tick、显示暂停、销毁和单实例保护。
 * 依赖: Hypium, RenderTick
 *
 * 数据流:
 *   fake timer/handlers → RenderTick → 可观察阶段事件
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 fake classes，避免无类型对象字面量。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  RenderTick,
  RenderTickOptions,
  RenderTickPhaseHandlers,
  RenderTickTimer,
  TICK_MS,
} from '../main/ets/services/RenderTick';

class RecordingTimer implements RenderTickTimer {
  public startCount: number = 0;
  public stopCount: number = 0;
  public lastIntervalMs: number = 0;
  private nextTimerId: number = 0;
  private callback: (() => void) | undefined = undefined;

  start(callback: () => void, intervalMs: number): number {
    this.startCount += 1;
    this.lastIntervalMs = intervalMs;
    this.nextTimerId += 1;
    this.callback = callback;
    return this.nextTimerId;
  }

  stop(_timerId: number): void {
    this.stopCount += 1;
  }

  fire(): void {
    const callback: (() => void) | undefined = this.callback;
    if (callback !== undefined) {
      callback();
    }
  }
}

class RecordingHandlers implements RenderTickPhaseHandlers {
  public events: string[] = [];
  public active: boolean = true;
  public pendingStateCount: number = 0;
  public disconnectCount: number = 0;

  isSubscriberActive(): boolean {
    return this.active;
  }

  updatePendingState(): void {
    this.pendingStateCount += 1;
  }

  disconnectSubscriber(): void {
    this.disconnectCount += 1;
  }

  notifyData(): void {
    this.events.push('data');
  }

  notifyGeometry(): void {
    this.events.push('geometry');
  }

  handleScroll(): void {
    this.events.push('scroll');
  }
}

export default function renderTickTest(): void {
  describe('RenderTick.issue140_lifecycle', () => {
    it('starts_only_for_pending_work_and_runs_one_ordered_delayed_tick', 0, () => {
      const timer: RecordingTimer = new RecordingTimer();
      const handlers: RecordingHandlers = new RecordingHandlers();
      const tick: RenderTick = new RenderTick(handlers, timer);

      expect(TICK_MS).assertEqual(50);
      expect(tick.isRunning()).assertFalse();
      tick.requestTick();
      expect(timer.startCount).assertEqual(1);
      expect(timer.lastIntervalMs).assertEqual(TICK_MS);
      expect(handlers.events.length).assertEqual(0);

      timer.fire();
      expect(handlers.events.join(',')).assertEqual('data,geometry,scroll');
      expect(handlers.pendingStateCount).assertEqual(1);
      expect(timer.stopCount).assertEqual(1);
      expect(tick.isRunning()).assertFalse();
      tick.dispose();
      expect(handlers.disconnectCount).assertEqual(1);
    });

    it('reuses_the_instance_and_flushes_pending_work_before_hiding', 0, () => {
      const timer: RecordingTimer = new RecordingTimer();
      const handlers: RecordingHandlers = new RecordingHandlers();
      const tick: RenderTick = new RenderTick(handlers, timer);

      tick.requestTick();
      tick.setShow(false);
      expect(handlers.events.join(',')).assertEqual('data,geometry,scroll');
      expect(handlers.pendingStateCount).assertEqual(1);
      expect(timer.stopCount).assertEqual(1);
      expect(tick.isRunning()).assertFalse();
      expect(tick.hasPending()).assertFalse();

      tick.requestTick();
      expect(timer.startCount).assertEqual(1);
      tick.setShow(true);
      expect(timer.startCount).assertEqual(2);
      timer.fire();
      expect(handlers.events.join(',')).assertEqual('data,geometry,scroll,data,geometry,scroll');
      expect(handlers.pendingStateCount).assertEqual(2);
      tick.dispose();
      expect(handlers.disconnectCount).assertEqual(1);
    });

    it('keeps_document_tick_state_without_notifying_an_inactive_subscriber', 0, () => {
      const timer: RecordingTimer = new RecordingTimer();
      const handlers: RecordingHandlers = new RecordingHandlers();
      handlers.active = false;
      const tick: RenderTick = new RenderTick(handlers, timer);

      tick.requestTick();
      timer.fire();
      expect(handlers.events.length).assertEqual(0);
      expect(handlers.pendingStateCount).assertEqual(1);
      expect(tick.isRunning()).assertFalse();
      tick.dispose();
    });

    it('disposes_the_timer_and_ignores_late_or_new_pending_work', 0, () => {
      const timer: RecordingTimer = new RecordingTimer();
      const handlers: RecordingHandlers = new RecordingHandlers();
      const tick: RenderTick = new RenderTick(handlers, timer);

      tick.requestTick();
      tick.dispose();
      timer.fire();
      tick.requestTick();
      expect(tick.isDisposed()).assertTrue();
      expect(timer.startCount).assertEqual(1);
      expect(handlers.events.length).assertEqual(0);
      expect(handlers.disconnectCount).assertEqual(1);
    });
  });

  describe('RenderTick.issue140_single_instance', () => {
    it('rejects_a_second_live_instance_in_every_build_path_without_side_effects', 0, () => {
      const firstTimer: RecordingTimer = new RecordingTimer();
      const firstHandlers: RecordingHandlers = new RecordingHandlers();
      const first: RenderTick = new RenderTick(firstHandlers, firstTimer);
      let releaseRejected: boolean = false;
      let releaseErrorMessage: string = '';
      const releaseTimer: RecordingTimer = new RecordingTimer();
      const releaseHandlers: RecordingHandlers = new RecordingHandlers();
      try {
        const second: RenderTick = new RenderTick(releaseHandlers, releaseTimer);
        second.requestTick();
      } catch (e) {
        releaseRejected = true;
        releaseErrorMessage = (e as Error).message;
      }
      expect(releaseRejected).assertTrue();
      expect(releaseErrorMessage).assertEqual('Only one RenderTick instance is supported');
      expect(releaseTimer.startCount).assertEqual(0);
      expect(releaseTimer.stopCount).assertEqual(0);
      expect(releaseHandlers.disconnectCount).assertEqual(0);

      let developmentRejected: boolean = false;
      let developmentErrorMessage: string = '';
      const developmentTimer: RecordingTimer = new RecordingTimer();
      const developmentHandlers: RecordingHandlers = new RecordingHandlers();
      try {
        const developmentOptions: RenderTickOptions = { developmentGuard: true };
        const second: RenderTick = new RenderTick(developmentHandlers, developmentTimer, developmentOptions);
        second.requestTick();
      } catch (e) {
        developmentRejected = true;
        developmentErrorMessage = (e as Error).message;
      }
      expect(developmentRejected).assertTrue();
      expect(developmentErrorMessage).assertEqual('Only one RenderTick instance is supported');
      expect(developmentTimer.startCount).assertEqual(0);
      expect(developmentTimer.stopCount).assertEqual(0);
      expect(developmentHandlers.disconnectCount).assertEqual(0);
      first.requestTick();
      firstTimer.fire();
      expect(firstHandlers.events.join(',')).assertEqual('data,geometry,scroll');
      first.dispose();

      const replacementTimer: RecordingTimer = new RecordingTimer();
      const replacementHandlers: RecordingHandlers = new RecordingHandlers();
      const replacement: RenderTick = new RenderTick(replacementHandlers, replacementTimer);
      replacement.requestTick();
      replacementTimer.fire();
      replacement.dispose();
      expect(replacementHandlers.disconnectCount).assertEqual(1);
    });
  });
}
