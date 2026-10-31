/**
 * DispatchGraph.ets — Dispatcher 主图骨架（A4 切片 3）
 *
 * 路径: agents/src/main/ets/core/dispatch/DispatchGraph.ets
 * 职责: 定义 `preflight → route → invoke → verify → hitl → publish` 六阶段主图的推进语义：
 *       阶段实现返回 `{ next }` 继续、返回 `{ outcome }` 终止、返回 `{ error }` 走兜底失败。
 *       本片只提供**骨架与推进器**，capture 分支的实际迁移在切片 3b（保持旧 dispatch 输出不变）。
 * 依赖: 仅 common 的 NoteOutcome / NoteCommand 类型。
 *
 * 边界:
 *   - 主图不直接执行业务：每个阶段由调用方注入 handler，骨架只负责顺序、短路与阶段校验。
 *   - 阶段顺序固定；handler 显式 `next` 只允许前进（防止回跳造成死循环），非法跳转抛 NODE_ERROR 等价错误。
 *   - 退出条件唯一：拿到 `outcome`（五个终态之一）即结束。
 */
import type { NoteCommand, NoteOutcome } from 'common';

export type DispatchStage = 'preflight' | 'route' | 'invoke' | 'verify' | 'hitl' | 'publish';

export const DISPATCH_STAGE_ORDER: DispatchStage[] = [
  'preflight',
  'route',
  'invoke',
  'verify',
  'hitl',
  'publish',
];

// 阶段上下文：命令 + 调用方选项 + 前置阶段产出的中间值（不跨类型系统，保持 ArkTS 简单）。
export interface DispatchGraphContext {
  command: NoteCommand;
  runId: string;
  stage: DispatchStage;
}

// 阶段返回：next 继续；outcome 终止；error 走兜底失败（code/retryable 由 handler 给）。
export interface DispatchStageResult {
  next?: DispatchStage;
  outcome?: NoteOutcome;
  errorCode?: string;
  errorMessage?: string;
  retryable?: boolean;
}

export interface DispatchStageHandlers {
  preflight: (context: DispatchGraphContext) => Promise<DispatchStageResult>;
  route: (context: DispatchGraphContext) => Promise<DispatchStageResult>;
  invoke: (context: DispatchGraphContext) => Promise<DispatchStageResult>;
  verify: (context: DispatchGraphContext) => Promise<DispatchStageResult>;
  hitl: (context: DispatchGraphContext) => Promise<DispatchStageResult>;
  publish: (context: DispatchGraphContext) => Promise<DispatchStageResult>;
}

const DISPATCH_GRAPH_ERROR_INVALID_STAGE: string = 'INVALID_DISPATCH_STAGE';
const DISPATCH_GRAPH_ERROR_NO_TERMINAL: string = 'DISPATCH_GRAPH_NO_TERMINAL';

export class DispatchGraphError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = 'DispatchGraphError';
    this.code = code;
  }
}

export class DispatchGraph {
  /** 按固定顺序推进六个阶段；返回唯一终态。 */
  static async run(
    command: NoteCommand,
    handlers: DispatchStageHandlers,
    startedAt: number,
    fallbackOutcome: (code: string, message: string, retryable: boolean) => NoteOutcome,
  ): Promise<NoteOutcome> {
    let index: number = 0;
    while (index < DISPATCH_STAGE_ORDER.length) {
      const stage: DispatchStage = DISPATCH_STAGE_ORDER[index];
      const context: DispatchGraphContext = { command: command, runId: command.operationId, stage: stage };
      const result: DispatchStageResult = await DispatchGraph.callStage(stage, handlers, context);
      if (result.outcome !== undefined) {
        return result.outcome;
      }
      if (result.errorCode !== undefined) {
        const message: string = result.errorMessage !== undefined ? result.errorMessage : result.errorCode;
        return fallbackOutcome(result.errorCode, message, result.retryable === true);
      }
      if (result.next === undefined) {
        throw new DispatchGraphError(DISPATCH_GRAPH_ERROR_NO_TERMINAL,
          'stage ' + stage + ' returned neither outcome nor next');
      }
      if (result.next !== DISPATCH_STAGE_ORDER[index + 1]) {
        throw new DispatchGraphError(DISPATCH_GRAPH_ERROR_INVALID_STAGE,
          'stage ' + stage + ' may only advance to ' + (DISPATCH_STAGE_ORDER[index + 1] ?? 'END')
          + ', got ' + result.next);
      }
      index += 1;
    }
    throw new DispatchGraphError(DISPATCH_GRAPH_ERROR_NO_TERMINAL,
      'graph finished without terminal outcome after ' + (Date.now() - startedAt).toString() + 'ms');
  }

  private static async callStage(
    stage: DispatchStage,
    handlers: DispatchStageHandlers,
    context: DispatchGraphContext,
  ): Promise<DispatchStageResult> {
    if (stage === 'preflight') { return await handlers.preflight(context); }
    if (stage === 'route') { return await handlers.route(context); }
    if (stage === 'invoke') { return await handlers.invoke(context); }
    if (stage === 'verify') { return await handlers.verify(context); }
    if (stage === 'hitl') { return await handlers.hitl(context); }
    return await handlers.publish(context);
  }
}
