// ============================================================================
//  pages/Review/GalaxyRendererSelection.ets - renderer fallback policy
// ============================================================================

// unavailable is an error state, not a third renderer.
export type GalaxyRendererMode = 'native' | 'web' | 'unavailable'

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
    return event === 'web_failure' ? 'unavailable' : 'web'
  }
  return 'unavailable'
}
