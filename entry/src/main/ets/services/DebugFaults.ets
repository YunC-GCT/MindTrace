/**
 * DebugFaults.ets — 流式故障注入开关（仅调试用，默认 none）
 *
 * 路径: entry/src/main/ets/services/DebugFaults.ets
 * 职责: 为 #224 的两条恢复分支（reason=empty / reason=interrupted）提供真机可重复的注入源；
 *       用 preferences 持久化当前故障档位，并在模块内缓存，供 ReplyService.stream() 同步读取。
 * 依赖: @kit.ArkData preferences; common Logger
 *
 * 数据流:
 *   AiSettingsPage（隐藏入口） → DebugFaults.set() → preferences(mindtrace_debug)
 *   ReplyService.stream() → DebugFaults.load()（首次懒加载） → DebugFaults.current() → 注入
 *
 * 生产安全:
 *   - 默认值恒为 'none'；load/set 的任何异常都不会抛出到调用方。
 *   - 'none' 时 ReplyService 原样返回，行为与未接入前完全一致。
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式 Promise/void 返回类型；不用 any/unknown/解构。
 *   - getContext() 声明为 Context，但文档说明异步链路上可能取不到；这里按可空处理并降级为 none。
 */
import { preferences } from '@kit.ArkData';
import { Logger } from 'common';

export type DebugFault = 'none' | 'empty' | 'interrupted';

const STORE_NAME: string = 'mindtrace_debug';
const KEY_FAULT: string = 'stream_fault';
const NONE: DebugFault = 'none';

const debugLog: Logger = new Logger('DebugFaults');

export class DebugFaults {
  private static cached: DebugFault = NONE;
  // ready: 本进程已确定过档位（成功读盘、成功写盘、或确认拿不到 Context）。
  private static ready: boolean = false;
  // contextMissing: 上次无参 load() 没拿到 Context；后续页面显式传入 Context 时应重试读盘。
  private static contextMissing: boolean = false;
  private static store: preferences.Preferences | null = null;
  private static ctx: Context | undefined = undefined;

  /** 同步读取当前档位（ReplyService 在返回前调用，不能 await）。 */
  static current(): DebugFault {
    return DebugFaults.cached;
  }

  /**
   * 首次调用时从 preferences 读取档位；之后直接返回模块缓存。
   * @param context 页面可显式传入 getContext(this)，服务侧无参调用时回退到全局 getContext()。
   */
  static async load(context?: Context): Promise<DebugFault> {
    const explicit: boolean = context !== undefined;
    if (explicit) {
      DebugFaults.ctx = context;
    }
    if (DebugFaults.ready && !(explicit && DebugFaults.contextMissing)) {
      return DebugFaults.cached;
    }
    try {
      const ctx: Context | undefined = DebugFaults.ensureContext(context);
      if (ctx === undefined) {
        // 拿不到 Context（例如异步调用链无法回溯页面）：本进程按 none 处理，不阻塞聊天。
        DebugFaults.cached = NONE;
        DebugFaults.contextMissing = true;
        DebugFaults.ready = true;
        debugLog.warn('[DebugFault] context unavailable, fallback=none');
        return DebugFaults.cached;
      }
      const store: preferences.Preferences = await preferences.getPreferences(ctx, STORE_NAME);
      const raw: string = await store.get(KEY_FAULT, NONE) as string;
      DebugFaults.store = store;
      DebugFaults.cached = DebugFaults.normalize(raw);
      DebugFaults.contextMissing = false;
      DebugFaults.ready = true;
      debugLog.info('[DebugFault] loaded=' + DebugFaults.cached);
    } catch (_e) {
      // 持久化不可用不能影响生产：退回 none。
      DebugFaults.cached = NONE;
      DebugFaults.contextMissing = false;
      DebugFaults.ready = true;
      debugLog.warn('[DebugFault] load failed, fallback=none');
    }
    return DebugFaults.cached;
  }
  /** 切换档位：先更新模块缓存（立即生效），再尽力持久化。 */
  static async set(v: DebugFault): Promise<void> {
    const next: DebugFault = DebugFaults.normalize(v);
    DebugFaults.cached = next;
    DebugFaults.ready = true;
    DebugFaults.contextMissing = false;
    try {
      let store: preferences.Preferences | null = DebugFaults.store;
      if (store === null) {
        const ctx: Context | undefined = DebugFaults.ensureContext(undefined);
        if (ctx === undefined) {
          debugLog.warn('[DebugFault] set=' + next + ' memory-only (context unavailable)');
          return;
        }
        store = await preferences.getPreferences(ctx, STORE_NAME);
        DebugFaults.store = store;
      }
      await store.put(KEY_FAULT, next);
      await store.flush();
      debugLog.info('[DebugFault] set=' + next);
    } catch (_e) {
      // 写盘失败仍保留本进程缓存，保证本次调试可复现。
      debugLog.warn('[DebugFault] set=' + next + ' memory-only (persist failed)');
    }
  }

  private static ensureContext(context?: Context): Context | undefined {
    if (context !== undefined) {
      return context;
    }
    if (DebugFaults.ctx !== undefined) {
      return DebugFaults.ctx;
    }
    const resolved: Context | undefined = getContext() as Context | undefined;
    if (resolved !== undefined) {
      DebugFaults.ctx = resolved;
    }
    return resolved;
  }

  private static normalize(value: string): DebugFault {
    if (value === 'empty') {
      return 'empty';
    }
    if (value === 'interrupted') {
      return 'interrupted';
    }
    return NONE;
  }
}
