// A4 4c Step4 过渡工具：旧 `dispatcher.dispatch(request, options)` 的测试替身。
// 把 BranchRequest 反向映射成 NoteCommand 走命令 seam，再用 LegacyDispatchAdapter 还原 DispatchResult 外观，
// 供尚未迁移的 baseline / golden 测试在旧入口删除后继续锁定「旧外观」。
import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

const adapterModule = loadNoteReviewEtsModule('agents/src/main/ets/core/dispatch/LegacyDispatchAdapter.ets');
const LegacyDispatchAdapter = adapterModule.LegacyDispatchAdapter;

let seq = 0;

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
  return LegacyDispatchAdapter.toDispatchResult(outcome);
}
