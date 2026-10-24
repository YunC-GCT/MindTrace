// ============================================================================
//  pages/Review/GalaxyRendererSelection.ets - renderer fallback policy
//  路径: entry/src/main/ets/pages/Review/GalaxyRendererSelection.ets
//  职责: 选择星系渲染器并处理失败状态；临时固定使用 Web。
// ============================================================================

// Temporary device-validation choice. Keep native implementation available;
// restore this flag only after native visual acceptance.
const ENABLE_NATIVE_GALAXY: boolean = false

// unavailable is an error state, not a third renderer.
export type GalaxyRendererMode = 'native' | 'web' | 'unavailable'

export type GalaxyRendererEvent =
  'native_ready' | 'native_failure' | 'web_ready' | 'web_failure'

export function chooseInitialGalaxyRenderer(nativeCapable: boolean): GalaxyRendererMode {
  return ENABLE_NATIVE_GALAXY && nativeCapable ? 'native' : 'web'
}

export function nextGalaxyRendererMode(
  current: GalaxyRendererMode,
  event: GalaxyRendererEvent,
): GalaxyRendererMode {
  if (current === 'native') {
    return event === 'native_failure' ? 'web' : 'native'
  }
  if (current === 'web') {
    return event === 'web_failure' ? 'unavailable' : 'web'
  }
  return 'unavailable'
}
