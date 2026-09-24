// ============================================================================
//  pages/Review/GalaxyRendererContracts.ets - shared 3D renderer seam
// ============================================================================

import type { GalaxyGraphSnapshot } from './GalaxyGraphProjection'

export class GalaxyPerformanceSample {
  renderer: string = ''
  fps: number = 0
  particles: number = 0
  degraded: boolean = false

  constructor(renderer: string, fps: number, particles: number, degraded: boolean) {
    this.renderer = renderer
    this.fps = fps
    this.particles = particles
    this.degraded = degraded
  }
}

export interface GalaxyRendererCallbacks {
  onReady(): void
  onSelect(id: string): void
  onClearSelection(): void
  onFailure(reason: string): void
  onPerformance(sample: GalaxyPerformanceSample): void
}

export interface GalaxyRendererAdapter {
  setSnapshot(snapshot: GalaxyGraphSnapshot): void
  setSelection(id: string): void
  resetCamera(): void
  pause(): void
  resume(): void
  release(): void
}

export class GalaxyRendererCallbackSet implements GalaxyRendererCallbacks {
  private readyHandler: () => void
  private selectHandler: (id: string) => void
  private clearSelectionHandler: () => void
  private failureHandler: (reason: string) => void
  private performanceHandler: (sample: GalaxyPerformanceSample) => void

  constructor(
    readyHandler: () => void,
    selectHandler: (id: string) => void,
    clearSelectionHandler: () => void,
    failureHandler: (reason: string) => void,
    performanceHandler: (sample: GalaxyPerformanceSample) => void,
  ) {
    this.readyHandler = readyHandler
    this.selectHandler = selectHandler
    this.clearSelectionHandler = clearSelectionHandler
    this.failureHandler = failureHandler
    this.performanceHandler = performanceHandler
  }

  onReady(): void {
    this.readyHandler()
  }

  onSelect(id: string): void {
    this.selectHandler(id)
  }

  onClearSelection(): void {
    this.clearSelectionHandler()
  }

  onFailure(reason: string): void {
    this.failureHandler(reason)
  }

  onPerformance(sample: GalaxyPerformanceSample): void {
    this.performanceHandler(sample)
  }
}

export class GalaxyNoopCallbacks implements GalaxyRendererCallbacks {
  onReady(): void {}
  onSelect(_id: string): void {}
  onClearSelection(): void {}
  onFailure(_reason: string): void {}
  onPerformance(_sample: GalaxyPerformanceSample): void {}
}
