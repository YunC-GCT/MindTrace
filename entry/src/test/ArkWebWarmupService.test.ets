/**
 * ArkWebWarmupService.test.ets — ArkWeb warmup seam behavior tests
 *
 * 路径: entry/src/test/ArkWebWarmupService.test.ets
 * 职责: 执行 issue #119 公共测试 seam，覆盖 adapter 注入、reset、warmup 结果和前置状态查询。
 * 依赖: Hypium, @ohos.web.webview, ArkWebWarmupService
 *
 * 数据流:
 *   fake ArkWeb adapter -> ArkWebWarmupService.warmup() -> WarmupResult + BenchmarkBaselinePrecondition
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 classes/interfaces，避免无类型对象字面量。
 */

import { describe, it, expect } from '@ohos/hypium';
import webview from '@ohos.web.webview';
import {
  ArkWebPlatformAdapter,
  ArkWebWarmupService,
  BenchmarkBaselinePrecondition,
  WarmupResult,
} from '../main/ets/services/ArkWebWarmupService';

class RecordingArkWebAdapter implements ArkWebPlatformAdapter {
  public recordedModes: webview.RenderProcessMode[] = [];
  public renderProcessModeCalls: number = 0;
  public initializeCalls: number = 0;
  public callOrder: string[] = [];
  public failOnInitialize: boolean = false;

  setRenderProcessMode(mode: webview.RenderProcessMode): void {
    this.renderProcessModeCalls += 1;
    this.callOrder.push('setRenderProcessMode');
    this.recordedModes.push(mode);
  }

  initializeWebEngine(): void {
    this.initializeCalls += 1;
    this.callOrder.push('initializeWebEngine');
    if (this.failOnInitialize) {
      throw new Error('user content must not appear in diagnostics');
    }
  }
}

const installAdapter = (adapter: RecordingArkWebAdapter): void => {
  ArkWebWarmupService.resetForTest();
  ArkWebWarmupService.setPlatformAdapterForTest(adapter);
};

const assertSingleMode = (adapter: RecordingArkWebAdapter): void => {
  expect(adapter.recordedModes.length).assertEqual(1);
  expect(adapter.recordedModes[0]).assertEqual(webview.RenderProcessMode.SINGLE);
};

export default function arkWebWarmupServiceTest(): void {
  describe('ArkWebWarmupService.issue119_behavior', () => {
    it('sets_SINGLE_then_initializes_and_marks_precondition_valid', 0, () => {
      const adapter: RecordingArkWebAdapter = new RecordingArkWebAdapter();
      installAdapter(adapter);

      const result: WarmupResult = ArkWebWarmupService.warmup();
      const precondition: BenchmarkBaselinePrecondition = ArkWebWarmupService.getBenchmarkBaselinePrecondition();

      expect(result.success).assertTrue();
      expect(result.recoverable).assertFalse();
      assertSingleMode(adapter);
      expect(adapter.renderProcessModeCalls).assertEqual(1);
      expect(adapter.initializeCalls).assertEqual(1);
      expect(adapter.callOrder[0]).assertEqual('setRenderProcessMode');
      expect(adapter.callOrder[1]).assertEqual('initializeWebEngine');
      expect(precondition.state).assertEqual('valid');
      expect(precondition.diagnostic.indexOf('completed') >= 0).assertTrue();

      ArkWebWarmupService.resetForTest();
    });

    it('is_idempotent_after_success_without_repeating_platform_calls', 0, () => {
      const adapter: RecordingArkWebAdapter = new RecordingArkWebAdapter();
      installAdapter(adapter);

      const firstResult: WarmupResult = ArkWebWarmupService.warmup();
      const secondResult: WarmupResult = ArkWebWarmupService.warmup();
      const precondition: BenchmarkBaselinePrecondition = ArkWebWarmupService.getBenchmarkBaselinePrecondition();

      expect(firstResult.success).assertTrue();
      expect(firstResult.recoverable).assertFalse();
      expect(secondResult.success).assertTrue();
      expect(secondResult.recoverable).assertFalse();
      expect(secondResult.diagnostic).assertEqual(firstResult.diagnostic);
      assertSingleMode(adapter);
      expect(adapter.renderProcessModeCalls).assertEqual(1);
      expect(adapter.initializeCalls).assertEqual(1);
      expect(adapter.callOrder.length).assertEqual(2);
      expect(precondition.state).assertEqual('valid');
      expect(precondition.diagnostic).assertEqual(secondResult.diagnostic);

      ArkWebWarmupService.resetForTest();
    });

    it('marks_precondition_invalid_with_safe_metadata_when_adapter_fails', 0, () => {
      const adapter: RecordingArkWebAdapter = new RecordingArkWebAdapter();
      adapter.failOnInitialize = true;
      installAdapter(adapter);

      const result: WarmupResult = ArkWebWarmupService.warmup();
      const precondition: BenchmarkBaselinePrecondition = ArkWebWarmupService.getBenchmarkBaselinePrecondition();

      expect(result.success).assertFalse();
      expect(result.recoverable).assertTrue();
      assertSingleMode(adapter);
      expect(adapter.renderProcessModeCalls).assertEqual(1);
      expect(adapter.initializeCalls).assertEqual(1);
      expect(precondition.state).assertEqual('invalid');
      expect(precondition.diagnostic.indexOf('errorName=') >= 0).assertTrue();
      expect(precondition.diagnostic.indexOf('errorCode=') >= 0).assertTrue();
      expect(precondition.diagnostic.indexOf('user content') < 0).assertTrue();
      expect(precondition.diagnostic.indexOf('must not appear') < 0).assertTrue();

      ArkWebWarmupService.resetForTest();
    });

    it('retries_after_initial_failure_and_recovers_the_precondition', 0, () => {
      const adapter: RecordingArkWebAdapter = new RecordingArkWebAdapter();
      adapter.failOnInitialize = true;
      installAdapter(adapter);

      const failedResult: WarmupResult = ArkWebWarmupService.warmup();
      adapter.failOnInitialize = false;
      const recoveredResult: WarmupResult = ArkWebWarmupService.warmup();
      const precondition: BenchmarkBaselinePrecondition = ArkWebWarmupService.getBenchmarkBaselinePrecondition();

      expect(failedResult.success).assertFalse();
      expect(failedResult.recoverable).assertTrue();
      expect(recoveredResult.success).assertTrue();
      expect(recoveredResult.recoverable).assertFalse();
      expect(adapter.renderProcessModeCalls).assertEqual(2);
      expect(adapter.initializeCalls).assertEqual(2);
      expect(precondition.state).assertEqual('valid');

      ArkWebWarmupService.resetForTest();
    });
  });
}
