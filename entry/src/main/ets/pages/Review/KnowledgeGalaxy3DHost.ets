// ============================================================================
//  pages/Review/KnowledgeGalaxy3DHost.ets - Review galaxy renderer host
//  ----------------------------------------------------------------------------
//  Owns renderer selection, ViewModel refresh, business-ID selection and detail.
// ============================================================================

import {
  BG_DARK,
  F_SM,
  MINT,
  S_2,
  TEXT_3,
  KnowledgeUnit,
  NoteItem,
} from 'common'
import { promptAction } from '@kit.ArkUI'
import { NoteDetailOverlay } from '../../overlays/NoteDetailOverlay/NoteDetailOverlay'
import {
  KnowledgeGalaxyViewModel,
  PlanetNode,
} from '../../viewmodels/KnowledgeGalaxyViewModel'
import { unitToNoteItem } from '../../utils/NoteItemMapper'
import { GalaxyComponent3DAdapter } from './GalaxyComponent3DAdapter'
import { GalaxyGraphSnapshot, projectGalaxyGraph } from './GalaxyGraphProjection'
import type { GalaxyRendererEvent, GalaxyRendererMode } from './GalaxyRendererSelection'
import { chooseInitialGalaxyRenderer, nextGalaxyRendererMode } from './GalaxyRendererSelection'
import {
  GalaxyPerformanceSample,
  GalaxyRendererCallbackSet,
  GalaxyRendererCallbacks,
} from './GalaxyRendererContracts'
import { GalaxyWebAdapter } from './GalaxyWebAdapter'
import { ReviewGraphView } from './ReviewGraphView'

@Component
export struct KnowledgeGalaxy3DHost {
  @StorageProp('notesVersion') @Watch('onNotesVersionChange') notesVersion: number = 0
  @State private vm: KnowledgeGalaxyViewModel = new KnowledgeGalaxyViewModel()
  @State private snapshot: GalaxyGraphSnapshot = { nodes: [], edges: [] }
  @State private rendererMode: GalaxyRendererMode = 'web'
  @State private rendererReady: boolean = false
  @State private loading: boolean = true
  @State private loadFailed: boolean = false
  @State private selectedId: string = ''
  @State private selectedNote: NoteItem | null = null
  @State private selectedUnit: KnowledgeUnit | null = null
  @State private paused: boolean = false
  @State private viewportWidth: number = 360
  @State private viewportHeight: number = 520
  @State private performance: GalaxyPerformanceSample = new GalaxyPerformanceSample('', 0, 0, false)
  onGoAI: () => void = (): void => {}

  private nativeCallbacks: GalaxyRendererCallbacks = new GalaxyRendererCallbackSet(
    (): void => this.handleRendererEvent('native_ready'),
    (id: string): void => this.openById(id),
    (): void => this.clearSelection(),
    (reason: string): void => this.handleRendererFailure('native_failure', reason),
    (sample: GalaxyPerformanceSample): void => { this.performance = sample },
  )

  private webCallbacks: GalaxyRendererCallbacks = new GalaxyRendererCallbackSet(
    (): void => this.handleRendererEvent('web_ready'),
    (id: string): void => this.openById(id),
    (): void => this.clearSelection(),
    (reason: string): void => this.handleRendererFailure('web_failure', reason),
    (sample: GalaxyPerformanceSample): void => { this.performance = sample },
  )

  aboutToAppear(): void {
    this.paused = false
    this.rendererMode = chooseInitialGalaxyRenderer(this.hasNativeCapability())
    this.reloadGalaxy(false)
  }

  aboutToDisappear(): void {
    this.paused = true
  }

  onPageShow(): void {
    this.paused = false
  }

  onPageHide(): void {
    this.paused = true
  }

  onNotesVersionChange(): void {
    this.reloadGalaxy(true)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.rendererMode === 'native') {
        GalaxyComponent3DAdapter({
          snapshot: this.snapshot,
          selectedId: this.selectedId,
          paused: this.paused,
          viewportWidth: this.viewportWidth,
          viewportHeight: this.viewportHeight,
          callbacks: this.nativeCallbacks,
        })
      } else if (this.rendererMode === 'web') {
        GalaxyWebAdapter({
          snapshot: this.snapshot,
          selectedId: this.selectedId,
          paused: this.paused,
          callbacks: this.webCallbacks,
        })
      } else {
        ReviewGraphView({ onGoAI: this.onGoAI })
      }

