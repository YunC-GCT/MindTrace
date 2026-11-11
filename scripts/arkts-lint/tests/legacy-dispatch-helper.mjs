// A4 4c Step4 过渡工具：旧 `dispatcher.dispatch(request, options)` 的测试替身。
// 把 BranchRequest 反向映射成 NoteCommand 走命令 seam，再用 LegacyDispatchAdapter 还原 DispatchResult 外观，
// 供尚未迁移的 baseline / golden 测试在旧入口删除后继续锁定「旧外观」。
let seq = 0;

// NoteOutcome → 旧 DispatchResult 外观（原 agents/LegacyDispatchAdapter 迁到测试侧；Step 3 生产不再需要）。
export function toLegacyDispatchResult(outcome) {
  const result = {
    success: outcome.kind === 'committed' || outcome.kind === 'readyPreview',
    route: 'D1',
    durationMs: outcome.durationMs,
  };
  if (outcome.unit !== undefined) {
    result.data = outcome.unit;
  } else if (outcome.draft !== undefined) {
    result.data = outcome.draft;
  }
  if (outcome.classification !== undefined) { result.classification = outcome.classification; }
  if (outcome.recognizedText !== undefined) { result.recognizedText = outcome.recognizedText; }
  if (outcome.generation !== undefined) { result.generation = outcome.generation; }
  if (outcome.kind === 'failed') {
    const code = outcome.code !== undefined ? outcome.code : '';
    if (code.length > 0) { result.errorCode = code; }
    result.errorMessage = outcome.message;
    if (outcome.retryable !== undefined) { result.errorRetryable = outcome.retryable; }
  } else if (outcome.kind === 'needsInput') {
    result.errorMessage = outcome.reason;
    if (outcome.generation !== undefined) { result.generation = outcome.generation; }
  } else if (outcome.kind === 'cancelled') {
    result.errorCode = 'CANCELLED';
    result.errorMessage = 'CONVERSATION_CANCELLED';
    result.cancelledCommitted = outcome.committed === true;
    if (outcome.noteId !== undefined) { result.cancelledNoteId = outcome.noteId; }
    if (outcome.version !== undefined) { result.cancelledVersion = outcome.version; }
    if (outcome.commitKey !== undefined) { result.cancelledCommitKey = outcome.commitKey; }
  }
  return result;
}

export async function dispatchLegacy(runtime, request, options = {}) {
  const regenerating = request.generation !== undefined && request.generation.mode === 'regenerate';
  let kind = 'capture';
  if (request.preparedCandidate !== undefined) {
    kind = 'preparedCandidate';
  } else if (request.generation !== undefined) {
    kind = regenerating ? 'regenerate' : 'generation';
  } else if (options.analysisOnly === true) {
    kind = 'analysisOnly';
  }
  const command = {
    kind: kind,
    operationId: 'legacy-op-' + (++seq),
    source: request.source !== undefined ? request.source : 'app',
    payload: request.payload,
  };
  if (request.preparedCandidate !== undefined) {
    command.preparedCandidate = request.preparedCandidate;
  }
  if (request.generation !== undefined) {
    command.generation = request.generation;
  }
  if (options.includeRawText === true) {
    command.includeRawText = true;
  }
  const outcome = await runtime.dispatcher.dispatchCommand(command, options);
  // 旧 dispatch() 语义：取消以异常结束（入口取消 / capture 图内取消均抛错）。
  if (outcome.kind === 'cancelled') {
    throw new Error('CONVERSATION_CANCELLED');
  }
  return toLegacyDispatchResult(outcome);
}
