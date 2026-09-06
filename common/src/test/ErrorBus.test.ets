// MindTrace - ErrorBus 行为测试 (评审前 1.5 项 / fix/demo-polish-2026-09-06)
//
// 测试 ErrorBus.publish/subscribe 的核心契约, 不测 UI 渲染 (UI 测试需 DevEco GUI):
//   - 订阅者收到 publish 的事件
//   - unsubscribe 后不再收到
//   - 多订阅者全部收到 (fanout)
//   - severity / action / cause 透传
//
// 配套 ErrorBanner UI 测试在 DevEco GUI 跑 — 本套件作为 Node/Hypium 守门。

import { describe, it, expect } from '@ohos/hypium';
import { AppError, ErrorBus } from '../main/ets/Index';

function makeError(title: string, message: string, severity: 'info' | 'warn' | 'error'): AppError {
  return new AppError({
    kind: 'UNKNOWN',
    severity: severity,
    title: title,
    message: message,
    action: 'none',
    timestamp: Date.now(),
  });
}

export default function errorBusTest(): void {
  describe('ErrorBus.publish/subscribe', () => {
    it('subscriber_receives_published_error', 0, () => {
      const received: AppError[] = [];
      const unsubscribe: () => void = ErrorBus.subscribe((err: AppError): void => {
        received.push(err);
      });
      const e: AppError = makeError('test', 'hello', 'info');
      ErrorBus.publish(e);
      expect(received.length).assertEqual(1);
      expect(received[0].title).assertEqual('test');
      unsubscribe();
    });

    it('unsubscribe_stops_delivery', 0, () => {
      const received: AppError[] = [];
      const unsubscribe: () => void = ErrorBus.subscribe((err: AppError): void => {
        received.push(err);
      });
      unsubscribe();
      ErrorBus.publish(makeError('after-un', 'should-not-arrive', 'warn'));
      expect(received.length).assertEqual(0);
    });

    it('multiple_subscribers_all_receive', 0, () => {
      const a: AppError[] = [];
      const b: AppError[] = [];
      const ua: () => void = ErrorBus.subscribe((err: AppError): void => { a.push(err); });
      const ub: () => void = ErrorBus.subscribe((err: AppError): void => { b.push(err); });
      ErrorBus.publish(makeError('multi', 'fanout', 'error'));
      expect(a.length).assertEqual(1);
      expect(b.length).assertEqual(1);
      ua();
      ub();
    });

    it('severity_preserved_through_bus', 0, () => {
      let got: AppError | null = null;
      const unsubscribe: () => void = ErrorBus.subscribe((err: AppError): void => { got = err; });
      ErrorBus.publish(makeError('sev', 'preserve', 'error'));
      expect(got?.severity).assertEqual('error');
      unsubscribe();
    });

    it('cause_round_trips_through_app_error_from', 0, () => {
      let got: AppError | null = null;
      const unsubscribe: () => void = ErrorBus.subscribe((err: AppError): void => { got = err; });
      const original: Error = new Error('underlying');
      const wrapped: AppError = AppError.from(original, {
        kind: 'NETWORK_TIMEOUT',
        severity: 'error',
        title: '超时',
        message: '请重试',
        action: 'retry',
        actionLabel: '重试',
        timestamp: Date.now(),
      });
      ErrorBus.publish(wrapped);
      expect(got?.kind).assertEqual('NETWORK_TIMEOUT');
      expect(got?.action).assertEqual('retry');
      expect(got?.cause).assertEqual(original);
      unsubscribe();
    });
  });
}
