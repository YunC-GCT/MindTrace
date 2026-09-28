/**
 * NoteDetailBenchmarkLaunch.ets — NoteDetail 设备基准启动契约
 *
 * 路径: entry/src/main/ets/services/NoteDetailBenchmarkLaunch.ets
 * 职责: 将显式 benchmark URI 转为默认关闭的确定性运行配置。
 * 依赖: NoteDetailRenderFixtures.
 *
 * 数据流:
 *   EntryAbility Want URI -> fromUri() -> AppStorage -> Index benchmark host
 *
 * ArkTS 1.1 strict:
 *   - 不读取动态 Want parameters；只解析白名单 URI token。
 *   - 所有未知值回落到固定离线 fixture，不触发网络或持久化。
 */

import {
  NoteDetailFixtureId,
  NoteDetailLengthProfile,
  NoteDetailRendererFamily,
} from './NoteDetailRenderFixtures'

export const NOTE_DETAIL_BENCHMARK_CONFIG_KEY: string = 'noteDetailBenchmarkConfig'
export const NOTE_DETAIL_BENCHMARK_URI_PREFIX: string = 'mindtrace://note-detail-benchmark'

export class NoteDetailBenchmarkLaunchConfig {
  enabled: boolean
  fixtureId: NoteDetailFixtureId
  rendererFamily: NoteDetailRendererFamily
  lengthProfile: NoteDetailLengthProfile
  aiHelperVisible: boolean
  webKeepAliveEnabled: boolean

  constructor(enabled: boolean, fixtureId: NoteDetailFixtureId,
    rendererFamily: NoteDetailRendererFamily, lengthProfile: NoteDetailLengthProfile,
    aiHelperVisible: boolean, webKeepAliveEnabled: boolean) {
    this.enabled = enabled
    this.fixtureId = fixtureId
    this.rendererFamily = rendererFamily
    this.lengthProfile = lengthProfile
    this.aiHelperVisible = aiHelperVisible
    this.webKeepAliveEnabled = webKeepAliveEnabled
  }

  public static disabled(): NoteDetailBenchmarkLaunchConfig {
    return new NoteDetailBenchmarkLaunchConfig(false, 'A', '概念', 'long', false, false)
  }

  public static fromUri(uri: string): NoteDetailBenchmarkLaunchConfig {
    if (!uri.startsWith(NOTE_DETAIL_BENCHMARK_URI_PREFIX)) {
      return NoteDetailBenchmarkLaunchConfig.disabled()
    }
    const fixtureId: NoteDetailFixtureId = NoteDetailBenchmarkLaunchConfig.fixtureFromUri(uri)
    return new NoteDetailBenchmarkLaunchConfig(
      true,
      fixtureId,
      NoteDetailBenchmarkLaunchConfig.rendererFromUri(uri, fixtureId),
      uri.includes('length=short') ? 'short' : 'long',
      uri.includes('ai=1'),
      uri.includes('keepAlive=1'),
    )
  }

  private static fixtureFromUri(uri: string): NoteDetailFixtureId {
    if (uri.includes('fixture=C_P')) { return 'C_P' }
    if (uri.includes('fixture=C')) { return 'C' }
    if (uri.includes('fixture=B')) { return 'B' }
    return 'A'
  }

  private static rendererFromUri(uri: string,
    fixtureId: NoteDetailFixtureId): NoteDetailRendererFamily {
    if (uri.includes('renderer=theorem')) { return '定理' }
    if (uri.includes('renderer=formula')) { return '公式' }
    if (uri.includes('renderer=proof')) { return '证明题' }
    if (uri.includes('renderer=computation')) { return '计算题' }
    if (uri.includes('renderer=fallback')) { return '兜底' }
    if (uri.includes('renderer=concept')) { return '概念' }
    if (fixtureId === 'C_P') { return '证明题' }
    if (fixtureId === 'B' || fixtureId === 'C') { return '公式' }
    return '概念'
  }
}