      if (this.loading || (this.rendererMode !== 'fallback' && !this.rendererReady)) {
        Column({ space: S_2 }) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(MINT)
          Text('正在加载知识星系')
            .fontSize(F_SM)
            .fontColor(TEXT_3)
        }
        .alignItems(HorizontalAlign.Center)
      }

      if (this.selectedNote !== null) {
        NoteDetailOverlay({
          note: this.selectedNote!,
          unit: this.selectedUnit,
          units: this.vm.units,
          onClose: this.closeDetail,
          onDelete: this.deleteNote,
          onSaved: this.handleSaved,
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(BG_DARK)
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.viewportWidth = Number(newValue.width)
      this.viewportHeight = Number(newValue.height)
    })
  }

  private reloadGalaxy(keepSelection: boolean): void {
    this.loading = true
    this.loadFailed = false
    this.vm.load(getContext(this)).then((ok: boolean): void => {
      this.loading = false
      this.loadFailed = !ok
      if (!ok) {
        try { promptAction.showToast({ message: '知识星系加载失败', duration: 1500 }) } catch (_error) {}
        return
      }
      this.snapshot = projectGalaxyGraph(this.vm.systems)
      if (!keepSelection || this.findPlanet(this.selectedId) === null) {
        this.clearSelection()
      }
    }).catch((_error: Error): void => {
      this.loading = false
      this.loadFailed = true
      try { promptAction.showToast({ message: '知识星系加载失败', duration: 1500 }) } catch (_toastError) {}
    })
  }

  private handleRendererEvent(event: GalaxyRendererEvent): void {
    const nextMode: GalaxyRendererMode = nextGalaxyRendererMode(this.rendererMode, event)
    if (nextMode !== this.rendererMode) {
      this.rendererMode = nextMode
      this.rendererReady = false
      return
    }
    if ((event === 'native_ready' && this.rendererMode === 'native')
      || (event === 'web_ready' && this.rendererMode === 'web')) {
      this.rendererReady = true
    }
  }

  private handleRendererFailure(event: GalaxyRendererEvent, reason: string): void {
    const currentMode: GalaxyRendererMode = this.rendererMode
    this.handleRendererEvent(event)
    if (currentMode === 'web' && this.rendererMode === 'fallback') {
      try {
        promptAction.showToast({ message: '三维星系加载失败，已切换兼容视图', duration: 1800 })
      } catch (_error) {}
      console.warn('[KnowledgeGalaxy3DHost] Web renderer failed: ' + reason)
    } else if (currentMode === 'native' && this.rendererMode === 'web') {
      console.info('[KnowledgeGalaxy3DHost] Native renderer unavailable: ' + reason)
    }
  }

  private openById(id: string): void {
    const planet: PlanetNode | null = this.findPlanet(id)
    if (planet === null) {
      return
    }
    this.selectedId = planet.id
    this.selectedNote = planet.note
    this.selectedUnit = planet.unit
    this.vm.loadNote(getContext(this), planet.id).then((unit: KnowledgeUnit | null): void => {
      if (unit !== null && this.selectedId === planet.id) {
        this.selectedUnit = unit
      }
    })
  }

  private clearSelection(): void {
    this.selectedId = ''
  }

  private closeDetail = (): void => {
    this.selectedNote = null
    this.selectedUnit = null
    this.clearSelection()
  }

  private handleSaved = (unit: KnowledgeUnit): void => {
    this.selectedId = unit.id
    this.selectedNote = unitToNoteItem(unit)
    this.selectedUnit = unit
    this.reloadGalaxy(true)
  }

  private deleteNote = async (id: string): Promise<void> => {
    const ok: boolean = await this.vm.deleteNote(getContext(this), id)
    if (!ok) {
      try { promptAction.showToast({ message: '删除笔记失败', duration: 1500 }) } catch (_error) {}
      return
    }
    this.closeDetail()
    this.snapshot = projectGalaxyGraph(this.vm.systems)
    const version: number = AppStorage.get<number>('notesVersion') ?? 0
    AppStorage.setOrCreate('notesVersion', version + 1)
    try { promptAction.showToast({ message: '已删除笔记', duration: 1200 }) } catch (_error) {}
  }

  private findPlanet(id: string): PlanetNode | null {
    if (id.length === 0) {
      return null
    }
    for (const system of this.vm.systems) {
      const planet: PlanetNode | undefined = system.planets.find(
        (candidate: PlanetNode): boolean => candidate.id === id,
      )
      if (planet !== undefined) {
        return planet
      }
    }
    return null
  }

  private hasNativeCapability(): boolean {
    try {
      return canIUse('SystemCapability.ArkUi.Graphics3D')
    } catch (_error) {
      return false
    }
  }
}
