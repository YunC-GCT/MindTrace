/**
 * A2AConstants.ets — 小艺端A2A 的共享常量
 *
 * 路径: entry/src/main/ets/services/A2AConstants.ets
 * 职责: 日志域/标签与整理 deadline；控制器与整理处理器共用，避免两处各写一份
 * 依赖: 无
 *
 * 数据流: A2AController / A2AIngestHandler → hilog 与超时判断
 */
export const TAG: string = 'MindTraceA2A';
export const DOMAIN: number = 0xA2A0;
export const INGEST_DEADLINE_MS: number = 90000;
