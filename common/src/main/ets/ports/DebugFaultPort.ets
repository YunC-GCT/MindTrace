/**
 * DebugFaultPort.ets — 流式故障注入的只读端口
 *
 * 路径: common/src/main/ets/ports/DebugFaultPort.ets
 * 职责: 让回复链路在不依赖 preferences / Context 的前提下读取调试档位；
 *       实现留在 entry（DebugFaults），由组合根注入
 * 依赖: 无
 *
 * 数据流:
 *   entry DebugFaults（preferences） → 实现 DebugFaultSource → 注入 ReplyService
 *
 * 生产安全: 未注入时调用方按 'none' 处理，行为与未接入前一致
 */
export type DebugFault = 'none' | 'empty' | 'interrupted';

export interface DebugFaultSource {
  /** 首次读取档位；实现方需自行保证失败不抛出。 */
  load(): Promise<DebugFault>;
  /** 同步读取当前档位（回复返回前调用，不能 await）。 */
  current(): DebugFault;
}
