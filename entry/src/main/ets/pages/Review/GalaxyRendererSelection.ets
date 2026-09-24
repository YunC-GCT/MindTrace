// ============================================================================
//  pages/Review/GalaxyRendererSelection.ets - renderer fallback policy
// ============================================================================

export type GalaxyRendererMode = 'native' | 'web' | 'fallback'

export type GalaxyRendererEvent =
  'native_ready' | 'native_failure' | 'web_ready' | 'web_failure'

export function chooseInitialGalaxyRenderer(nativeCapable: boolean): GalaxyRendererMode {
  return nativeCapable ? 'native' : 'web'
}

export function nextGalaxyRendererMode(
  current: GalaxyRendererMode,
  event: GalaxyRendererEvent,
): GalaxyRendererMode {
  if (current === 'native') {
    return event === 'native_failure' ? 'web' : 'native'
  }
  if (current === 'web') {
    return event === 'web_failure' ? 'fallback' : 'web'
  }
  return 'fallback'
}
