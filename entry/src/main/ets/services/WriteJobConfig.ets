/**
 * WriteJobConfig.ets — 调度器灰度配置（spec 038 S2）
 *
 * 路径: entry/src/main/ets/services/WriteJobConfig.ets
 * 职责: 只允许 UI 进程在启动时按此配置打开调度器；A2A 扩展进程（:agent）不读此配置，保持默认关闭。
 * 依赖: 无
 */
export const WRITE_JOB_UI_ENABLED: boolean = true;

export function uiProcessEnabled(): boolean {
  return WRITE_JOB_UI_ENABLED;
}
