/**
 * BatchSupport.ets — dispatchSet 批量编排的纯辅助（从 CommandExecutor.ets 抽出）
 *
 * 路径: agents/src/main/ets/core/dispatch/BatchSupport.ets
 * 职责: 取消判定 / 跳过项回执 / 共享 RunContext 的选项逐字段复制。
 * 依赖: DispatchOptions（同目录）、common 类型（仅类型）。
 */

import type { CancellationToken, CaptureSetItemResult, DispatchPayload } from 'common';
import type { RunContext } from 'common';
import type { DispatchOptions } from './DispatchOptions';

export function isBatchCancelled(options: DispatchOptions): boolean {
  const token: CancellationToken | undefined = options.cancellationToken;
  return token !== undefined && token.isCancelled();
}

export function skippedItem(index: number, payload: DispatchPayload): CaptureSetItemResult {
  return { index: index, kind: payload.kind, success: false, cancelled: true, durationMs: 0 };
}

// 逐字段搬运而不是 {...options}：ArkTS 1.1 对对象展开有限制，且显式列举能让
// DispatchOptions 新增字段时在这里编译报错，而不是静默丢参数。
export function withRunContext(options: DispatchOptions, runContext: RunContext): DispatchOptions {
  const copy: DispatchOptions = {};
  copy.persist = options.persist;
  copy.includeRawText = options.includeRawText;
  copy.analysisOnly = options.analysisOnly;
  copy.dao = options.dao;
  copy.noteWritePort = options.noteWritePort;
  copy.generationRepository = options.generationRepository;
  copy.knowledgeModel = options.knowledgeModel;
  copy.cancellationToken = options.cancellationToken;
  copy.runContext = runContext;
  copy.progressSink = options.progressSink;
  copy.onNodeTiming = options.onNodeTiming;
  copy.subjectVocabulary = options.subjectVocabulary;
  return copy;
}
