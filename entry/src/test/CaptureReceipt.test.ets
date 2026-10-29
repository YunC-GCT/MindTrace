/**
 * CaptureReceipt.test.ets — 批量整理回执文案与意图判定
 *
 * 路径: entry/src/test/CaptureReceipt.test.ets
 * 职责: 覆盖 formatReceipt 的 null / 24h 内 / 超过 24h 三种分支、24h 边界，
 *       以及 matchesReceiptIntent 的命中与不命中关键词。
 * 依赖: @ohos/hypium; services/CaptureReceipt
 *
 * 数据流: 固定时间戳与 CaptureReceipt fixture → formatReceipt / matchesReceiptIntent → expect
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  CaptureReceipt,
  formatReceipt,
  matchesReceiptIntent,
} from '../main/ets/services/CaptureReceipt';

const HOUR_MS: number = 60 * 60 * 1000;

/** 默认 fixture：成功 2、失败 1、共 3；at/source 由调用方按场景给 */
function receiptAt(at: number, source: string): CaptureReceipt {
  const receipt: CaptureReceipt = {
    done: 2,
    failed: 1,
    total: 3,
    at: at,
    source: source,
  };
  return receipt;
}

export default function captureReceiptTest(): void {
  describe('CaptureReceipt.formatReceipt', () => {
    it('should explain the batch entry when there is no receipt', 0, () => {
      expect(formatReceipt(null, 1761363131000))
        .assertEqual('还没有整理记录，先在 MindTrace 里用「+ → 批量」选图。');
    });

    it('should report this run with total, done, failed and HH:mm within 24h', 0, () => {
      const at: number = new Date(2026, 9, 25, 9, 5, 0).getTime();
      const now: number = at + 2 * HOUR_MS;
      expect(formatReceipt(receiptAt(at, 'batch'), now))
        .assertEqual('本次整理 3 条：成功 2 条，失败 1 条（09:05）。');
    });

    it('should report the last run in whole hours beyond 24h', 0, () => {
      const now: number = new Date(2026, 9, 26, 10, 0, 0).getTime();
      const at: number = now - 25 * HOUR_MS;
      expect(formatReceipt(receiptAt(at, 'debug'), now))
        .assertEqual('最近一次整理是 25 小时前：成功 2 条，失败 1 条。');
    });
  });

  describe('CaptureReceipt.24h_boundary', () => {
    it('should keep the this-run wording at 24h minus one minute', 0, () => {
      const at: number = new Date(2026, 9, 25, 9, 5, 0).getTime();
      const now: number = at + 24 * HOUR_MS - 60 * 1000;
      expect(formatReceipt(receiptAt(at, 'batch'), now)).assertContain('本次整理 3 条');
    });

    it('should switch to the last-run wording at 25h', 0, () => {
      const at: number = new Date(2026, 9, 24, 9, 5, 0).getTime();
      const now: number = at + 25 * HOUR_MS;
      expect(formatReceipt(receiptAt(at, 'batch'), now)).assertContain('最近一次整理是 25 小时前');
    });
  });

  describe('CaptureReceipt.matchesReceiptIntent', () => {
    it('should match 整理了几条', 0, () => {
      expect(matchesReceiptIntent('刚才总共整理了几条呀')).assertTrue();
    });

    it('should match the keyword after whitespace is stripped', 0, () => {
      expect(matchesReceiptIntent('本 次 整 理 了 几 条')).assertTrue();
    });

    it('should match 整理结果', 0, () => {
      expect(matchesReceiptIntent('看看整理结果')).assertTrue();
    });

    it('should not match a generic 整理一下 request', 0, () => {
      expect(matchesReceiptIntent('整理一下这道题')).assertFalse();
    });

    it('should not match 本次总结', 0, () => {
      expect(matchesReceiptIntent('本次总结')).assertFalse();
    });

    it('should not match an unrelated 错题本 request', 0, () => {
      expect(matchesReceiptIntent('帮我整理错题本')).assertFalse();
    });
  });
}
