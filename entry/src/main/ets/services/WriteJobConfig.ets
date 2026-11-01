/**
 * WriteJobConfig.ets — 调度器灰度配置（spec 038 S2）
 *
 * 路径: entry/src/main/ets/services/WriteJobConfig.ets
 * 职责: 只允许 UI 进程在启动时按此配置打开调度器；A2A 扩展进程（:agent）不读此配置，保持默认关闭。
 * 依赖: 无
 * 数据流: EntryAbility.onCreate() → WRITE_JOB_UI_ENABLED → WriteJobFlags.setEnabled()
 */
export const WRITE_JOB_UI_ENABLED: boolean = true;
// spec 040 P1：持久队列开关（默认关；P3 真机验收后再打开）。
export const WRITE_JOB_PERSIST_ENABLED: boolean = false;
