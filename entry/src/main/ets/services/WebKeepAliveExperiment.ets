/**
 * WebKeepAliveExperiment.ets — WebKeepAlive A/B 实验开关
 *
 * 路径: entry/src/main/ets/services/WebKeepAliveExperiment.ets
 * 职责: 通过 AppStorage 暴露默认关闭的可逆实验入口，供目标设备 A/B 采集使用。
 * 依赖: ArkUI AppStorage
 *
 * 数据流:
 *   device harness → configure() → AppStorage → Index root conditional mount
 *
 * ArkTS 1.1 strict 适配:
 *   - 只暴露布尔开关，不使用动态对象或索引签名。
 */

export const WEB_KEEP_ALIVE_EXPERIMENT_KEY: string = 'webKeepAliveExperimentEnabled'

export class WebKeepAliveExperiment {
  public static configure(enabled: boolean): void {
    AppStorage.setOrCreate(WEB_KEEP_ALIVE_EXPERIMENT_KEY, enabled)
  }

  public static isEnabled(): boolean {
    return AppStorage.get<boolean>(WEB_KEEP_ALIVE_EXPERIMENT_KEY) ?? false
  }
}
