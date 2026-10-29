/**
 * CaptureReceipt.ets — 批量整理回执的落盘与查询文案
 *
 * 路径: entry/src/main/ets/services/CaptureReceipt.ets
 * 职责: 保存/读取最近一次批量整理结果（<filesDir>/receipts/last-capture.json），
 *       并判定小艺的回执意图、生成固定中文回执文案。
 * 依赖: @kit.AbilityKit (common.Context)、@kit.CoreFileKit (fileIo)
 *
 * 数据流:
 *   AgentFloatWindow.onBatchAction / DebugCaptureRunner.run → CaptureReceiptStore.save()
 *     → <filesDir>/receipts/last-capture.json
 *   AgentExtAbility.handleQuery → matchesReceiptIntent(query)
 *     → CaptureReceiptStore.read() → formatReceipt(receipt, Date.now()) → sendAnswer()
 *
 * 设计要点:
 *   - 文件只有几十字节，用同步文件读写而不是 preferences（:agent 进程 preferences 可能不返回）。
 *   - read() 对文件不存在 / JSON 非法 / 字段缺失一律返回 null，只拒绝坏数据，不抛给调用方。
 *   - 文案与意图判定是纯函数，便于单测；落盘路径固定为 receipts/last-capture.json。
 *
 * ArkTS 1.1 strict 适配:
 *   - JSON.parse 结果显式 cast 为 CaptureReceipt | null，不使用 any/unknown。
 *   - catch 变量不标注类型，错误信息用 instanceof Error 收窄后再取 message。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';

/** 最近一次批量整理的结果快照 */
export interface CaptureReceipt {
  done: number;
  failed: number;
  total: number;
  /** 写入时间，Date.now() 毫秒时间戳 */
  at: number;
  /** 触发来源：'batch' | 'debug' */
  source: string;
}

/** 24 小时：超过后回执改说「最近一次」 */
const RECEIPT_FRESH_MS: number = 24 * 60 * 60 * 1000;
const RECEIPTS_DIR_NAME: string = 'receipts';
const RECEIPT_FILE_NAME: string = 'last-capture.json';

/** 本地回执意图关键词：去空格后 includes 任一即命中，不花 token */
const RECEIPT_KEYWORDS: string[] = [
  '整理了几条',
  '整理多少',
  '本次整理',
  '刚才整理',
  '几条笔记',
  '整理结果',
  '回执',
];

export class CaptureReceiptStore {
  /** 落盘路径：<filesDir>/receipts/last-capture.json */
  private static receiptPath(context: common.Context): string {
    return context.filesDir + '/' + RECEIPTS_DIR_NAME + '/' + RECEIPT_FILE_NAME;
  }

  /** 目录不存在时先建；文件内容固定为 JSON.stringify(receipt) */
  static async save(context: common.Context, receipt: CaptureReceipt): Promise<void> {
    const dir: string = context.filesDir + '/' + RECEIPTS_DIR_NAME;
    if (!fileIo.accessSync(dir)) {
      fileIo.mkdirSync(dir, true);
    }
    const path: string = CaptureReceiptStore.receiptPath(context);
    const file: fileIo.File = fileIo.openSync(
      path,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC,
    );
    try {
      fileIo.writeSync(file.fd, JSON.stringify(receipt));
    } finally {
      fileIo.closeSync(file);
    }
  }

  /** 任何失败都返回 null（文件不存在 / JSON 非法 / 字段缺失），只 warn 不抛 */
  static async read(context: common.Context): Promise<CaptureReceipt | null> {
    const path: string = CaptureReceiptStore.receiptPath(context);
    try {
      if (!fileIo.accessSync(path)) {
        console.warn('[CaptureReceipt] read failed: file not found');
        return null;
      }
      const raw: string = fileIo.readTextSync(path);
      const parsed: CaptureReceipt | null = JSON.parse(raw) as CaptureReceipt | null;
      if (parsed === null || !CaptureReceiptStore.isValid(parsed)) {
        console.warn('[CaptureReceipt] read failed: invalid json or fields');
        return null;
      }
      return parsed;
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      console.warn('[CaptureReceipt] read failed: ' + message);
      return null;
    }
  }

  /** 五个字段都必须存在且类型正确，缺一即视为坏数据 */
  private static isValid(receipt: CaptureReceipt): boolean {
    return typeof receipt.done === 'number'
      && typeof receipt.failed === 'number'
      && typeof receipt.total === 'number'
      && typeof receipt.at === 'number'
      && typeof receipt.source === 'string';
  }
}

/** 固定文案：null / 24h 内 / 超过 24h 三种分支 */
export function formatReceipt(receipt: CaptureReceipt | null, now: number): string {
  if (receipt === null) {
    return '还没有整理记录，先在 MindTrace 里用「+ → 批量」选图。';
  }
  const elapsed: number = now - receipt.at;
  if (elapsed <= RECEIPT_FRESH_MS) {
    return '本次整理 ' + receipt.total.toString() + ' 条：成功 ' + receipt.done.toString()
      + ' 条，失败 ' + receipt.failed.toString() + ' 条（' + formatClock(receipt.at) + '）。';
  }
  // 超过 24h 仍给数字，不装作刚发生；至少显示 1 小时
  const hours: number = Math.max(1, Math.round(elapsed / 3600000));
  return '最近一次整理是 ' + hours.toString() + ' 小时前：成功 ' + receipt.done.toString()
    + ' 条，失败 ' + receipt.failed.toString() + ' 条。';
}

/** HH:mm，两位补零；用本地时区，与用户读 Toast 的时钟一致 */
function formatClock(at: number): string {
  const date: Date = new Date(at);
  const hour: string = date.getHours().toString().padStart(2, '0');
  const minute: string = date.getMinutes().toString().padStart(2, '0');
  return hour + ':' + minute;
}

/** 回执意图：去空格后包含任一关键词即命中 */
export function matchesReceiptIntent(text: string): boolean {
  const normalized: string = text.replace(/\s/g, '');
  for (const keyword of RECEIPT_KEYWORDS) {
    if (normalized.includes(keyword)) {
      return true;
    }
  }
  return false;
}
