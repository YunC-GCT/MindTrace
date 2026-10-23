/**
 * TaskSnapshot.ets — A2A 单帧 result.task 快照的纯字符串构造
 *
 * 路径: entry/src/main/ets/agentextability/TaskSnapshot.ets
 * 职责: 把请求 id / task id / 完整回答拼成一条可直接 sendData 的 JSON-RPC 2.0 响应。
 * 依赖: 无（纯函数，不 import 任何 Kit，也不读写外部状态）
 *
 * 数据流:
 *   AgentExtAbility.sendAnswer(taskId, text) -> buildTaskSnapshot() -> hostProxy.sendData()
 *
 * 为什么必须是单帧（真机实测，别再改成增量序列）:
 *   小艺对 SDK 的 statusUpdate / artifactUpdate 增量帧只渲染开头一两个词（实测「已」「好」「当前」），
 *   对一次给全 artifacts + TASK_STATE_COMPLETED 的单帧 result.task 才能完整渲染长文本
 *   （实测 263 字，含 Markdown / LaTeX）。响应形状与约束见
 *   docs/specs/032-model-gateway-and-a2a-runtime.md §2「A2A 响应契约」。
 *
 * 输出契约（与改造前 sendAnswer 的内联拼接逐字节一致）:
 *   contextId 固定 mindtrace-context；artifactId 为 <taskId>-artifact；
 *   parts 只放 text + mediaType，不引入客户端不认识的 part（未知 part 会让整条响应被丢弃）。
 */
const CONTEXT_ID: string = 'mindtrace-context';
const COMPLETED_STATE: string = 'TASK_STATE_COMPLETED';
const TEXT_MEDIA_TYPE: string = 'text/plain';

/**
 * 构造单帧 result.task 快照。纯函数：同样入参永远得到同样字符串，无副作用。
 *
 * 为什么必须是单帧：小艺对 statusUpdate / artifactUpdate 增量帧只渲染开头一两个词，
 * 只有一次给全 artifacts + TASK_STATE_COMPLETED 的 result.task 才能完整渲染长文本
 * （真机实测 263 字，含 Markdown / LaTeX）。契约见
 * docs/specs/032-model-gateway-and-a2a-runtime.md §2「A2A 响应契约」。
 *
 * JSON.stringify(text) 负责换行 / 引号 / 反斜杠转义，调用方拿到后一次 sendData。
 */
export function buildTaskSnapshot(requestId: string, taskId: string, text: string): string {
  return '{"jsonrpc":"2.0","id":"' + requestId
    + '","result":{"task":{"id":"' + taskId
    + '","contextId":"' + CONTEXT_ID
    + '","status":{"state":"' + COMPLETED_STATE + '"},"artifacts":[{"artifactId":"'
    + taskId + '-artifact","parts":[{"text":' + JSON.stringify(text)
    + ',"mediaType":"' + TEXT_MEDIA_TYPE + '"}]}]}}}';
}
