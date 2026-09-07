import {
  BG_CARD, BG_DARK, BORDER, GLASS_10, MINT, TEXT, TEXT_2, TEXT_3,
  F_BASE, F_LG, F_SM, F_XS,
  R_FULL, R_LG, R_MD,
  S_2, S_3, S_4, S_5,
  W_BOLD, W_SEMIBOLD,
  KnowledgeUnit, NoteItem,
} from "common"
import { promptAction } from "@kit.ArkUI"
import { AppIcon } from "../../shared/atoms/AppIcon"
import { NoteDetailOverlay } from "../../overlays/NoteDetailOverlay/NoteDetailOverlay"
import {
  ChapterOrbit,
  GalaxyLink,
  KnowledgeGalaxyViewModel,
  PlanetNode,
  SubjectSystem,
} from "../../viewmodels/KnowledgeGalaxyViewModel"
import { unitToNoteItem } from "../../utils/NoteItemMapper"

const GALAXY_SIZE: number = 360
const GALAXY_CENTER: number = GALAXY_SIZE / 2
const UNIVERSE_WIDTH: number = 360
const UNIVERSE_HEIGHT: number = 520
const UNIVERSE_MIN_WORLD_WIDTH: number = UNIVERSE_WIDTH * 2
const UNIVERSE_MIN_WORLD_HEIGHT: number = UNIVERSE_HEIGHT * 2
const UNIVERSE_SUBJECT_HIT_SIZE: number = 44
const UNIVERSE_WRAP_OFFSETS: number[] = [-1, 0, 1]
const UNIVERSE_DEFAULT_ZOOM: number = 0.82
const UNIVERSE_MIN_ZOOM: number = 0.6
const UNIVERSE_MAX_ZOOM: number = 4.2
const UNIVERSE_ZOOM_STEP: number = 0.35
const UNIVERSE_STAR_INDEXES: number[] = [
  0, 1, 2, 3, 4, 5, 6, 7,
  8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23,
  24, 25, 26, 27, 28, 29, 30, 31,
  32, 33, 34, 35, 36, 37, 38, 39,
]
const MIN_ZOOM: number = 0.75
const MAX_ZOOM: number = 3
const ZOOM_STEP: number = 0.25

function pctText(value: number): string {
  return Math.round(value * 100).toString() + "%"
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value))
}

function wrapCoordinate(value: number, size: number): number {
  if (size <= 0) {
    return 0
  }
  let next: number = value % size
  if (next < 0) {
    next += size
  }
  return next
}

function universeColumns(count: number): number {
  if (count <= 1) {
    return 1
  }
  return Math.max(2, Math.ceil(Math.sqrt(count * 1.25)))
}

function universeRows(count: number): number {
  if (count <= 1) {
    return 1
  }
  return Math.ceil(count / universeColumns(count))
}

function universeWorldWidth(count: number): number {
  return Math.max(UNIVERSE_MIN_WORLD_WIDTH, universeColumns(count) * 280)
}

function universeWorldHeight(count: number): number {
  return Math.max(UNIVERSE_MIN_WORLD_HEIGHT, universeRows(count) * 260 + 220)
}

function stableHash(value: string): number {
  let hash: number = 17
  let index: number = 0
  while (index < value.length) {
    hash = (hash * 31 + value.charCodeAt(index)) % 2147483647
    index++
  }
  return Math.abs(hash)
}

function paletteColor(seed: number, offset: number): string {
  const colors: string[] = [
    "#F6C56D", "#F08A5D", "#D96C75", "#9DD8FF",
    "#6FE7D2", "#A99BFF", "#E8D8A8", "#7FB8FF",
    "#C786F0", "#8BE09B", "#D9A27E", "#8C9EFF",
  ]
  return colors[Math.abs(seed + offset) % colors.length]
}

function planetVariant(id: string): number {
  return stableHash(id) % 6
}

function planetBaseColor(id: string): string {
  return paletteColor(stableHash(id), 0)
}

function planetAccentColor(id: string): string {
  return paletteColor(stableHash(id), 5)
}

function planetLabel(planet: PlanetNode): string {
  const title: string = planet.note.title.trim()
  if (title.length > 0) {
    return title
  }
  const type: string = planet.type.trim()
  return type.length > 0 ? type : "笔记"
}

@Component
export struct ReviewGraphView {
  @StorageProp("notesVersion") @Watch("onNotesVersionChange") notesVersion: number = 0
  @State vm: KnowledgeGalaxyViewModel = new KnowledgeGalaxyViewModel()
  @State selectedSubject: string = ""
  @State zoom: number = 1
  @State universeZoom: number = UNIVERSE_DEFAULT_ZOOM
  @State universeCameraX: number = UNIVERSE_MIN_WORLD_WIDTH / 2
  @State universeCameraY: number = UNIVERSE_MIN_WORLD_HEIGHT / 2
  @State orbitOffset: number = 0
  @State selectedNote: NoteItem | null = null
  @State selectedUnit: KnowledgeUnit | null = null
  @State focusedPlanetId: string = ""
  @State galaxyCameraOffsetX: number = 0
  @State galaxyCameraOffsetY: number = 0
  private timerId: number = -1
  onGoAI: () => void = (): void => {}

  aboutToAppear(): void {
    this.reloadGalaxy(false)
  }

  aboutToDisappear(): void {
    this.stopRotation()
  }

  onNotesVersionChange(): void {
    this.reloadGalaxy(true)
  }

  private reloadGalaxy(keepSelection: boolean): void {
    this.vm.load(getContext(this)).then((ok: boolean): void => {
      if (!ok) {
        try { promptAction.showToast({ message: "知识星系加载失败", duration: 1500 }) } catch (_e) {}
        this.stopRotation()
        return
      }
      if (!keepSelection || !this.hasSubject(this.selectedSubject)) {
        this.selectedSubject = ""
        this.zoom = 1
        this.resetUniverseViewport()
      } else {
        this.setUniverseCamera(this.universeCameraX, this.universeCameraY)
      }
      if (this.selectedSubject.length > 0 && this.selectedNote === null) {
        this.startRotation()
      } else {
        this.stopRotation()
      }
    })
  }

  private hasSubject(subject: string): boolean {
    if (subject.length === 0) {
      return true
    }
    for (const system of this.vm.systems) {
      if (system.subject === subject) {
        return true
      }
    }
    return false
  }

  private enterSubject(subject: string): void {
    animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, (): void => {
      this.selectedSubject = subject
      this.zoom = 1
      this.galaxyCameraOffsetX = 0
      this.galaxyCameraOffsetY = 0
      this.orbitOffset = 0
      this.startRotation()
    })
  }

  private leaveSubject(): void {
    this.stopRotation()
    animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
      this.selectedSubject = ""
      this.zoom = 1
      this.galaxyCameraOffsetX = 0
      this.galaxyCameraOffsetY = 0
      this.orbitOffset = 0
      this.selectedNote = null
      this.selectedUnit = null
      this.focusedPlanetId = ""
    })
  }

  private startRotation(): void {
    if (this.timerId !== -1 || this.selectedSubject.length === 0 || this.selectedNote !== null) {
      return
    }
    this.timerId = setInterval((): void => {
      this.orbitOffset = (this.orbitOffset + 2.2) % 360
    }, 800)
  }

  private stopRotation(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private openPlanet = (planet: PlanetNode): void => {
    this.stopRotation()
    this.focusedPlanetId = planet.id
    this.selectedNote = planet.note
    this.selectedUnit = planet.unit
    this.vm.loadNote(getContext(this), planet.id).then((unit: KnowledgeUnit | null): void => {
      if (this.selectedNote !== null && this.selectedNote.rawId === planet.id) {
        if (unit !== null) {
          this.selectedUnit = unit
        }
      }
    })
  }

  private hoverPlanet = (planetId: string): void => {
    if (this.selectedNote !== null) {
      return
    }
    this.focusPlanet(planetId)
  }

  private selectGalaxyPlanet = (planet: PlanetNode): void => {
    if (this.focusedPlanetId !== planet.id) {
      this.focusPlanet(planet.id)
      return
    }
    this.openPlanet(planet)
  }

  private focusPlanet(planetId: string): void {
    this.focusedPlanetId = planetId
    if (planetId.length > 0) {
      this.stopRotation()
    } else {
      this.startRotation()
    }
  }

  private closeDetail = (): void => {
    this.selectedNote = null
    this.selectedUnit = null
    this.focusedPlanetId = ""
    this.startRotation()
  }

  private handleSaved = (unit: KnowledgeUnit): void => {
    this.selectedNote = unitToNoteItem(unit)
    this.selectedUnit = unit
    this.focusedPlanetId = unit.id
    this.reloadGalaxy(true)
  }

  private deleteNote = async (id: string): Promise<void> => {
    const ok: boolean = await this.vm.deleteNote(getContext(this), id)
    if (ok) {
      this.selectedNote = null
      this.selectedUnit = null
      this.focusedPlanetId = ""
      if (this.hasSubject(this.selectedSubject)) {
        this.startRotation()
      }
      const v: number = AppStorage.get<number>("notesVersion") ?? 0
      AppStorage.setOrCreate("notesVersion", v + 1)
      try { promptAction.showToast({ message: "已删除笔记", duration: 1200 }) } catch (_e) {}
    } else {
      try { promptAction.showToast({ message: "删除笔记失败", duration: 1500 }) } catch (_e) {}
    }
  }

  private activeSystem(): SubjectSystem | null {
    for (const system of this.vm.systems) {
      if (system.subject === this.selectedSubject) {
        return system
      }
    }
    return null
  }

  private zoomIn(): void {
    animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
      const nextZoom: number = clamp(Math.round((this.zoom + ZOOM_STEP) * 100) / 100, MIN_ZOOM, MAX_ZOOM)
      this.zoom = nextZoom
      this.setGalaxyCameraOffset(this.galaxyCameraOffsetX, this.galaxyCameraOffsetY, nextZoom)
    })
  }

  private zoomOut(): void {
    animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
      const nextZoom: number = clamp(Math.round((this.zoom - ZOOM_STEP) * 100) / 100, MIN_ZOOM, MAX_ZOOM)
      this.zoom = nextZoom
      this.setGalaxyCameraOffset(this.galaxyCameraOffsetX, this.galaxyCameraOffsetY, nextZoom)
    })
  }

  private resetZoom(): void {
    animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
      this.zoom = 1
      this.galaxyCameraOffsetX = 0
      this.galaxyCameraOffsetY = 0
    })
  }

  private setGalaxyCameraOffset = (x: number, y: number, zoomValue: number = this.zoom): void => {
    const maxPan: number = this.galaxyMaxPan(zoomValue)
    this.galaxyCameraOffsetX = clamp(x, -maxPan, maxPan)
    this.galaxyCameraOffsetY = clamp(y, -maxPan, maxPan)
  }

  private galaxyMaxPan(zoomValue: number): number {
    return GALAXY_SIZE * Math.max(0, zoomValue - 1) * 0.5
  }

  private universeWidth(): number {
    return universeWorldWidth(this.vm.systems.length)
  }

  private universeHeight(): number {
    return universeWorldHeight(this.vm.systems.length)
  }

  private zoomUniverseIn(): void {
    animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
      this.universeZoom = clamp(Math.round((this.universeZoom + UNIVERSE_ZOOM_STEP) * 100) / 100,
        UNIVERSE_MIN_ZOOM, UNIVERSE_MAX_ZOOM)
    })
  }

  private zoomUniverseOut(): void {
    animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
      this.universeZoom = clamp(Math.round((this.universeZoom - UNIVERSE_ZOOM_STEP) * 100) / 100,
        UNIVERSE_MIN_ZOOM, UNIVERSE_MAX_ZOOM)
    })
  }

  private resetUniverseViewport(): void {
    animateTo({ duration: 180, curve: Curve.FastOutSlowIn }, (): void => {
      this.universeZoom = UNIVERSE_DEFAULT_ZOOM
      this.universeCameraX = this.universeWidth() / 2
      this.universeCameraY = this.universeHeight() / 2
    })
  }

  private setUniverseCamera = (x: number, y: number): void => {
    this.universeCameraX = wrapCoordinate(x, this.universeWidth())
    this.universeCameraY = wrapCoordinate(y, this.universeHeight())
  }

  build() {
    Stack() {
      Column() {
        if (this.vm.systems.length === 0) {
          this.EmptyState()
        } else if (this.selectedSubject.length === 0) {
          SubjectUniverseView({
            systems: this.vm.systems,
            totalCount: this.vm.totalCount,
            avgMastery: this.vm.avgMastery,
            zoom: this.universeZoom,
            cameraX: this.universeCameraX,
            cameraY: this.universeCameraY,
            onSelectSubject: (subject: string): void => this.enterSubject(subject),
            onSelectPlanet: this.openPlanet,
            onCameraChange: this.setUniverseCamera,
            onZoomIn: (): void => this.zoomUniverseIn(),
            onZoomOut: (): void => this.zoomUniverseOut(),
            onResetZoom: (): void => this.resetUniverseViewport(),
          })
        } else {
          this.SubjectHeader()
          SubjectGalaxyView({
            system: this.activeSystem(),
            zoom: this.zoom,
            orbitOffset: this.orbitOffset,
            focusedPlanetId: this.focusedPlanetId,
            cameraOffsetX: this.galaxyCameraOffsetX,
            cameraOffsetY: this.galaxyCameraOffsetY,
            onSelectPlanet: this.selectGalaxyPlanet,
            onHoverPlanet: this.hoverPlanet,
            onCameraChange: this.setGalaxyCameraOffset,
            onZoomIn: (): void => this.zoomIn(),
            onZoomOut: (): void => this.zoomOut(),
            onResetZoom: (): void => this.resetZoom(),
          })
        }
      }
      .width("100%")
      .layoutWeight(1)
      .backgroundColor(BG_DARK)

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
    .width("100%")
    .layoutWeight(1)
  }

  @Builder
  SubjectHeader() {
    Row() {
      Stack() {
        AppIcon({ name: "chevron-right", iconSize: 18, color: TEXT, strokeWidth: 1.8 })
          .rotate({ angle: 180 })
      }
      .width(38)
      .height(38)
      .borderRadius(R_FULL)
      .backgroundColor(GLASS_10)
      .onClick((): void => this.leaveSubject())

      Column() {
        Text(this.selectedSubject)
          .fontSize(F_LG)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width("100%")
        Text("轨道代表章节，行星代表笔记")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .maxLines(1)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: S_3 })
      .alignItems(HorizontalAlign.Start)
    }
    .width("100%")
    .padding({ left: S_5, right: S_5, top: S_2, bottom: S_2 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  EmptyState() {
    Column() {
      Blank()
      Stack() {
        Circle({ width: 150, height: 150 })
          .fill(MINT)
          .opacity(0.08)
          .shadow({ radius: 30, color: MINT, offsetX: 0, offsetY: 0 })
        Circle({ width: 94, height: 94 })
          .fill("#16FFFFFF")
          .stroke(MINT)
          .strokeWidth(1)
        AppIcon({ name: "ai", iconSize: 32, color: MINT, strokeWidth: 1.8 })
      }
      .width(174)
      .height(174)

      Text("还没有知识星系")
        .fontSize(F_LG)
        .fontWeight(W_BOLD)
        .fontColor(TEXT)
        .margin({ top: S_4 })

      Text("打开 AI 捕获第一条笔记，它会按学科和章节进入星系。")
        .fontSize(F_SM)
        .fontColor(TEXT_3)
        .textAlign(TextAlign.Center)
        .lineHeight(20)
        .width("78%")
        .margin({ top: S_2, bottom: S_4 })

      Button("打开 AI")
        .fontSize(F_SM)
        .fontWeight(W_SEMIBOLD)
        .fontColor(BG_DARK)
        .height(42)
        .padding({ left: 22, right: 22 })
        .borderRadius(R_FULL)
        .backgroundColor(MINT)
        .onClick((): void => this.onGoAI())

      Blank()
    }
    .width("100%")
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}

@Component
struct SubjectUniverseView {
  @Prop systems: SubjectSystem[] = []
  @Prop totalCount: number = 0
  @Prop avgMastery: number = 0
  @Prop zoom: number = 1
  @Prop cameraX: number = UNIVERSE_MIN_WORLD_WIDTH / 2
  @Prop cameraY: number = UNIVERSE_MIN_WORLD_HEIGHT / 2
  @State dragStartCameraX: number = 0
  @State dragStartCameraY: number = 0
  onSelectSubject: (subject: string) => void = (_subject: string): void => {}
  onSelectPlanet: (planet: PlanetNode) => void = (_planet: PlanetNode): void => {}
  onCameraChange: (x: number, y: number) => void = (_x: number, _y: number): void => {}
  onZoomIn: () => void = (): void => {}
  onZoomOut: () => void = (): void => {}
  onResetZoom: () => void = (): void => {}

  build() {
    Scroll() {
      Column() {
        this.UniverseViewport()

        this.ZoomControls()

        Row() {
          this.StatPill(this.systems.length.toString() + " 学科", "分组")
          this.StatPill(this.totalCount.toString() + " 笔记", "总量")
          this.StatPill(pctText(this.avgMastery), "掌握")
        }
        .width("100%")
        .padding({ left: S_5, right: S_5 })
        .justifyContent(FlexAlign.SpaceBetween)
        .margin({ top: S_2 })

        Text(this.zoomHint())
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .width("100%")
          .textAlign(TextAlign.Center)
          .margin({ top: S_4, bottom: 90 })
      }
      .width("100%")
    }
    .layoutWeight(1)
    .width("100%")
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  UniverseViewport() {
    Stack() {
      ForEach(UNIVERSE_WRAP_OFFSETS,
        (copyX: number): void => {
          ForEach(UNIVERSE_WRAP_OFFSETS,
            (copyY: number): void => {
              this.WorldTile(copyX, copyY)
            },
            (copyY: number): string => "overview_tile_y_" + copyY.toString()
          )
        },
        (copyX: number): string => "overview_tile_x_" + copyX.toString()
      )
    }
    .width(UNIVERSE_WIDTH)
    .height(UNIVERSE_HEIGHT)
    .clip(true)
    .alignSelf(ItemAlign.Center)
    .backgroundColor("#01000000")
    .margin({ top: S_2 })
    .priorityGesture(
      PanGesture({ direction: PanDirection.All })
        .onActionStart((_event: GestureEvent): void => {
          this.dragStartCameraX = this.cameraX
          this.dragStartCameraY = this.cameraY
        })
        .onActionUpdate((event: GestureEvent): void => {
          this.onCameraChange(
            this.dragStartCameraX - event.offsetX / this.zoom,
            this.dragStartCameraY - event.offsetY / this.zoom,
          )
        })
        .onActionEnd((): void => {
          this.dragStartCameraX = this.cameraX
          this.dragStartCameraY = this.cameraY
        })
    )
  }

  @Builder
  WorldTile(copyX: number, copyY: number) {
    Stack() {
      Image($r("app.media.galaxy_overview_bg"))
        .width("100%")
        .height("100%")
        .objectFit(ImageFit.Cover)
      Row()
        .width("100%")
        .height("100%")
        .backgroundColor("#A004070D")
      this.NebulaTrails()
      this.StarDust()
      ForEach(this.systems,
        (system: SubjectSystem): void => {
          this.SubjectSystemNode(system)
        },
        (system: SubjectSystem): string => system.subject
      )
    }
    .width(this.worldWidth())
    .height(this.worldHeight())
    .scale({ x: this.zoom, y: this.zoom })
    .position({
      x: this.worldTileScreenX(copyX),
      y: this.worldTileScreenY(copyY),
    })
  }

  @Builder
  SubjectSystemNode(system: SubjectSystem) {
    Stack() {
      if (this.showOrbitHints()) {
        ForEach(system.orbits,
          (orbit: ChapterOrbit, orbitIndex: number): void => {
            this.OverviewOrbit(system, orbit, orbitIndex)
          },
          (orbit: ChapterOrbit): string => system.subject + "_" + orbit.chapter + "_overview_orbit"
        )
      }

      Ellipse()
        .width(this.subjectVisualSize(system) * 2.9)
        .height(this.subjectVisualSize(system) * 0.86)
        .stroke(system.color)
        .strokeWidth(0.45)
        .opacity(0.20)
        .rotate({ angle: -18 })

      Ellipse()
        .width(this.subjectVisualSize(system) * 3.55)
        .height(this.subjectVisualSize(system) * 1.04)
        .stroke(system.color)
        .strokeWidth(0.45)
        .opacity(0.08 + system.mastery * 0.07)
        .rotate({ angle: 8 })

      Ellipse()
        .width(this.subjectVisualSize(system) * 2.08)
        .height(this.subjectVisualSize(system) * 0.58)
        .stroke(MINT)
        .strokeWidth(0.35)
        .opacity(0.11)
        .rotate({ angle: 22 })

      Circle({ width: this.subjectVisualSize(system) + 30, height: this.subjectVisualSize(system) + 30 })
        .fill(system.color)
        .opacity(0.035)

      Circle({ width: this.subjectVisualSize(system) + 18, height: this.subjectVisualSize(system) + 18 })
        .fill(system.color)
        .opacity(0.055)

      Circle({ width: this.subjectVisualSize(system), height: this.subjectVisualSize(system) })
        .fill(system.color)
        .opacity(0.18)

      Circle({ width: this.subjectVisualSize(system) * 0.54, height: this.subjectVisualSize(system) * 0.54 })
        .fill("#D8FFF3")
        .opacity(0.42)
        .stroke(system.color)
        .strokeWidth(0.7)

      this.SolarStar(system.color, this.subjectVisualSize(system) * 0.62, 0.76)

      this.SatelliteDot(system.color, this.subjectVisualSize(system) * 1.42, this.subjectVisualSize(system) * 0.46, 5, 0.68)
      this.SatelliteDot(MINT, this.subjectVisualSize(system) * 0.55, this.subjectVisualSize(system) * 1.18, 4, 0.54)
      this.SatelliteDot(TEXT_2, this.subjectVisualSize(system) * 1.24, this.subjectVisualSize(system) * 1.34, 3, 0.46)

      if (system.count >= 4) {
        this.SatelliteDot(system.color, this.subjectVisualSize(system) * 0.78, this.subjectVisualSize(system) * 0.34, 3, 0.46)
      }

      if (system.count >= 10) {
        this.SatelliteDot(MINT, this.subjectVisualSize(system) * 1.68, this.subjectVisualSize(system) * 1.02, 4, 0.50)
      }

      if (system.count >= 18) {
        this.SatelliteDot(TEXT_2, this.subjectVisualSize(system) * 0.22, this.subjectVisualSize(system) * 0.70, 3, 0.42)
      }

      if (this.showPlanets()) {
        ForEach(system.orbits,
          (orbit: ChapterOrbit, orbitIndex: number): void => {
            ForEach(orbit.planets.slice(0, this.maxOverviewPlanets(orbitIndex)),
              (planet: PlanetNode, planetIndex: number): void => {
                this.OverviewPlanet(system, orbitIndex, planet, planetIndex)
              },
              (planet: PlanetNode): string => system.subject + "_" + planet.id + "_overview_planet"
            )
          },
          (orbit: ChapterOrbit): string => system.subject + "_" + orbit.chapter + "_overview_planets"
        )
      }

      this.SubjectLabelNode(system)
    }
    .width(this.subjectNodeWidth(system))
    .height(this.subjectNodeHeight(system))
    .alignContent(Alignment.Center)
    .position({
      x: this.subjectWorldCenterX(system) - this.subjectNodeWidth(system) / 2,
      y: this.subjectWorldCenterY(system) - this.subjectNodeHeight(system) / 2,
    })
    .backgroundColor("#01000000")
    .onClick((): void => this.onSelectSubject(system.subject))
  }

  @Builder
  SubjectLabelNode(system: SubjectSystem) {
    Column() {
      Text(system.subject)
        .fontSize(F_XS)
        .fontWeight(W_SEMIBOLD)
        .fontColor(TEXT)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(118)
        .textAlign(TextAlign.Center)
      Text(system.count.toString() + " 条 · " + pctText(system.mastery))
        .fontSize(F_XS)
        .fontColor(TEXT_3)
        .maxLines(1)
    }
    .width(126)
    .height(34)
    .alignItems(HorizontalAlign.Center)
    .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
    .translate({ y: this.subjectVisualSize(system) * 0.74 })
  }

  @Builder
  StarDust() {
    ForEach(UNIVERSE_STAR_INDEXES,
      (index: number): void => {
        this.StarPixel(index)
      },
      (index: number): string => "overview_star_" + index.toString()
    )
  }

  @Builder
  StarPixel(index: number) {
    Circle({ width: this.starSize(index), height: this.starSize(index) })
      .fill(this.starColor(index))
      .opacity(this.starOpacity(index))
      .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      .position({
        x: this.starWorldX(index) - this.starSize(index) / 2,
        y: this.starWorldY(index) - this.starSize(index) / 2,
      })
  }

  @Builder
  NebulaTrails() {
    Ellipse()
      .width(this.nebulaSize(420))
      .height(this.nebulaSize(138))
      .stroke(MINT)
      .strokeWidth(0.35)
      .opacity(0.16)
      .rotate({ angle: -22 })
      .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      .position({ x: this.nebulaWorldX(0.18, 420), y: this.nebulaWorldY(0.20, 138) })
    Ellipse()
      .width(this.nebulaSize(520))
      .height(this.nebulaSize(178))
      .stroke("#9BE7FF")
      .strokeWidth(0.3)
      .opacity(0.09)
      .rotate({ angle: -27 })
      .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      .position({ x: this.nebulaWorldX(0.56, 520), y: this.nebulaWorldY(0.38, 178) })
    Ellipse()
      .width(this.nebulaSize(300))
      .height(this.nebulaSize(86))
      .stroke("#C8B6FF")
      .strokeWidth(0.35)
      .opacity(0.08)
      .rotate({ angle: 18 })
      .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      .position({ x: this.nebulaWorldX(0.82, 300), y: this.nebulaWorldY(0.70, 86) })
    Row()
      .width(this.nebulaSize(162))
      .height(1)
      .backgroundColor(MINT)
      .opacity(0.10)
      .rotate({ angle: -31 })
      .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      .position({ x: this.nebulaWorldX(0.30, 162), y: this.nebulaWorldY(0.82, 1) })
    Row()
      .width(this.nebulaSize(96))
      .height(1)
      .backgroundColor("#DAB7FF")
      .opacity(0.10)
      .rotate({ angle: 24 })
      .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      .position({ x: this.nebulaWorldX(0.72, 96), y: this.nebulaWorldY(0.16, 1) })
  }

  @Builder
  OverviewOrbit(system: SubjectSystem, orbit: ChapterOrbit, orbitIndex: number) {
    Ellipse()
      .width(this.overviewOrbitWidth(system, orbitIndex))
      .height(this.overviewOrbitHeight(system, orbitIndex))
      .stroke(orbitIndex % 2 === 0 ? system.color : MINT)
      .strokeWidth(0.35)
      .opacity(this.orbitOpacity())
      .rotate({ angle: orbit.tilt })
  }

  @Builder
  OverviewPlanet(system: SubjectSystem, orbitIndex: number, planet: PlanetNode, planetIndex: number) {
    Column() {
      Stack() {
        Circle({ width: this.overviewPlanetSize(planet) + 5, height: this.overviewPlanetSize(planet) + 5 })
          .fill(planetBaseColor(planet.id))
          .opacity(0.08)
        this.SolarPlanet(planet, this.overviewPlanetSize(planet), 0.74)
      }
      .width(this.overviewPlanetSize(planet) * 1.72)
      .height(this.overviewPlanetSize(planet) * 1.34)
      .alignContent(Alignment.Center)

      if (this.showOverviewPlanetLabels()) {
        Text(planetLabel(planet))
          .fontSize(F_XS)
          .fontColor("#BEEBFAFF")
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(this.overviewPlanetFrameWidth(planet))
          .height(16)
          .textAlign(TextAlign.Center)
          .scale({ x: this.inverseZoom(), y: this.inverseZoom() })
      }
    }
    .width(this.overviewPlanetFrameWidth(planet))
    .height(this.overviewPlanetFrameHeight(planet))
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.overviewPlanetX(system, orbitIndex, planetIndex), y: this.overviewPlanetY(system, orbitIndex, planetIndex) })
    .onClick((): void => this.onSelectPlanet(planet))
  }

  @Builder
  SatelliteDot(color: string, x: number, y: number, sizeValue: number, alpha: number) {
    Circle({ width: sizeValue + 6, height: sizeValue + 6 })
      .fill(color)
      .opacity(alpha * 0.12)
      .position({ x: x, y: y })
    Circle({ width: sizeValue, height: sizeValue })
      .fill(color)
      .opacity(alpha)
      .position({ x: x + 3, y: y + 3 })
  }

  @Builder
  SolarPlanet(planet: PlanetNode, sizeValue: number, alpha: number) {
    Stack() {
      if (planetVariant(planet.id) === 2) {
        Ellipse()
          .width(sizeValue * 1.65)
          .height(sizeValue * 0.56)
          .stroke(planetAccentColor(planet.id))
          .strokeWidth(Math.max(1, sizeValue * 0.08))
          .opacity(alpha * 0.60)
          .rotate({ angle: -18 })
      }

      Circle({ width: sizeValue, height: sizeValue })
        .fill(planetBaseColor(planet.id))
        .opacity(alpha)

      if (planetVariant(planet.id) === 1) {
        Ellipse().width(sizeValue * 0.82).height(sizeValue * 0.14).fill(planetAccentColor(planet.id)).opacity(alpha * 0.42).position({ x: sizeValue * 0.09, y: sizeValue * 0.26 })
        Ellipse().width(sizeValue * 0.74).height(sizeValue * 0.12).fill("#FFF4C7").opacity(alpha * 0.28).position({ x: sizeValue * 0.13, y: sizeValue * 0.50 })
      } else if (planetVariant(planet.id) === 3) {
        Circle({ width: sizeValue * 0.34, height: sizeValue * 0.34 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.46).position({ x: sizeValue * 0.18, y: sizeValue * 0.18 })
        Circle({ width: sizeValue * 0.22, height: sizeValue * 0.22 }).fill("#E7FFF8").opacity(alpha * 0.30).position({ x: sizeValue * 0.58, y: sizeValue * 0.50 })
      } else if (planetVariant(planet.id) === 4) {
        Circle({ width: sizeValue * 0.18, height: sizeValue * 0.18 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.54).position({ x: sizeValue * 0.20, y: sizeValue * 0.30 })
        Circle({ width: sizeValue * 0.14, height: sizeValue * 0.14 }).fill("#FFF1C1").opacity(alpha * 0.32).position({ x: sizeValue * 0.60, y: sizeValue * 0.22 })
        Circle({ width: sizeValue * 0.12, height: sizeValue * 0.12 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.34).position({ x: sizeValue * 0.52, y: sizeValue * 0.66 })
      } else {
        Circle({ width: sizeValue * 0.28, height: sizeValue * 0.28 }).fill("#FFFFFF").opacity(alpha * 0.18).position({ x: sizeValue * 0.18, y: sizeValue * 0.16 })
      }
    }
    .width(sizeValue * 1.7)
    .height(sizeValue * 1.3)
    .alignContent(Alignment.Center)
  }

  @Builder
  SolarStar(color: string, sizeValue: number, alpha: number) {
    Stack() {
      Circle({ width: sizeValue * 1.36, height: sizeValue * 1.36 })
        .fill(color)
        .opacity(alpha * 0.16)
      Circle({ width: sizeValue, height: sizeValue })
        .fill(color)
        .opacity(alpha * 0.72)
      Circle({ width: sizeValue * 0.62, height: sizeValue * 0.62 })
        .fill("#FFF7B8")
        .opacity(alpha * 0.70)
      Circle({ width: sizeValue * 0.24, height: sizeValue * 0.24 })
        .fill("#FFFFFF")
        .opacity(alpha * 0.48)
        .position({ x: sizeValue * 0.42, y: sizeValue * 0.36 })
    }
    .width(sizeValue * 1.36)
    .height(sizeValue * 1.36)
    .alignContent(Alignment.Center)
  }

  @Builder
  ZoomControls() {
    Row({ space: 8 }) {
      this.ZoomButton("-", (): void => this.onZoomOut())
      this.ZoomButton(Math.round(this.zoom * 100).toString() + "%", (): void => this.onResetZoom(), 56)
      this.ZoomButton("+", (): void => this.onZoomIn())
    }
    .alignSelf(ItemAlign.Center)
    .margin({ top: S_2, bottom: S_2 })
  }

  @Builder
  ZoomButton(label: string, action: () => void, widthValue: number = 38) {
    Text(label)
      .fontSize(F_SM)
      .fontWeight(W_SEMIBOLD)
      .fontColor(TEXT_2)
      .width(widthValue)
      .height(34)
      .textAlign(TextAlign.Center)
      .borderRadius(R_FULL)
      .backgroundColor(GLASS_10)
      .border({ width: 0.5, color: BORDER })
      .onClick((): void => action())
  }

  @Builder
  StatPill(value: string, label: string) {
    Column() {
      Text(value)
        .fontSize(F_BASE)
        .fontWeight(W_BOLD)
        .fontColor(TEXT)
      Text(label)
        .fontSize(F_XS)
        .fontColor(TEXT_3)
        .margin({ top: 2 })
    }
    .width(96)
    .height(58)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(R_MD)
    .backgroundColor(BG_CARD)
    .border({ width: 0.5, color: BORDER })
  }

  private worldWidth(): number {
    return universeWorldWidth(this.systems.length)
  }

  private worldHeight(): number {
    return universeWorldHeight(this.systems.length)
  }

  private worldTileScreenX(copyX: number): number {
    return UNIVERSE_WIDTH / 2 - this.cameraX * this.zoom + copyX * this.worldWidth() * this.zoom -
      this.worldWidth() * (1 - this.zoom) / 2
  }

  private worldTileScreenY(copyY: number): number {
    return UNIVERSE_HEIGHT / 2 - this.cameraY * this.zoom + copyY * this.worldHeight() * this.zoom -
      this.worldHeight() * (1 - this.zoom) / 2
  }

  private inverseZoom(): number {
    return 1 / Math.max(UNIVERSE_MIN_ZOOM, this.zoom)
  }

  private subjectIndex(subject: string): number {
    let index: number = 0
    while (index < this.systems.length) {
      if (this.systems[index].subject === subject) {
        return index
      }
      index++
    }
    return 0
  }

  private subjectWorldCenterX(system: SubjectSystem): number {
    if (this.systems.length <= 1) {
      return this.worldWidth() / 2
    }
    const index: number = this.subjectIndex(system.subject)
    const cols: number = universeColumns(this.systems.length)
    const col: number = index % cols
    const cellWidth: number = this.worldWidth() / cols
    const jitter: number = ((stableHash(system.subject) % 101) - 50) / 50 * Math.min(68, cellWidth * 0.22)
    return wrapCoordinate(cellWidth * (col + 0.5) + jitter, this.worldWidth())
  }

  private subjectWorldCenterY(system: SubjectSystem): number {
    if (this.systems.length <= 1) {
      return this.worldHeight() / 2
    }
    const index: number = this.subjectIndex(system.subject)
    const cols: number = universeColumns(this.systems.length)
    const rows: number = universeRows(this.systems.length)
    const row: number = Math.floor(index / cols)
    const cellHeight: number = this.worldHeight() / rows
    const jitter: number = ((stableHash(system.subject + "_y") % 97) - 48) / 48 * Math.min(62, cellHeight * 0.18)
    return wrapCoordinate(cellHeight * (row + 0.5) + jitter, this.worldHeight())
  }

  private subjectVisualSize(system: SubjectSystem): number {
    const normalized: number = clamp((system.size - 48) / 52, 0, 1)
    return clamp(18 + normalized * 18, 18, 36)
  }

  private subjectNodeWidth(system: SubjectSystem): number {
    return Math.max(UNIVERSE_SUBJECT_HIT_SIZE, 126, this.subjectVisualSize(system) + 90)
  }

  private subjectNodeHeight(system: SubjectSystem): number {
    return Math.max(UNIVERSE_SUBJECT_HIT_SIZE, 104, this.subjectVisualSize(system) + 82)
  }

  private starWorldX(index: number): number {
    return wrapCoordinate(42 + index * 137 + (index % 5) * 31, this.worldWidth())
  }

  private starWorldY(index: number): number {
    return wrapCoordinate(36 + index * 89 + (index % 7) * 43, this.worldHeight())
  }

  private starSize(index: number): number {
    return 3 + index % 5
  }

  private starOpacity(index: number): number {
    return 0.15 + (index % 6) * 0.035
  }

  private starColor(index: number): string {
    if (index % 13 === 0) {
      return "#DAB7FF"
    }
    if (index % 7 === 0) {
      return MINT
    }
    return TEXT_2
  }

  private showOrbitHints(): boolean {
    return this.zoom >= 1.1
  }

  private showPlanets(): boolean {
    return this.zoom >= 1.35
  }

  private showOverviewPlanetLabels(): boolean {
    return this.zoom >= 1.9
  }

  private nebulaSize(value: number): number {
    return value
  }

  private nebulaWorldX(centerRatio: number, widthValue: number): number {
    return wrapCoordinate(this.worldWidth() * centerRatio, this.worldWidth()) - this.nebulaSize(widthValue) / 2
  }

  private nebulaWorldY(centerRatio: number, heightValue: number): number {
    return wrapCoordinate(this.worldHeight() * centerRatio, this.worldHeight()) - this.nebulaSize(heightValue) / 2
  }

  private orbitOpacity(): number {
    return clamp((this.zoom - 1.05) * 0.46, 0.04, 0.28)
  }

  private zoomHint(): string {
    if (this.zoom < 1.1) {
      return "点击学科星系进入详情，放大后逐步显示章节轨道"
    }
    if (this.zoom < 1.35) {
      return "章节轨道已显现，继续放大可看到笔记行星"
    }
    return "行星代表笔记，点击行星可打开详情"
  }

  private maxOverviewPlanets(orbitIndex: number): number {
    if (this.zoom < 1.5) {
      return orbitIndex < 2 ? 3 : 2
    }
    if (this.zoom < 1.9) {
      return orbitIndex < 3 ? 5 : 3
    }
    if (this.zoom < 2.2) {
      return orbitIndex < 4 ? 7 : 4
    }
    return orbitIndex < 4 ? 9 : 5
  }

  private overviewOrbitWidth(system: SubjectSystem, orbitIndex: number): number {
    return this.subjectVisualSize(system) * 1.65 + orbitIndex * 14
  }

  private overviewOrbitHeight(system: SubjectSystem, orbitIndex: number): number {
    return this.subjectVisualSize(system) * 0.54 + orbitIndex * 5
  }

  private overviewPlanetSize(planet: PlanetNode): number {
    return clamp(planet.size * 0.24, 4, 11)
  }

  private overviewPlanetFrameWidth(planet: PlanetNode): number {
    const visualWidth: number = this.overviewPlanetSize(planet) * 1.9
    return this.showOverviewPlanetLabels() ? Math.max(58, visualWidth) : visualWidth
  }

  private overviewPlanetFrameHeight(planet: PlanetNode): number {
    return this.overviewPlanetSize(planet) * 1.34 + (this.showOverviewPlanetLabels() ? 16 : 0)
  }

  private overviewPlanetX(system: SubjectSystem, orbitIndex: number, planetIndex: number): number {
    const frame: number = this.subjectNodeWidth(system)
    const angle: number = (planetIndex * 62 + orbitIndex * 37 + 18) * Math.PI / 180
    const radiusX: number = this.overviewOrbitWidth(system, orbitIndex) / 2
    const planet: PlanetNode = system.orbits[orbitIndex].planets[planetIndex]
    return frame / 2 + Math.cos(angle) * radiusX - this.overviewPlanetFrameWidth(planet) / 2
  }

  private overviewPlanetY(system: SubjectSystem, orbitIndex: number, planetIndex: number): number {
    const frame: number = this.subjectNodeHeight(system)
    const angle: number = (planetIndex * 62 + orbitIndex * 37 + 18) * Math.PI / 180
    const radiusY: number = this.overviewOrbitHeight(system, orbitIndex) / 2
    const planet: PlanetNode = system.orbits[orbitIndex].planets[planetIndex]
    return frame / 2 + Math.sin(angle) * radiusY - this.overviewPlanetFrameHeight(planet) / 2
  }

}

@Component
struct SubjectGalaxyView {
  @Prop system: SubjectSystem | null = null
  @Prop zoom: number = 1
  @Prop orbitOffset: number = 0
  @Prop focusedPlanetId: string = ""
  @Prop cameraOffsetX: number = 0
  @Prop cameraOffsetY: number = 0
  @State dragStartCameraOffsetX: number = 0
  @State dragStartCameraOffsetY: number = 0
  onSelectPlanet: (planet: PlanetNode) => void = (_planet: PlanetNode): void => {}
  onHoverPlanet: (planetId: string) => void = (_planetId: string): void => {}
  onCameraChange: (x: number, y: number) => void = (_x: number, _y: number): void => {}
  onZoomIn: () => void = (): void => {}
  onZoomOut: () => void = (): void => {}
  onResetZoom: () => void = (): void => {}

  build() {
    Scroll() {
      Column() {
        if (this.system !== null) {
          Stack() {
            Image($r("app.media.galaxy_detail_bg"))
              .width(this.detailBackgroundFrameSize())
              .height(this.detailBackgroundFrameSize())
              .objectFit(ImageFit.Cover)
              .opacity(0.72)
              .scale({ x: this.detailBackgroundScale(), y: this.detailBackgroundScale() })
              .position({
                x: this.detailBackgroundX(),
                y: this.detailBackgroundY(),
              })
            Stack() {
              this.DetailNebulaTrails(this.system!)
              this.StarDust()

              ForEach(this.system!.orbits,
                (orbit: ChapterOrbit): void => {
                  this.ChapterOrbitRing(orbit)
                },
                (orbit: ChapterOrbit): string => orbit.chapter
              )

              ForEach(this.focusedLinks(),
                (link: GalaxyLink): void => {
                  this.RelationLine(link)
                },
                (link: GalaxyLink): string => this.linkKey(link)
              )

              this.PlanetLayer(true)
              this.CenterStar(this.system!)
              this.PlanetLayer(false)
            }
            .width(GALAXY_SIZE)
            .height(GALAXY_SIZE)
            .translate({ x: this.cameraOffsetX, y: this.cameraOffsetY })
          }
          .width(GALAXY_SIZE)
          .height(GALAXY_SIZE)
          .alignSelf(ItemAlign.Center)
          .margin({ top: S_2 })
          .clip(true)
          .priorityGesture(
            PanGesture({ direction: PanDirection.All })
              .onActionStart((_event: GestureEvent): void => {
                this.dragStartCameraOffsetX = this.cameraOffsetX
                this.dragStartCameraOffsetY = this.cameraOffsetY
              })
              .onActionUpdate((event: GestureEvent): void => {
                this.onCameraChange(
                  this.dragStartCameraOffsetX + event.offsetX,
                  this.dragStartCameraOffsetY + event.offsetY,
                )
              })
              .onActionEnd((): void => {
                this.dragStartCameraOffsetX = this.cameraOffsetX
                this.dragStartCameraOffsetY = this.cameraOffsetY
              })
          )

          this.ZoomControls()
          this.SubjectSummary(this.system!)
        }
        Blank().height(96)
      }
      .width("100%")
    }
    .layoutWeight(1)
    .width("100%")
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  ChapterOrbitRing(orbit: ChapterOrbit) {
    Ellipse()
      .width(orbit.radiusX * 2 * this.zoom)
      .height(orbit.radiusY * 2 * this.zoom)
      .stroke(this.orbitStrokeColor(orbit))
      .strokeWidth(this.orbitStrokeWidth(orbit))
      .opacity(this.orbitOpacity(orbit))
      .rotate({ angle: orbit.tilt })

    Ellipse()
      .width(orbit.radiusX * 2 * this.zoom + 18)
      .height(orbit.radiusY * 2 * this.zoom + 8)
      .stroke(this.orbitStrokeColor(orbit))
      .strokeWidth(this.isOrbitFocused(orbit) ? 0.7 : 0.35)
      .opacity(this.isOrbitFocused(orbit) ? 0.20 : 0.08)
      .rotate({ angle: orbit.tilt + 2 })

    Text(orbit.chapter)
      .fontSize(F_XS)
      .fontWeight(W_SEMIBOLD)
      .fontColor(this.isOrbitFocused(orbit) ? "#E7FFF8" : "#CCECF7FF")
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width(96)
      .height(22)
      .textAlign(TextAlign.Center)
      .borderRadius(R_FULL)
      .backgroundColor(this.isOrbitFocused(orbit) ? "#361CECD4" : "#3008121C")
      .border({ width: this.isOrbitFocused(orbit) ? 0.8 : 0.5, color: this.isOrbitFocused(orbit) ? MINT : "#3A9BE7FF" })
      .position({ x: this.orbitLabelX(orbit), y: this.orbitLabelY(orbit) })
  }

  @Builder
  RelationLine(link: GalaxyLink) {
    if (this.hasPlanet(link.fromId) && this.hasPlanet(link.toId)) {
      Row()
        .width(this.linkDistance(link))
        .height(this.linkStrokeWidth(link))
        .borderRadius(R_FULL)
        .backgroundColor(this.linkColor(link))
        .opacity(this.linkOpacity(link))
        .rotate({ angle: this.linkAngle(link) })
        .position({ x: this.linkLeftX(link), y: this.linkTopY(link) })

      Text(this.linkLabel(link))
        .fontSize(9)
        .fontWeight(W_SEMIBOLD)
        .fontColor(this.linkLabelColor(link))
        .width(42)
        .height(18)
        .textAlign(TextAlign.Center)
        .borderRadius(R_FULL)
        .backgroundColor(this.linkLabelBackground(link))
        .border({ width: 0.4, color: this.linkColor(link) })
        .opacity(this.linkLabelOpacity(link))
        .position({ x: this.linkLabelX(link), y: this.linkLabelY(link) })
    }
  }

  @Builder
  CenterStar(system: SubjectSystem) {
    Stack() {
      Circle({ width: 72, height: 72 })
        .fill(system.color)
        .opacity(this.centerStarGlowOpacity(0.045))

      Circle({ width: 50, height: 50 })
        .fill(system.color)
        .opacity(this.centerStarGlowOpacity(0.10))

      Circle({ width: 28, height: 28 })
        .fill("#E7FFF8")
        .opacity(this.centerStarGlowOpacity(0.18))

      this.SolarStar(system.color, 34, 0.96)
    }
    .width(this.centerStarFrameSize())
    .height(this.centerStarFrameSize())
    .alignContent(Alignment.Center)
    .scale({ x: this.centerStarScale(), y: this.centerStarScale() })
    .position({
      x: GALAXY_CENTER - this.centerStarFrameSize() / 2,
      y: GALAXY_CENTER - this.centerStarFrameSize() / 2,
    })
  }

  @Builder
  Planet(orbit: ChapterOrbit, planet: PlanetNode) {
    Column() {
      Stack() {
        if (this.isOrbitFocused(orbit)) {
          Circle({ width: this.planetSize(planet) + this.planetHighlightPadding(planet), height: this.planetSize(planet) + this.planetHighlightPadding(planet) })
            .fill("#00FFFFFF")
            .stroke(planet.id === this.focusedPlanetId ? MINT : planetAccentColor(planet.id))
            .strokeWidth(planet.id === this.focusedPlanetId ? 1.2 : 0.75)
            .opacity(planet.id === this.focusedPlanetId ? 0.78 : 0.42)
        }
        Circle({ width: this.planetSize(planet) + 10, height: this.planetSize(planet) + 10 })
          .fill(planetBaseColor(planet.id))
          .opacity(0.045)
        Circle({ width: this.planetSize(planet) + 5, height: this.planetSize(planet) + 5 })
          .fill(planetAccentColor(planet.id))
          .opacity(0.08)
        this.SolarPlanet(planet, this.planetSize(planet), planet.alpha)
      }
      .width(this.planetSize(planet) * 1.72)
      .height(this.planetSize(planet) * 1.34)
      .alignContent(Alignment.Center)
      .scale({ x: this.planetVisualScale(), y: this.planetVisualScale() })

      Text(planetLabel(planet))
        .fontSize(F_XS)
        .fontColor("#C6ECF8FF")
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(this.planetFrameWidth(planet))
        .height(18)
        .textAlign(TextAlign.Center)
    }
    .width(this.planetFrameWidth(planet))
    .height(this.planetFrameHeight(planet))
    .alignItems(HorizontalAlign.Center)
    .position({ x: this.planetX(orbit, planet), y: this.planetY(orbit, planet) })
    .onHover((isHover: boolean): void => {
      this.onHoverPlanet(isHover ? planet.id : "")
    })
    .onClick((): void => this.onSelectPlanet(planet))
  }

  @Builder
  PlanetLayer(isBackLayer: boolean) {
    if (this.system !== null) {
      ForEach(this.system.orbits,
        (orbit: ChapterOrbit): void => {
          ForEach(orbit.planets,
            (planet: PlanetNode): void => {
              if (this.isPlanetBehindStar(planet) === isBackLayer) {
                this.Planet(orbit, planet)
              }
            },
            (planet: PlanetNode): string => orbit.chapter + "_" + planet.id + (isBackLayer ? "_back" : "_front")
          )
        },
        (orbit: ChapterOrbit): string => orbit.chapter + (isBackLayer ? "_back_planets" : "_front_planets")
      )
    }
  }

  @Builder
  ZoomControls() {
    Row({ space: 8 }) {
      this.ZoomButton("-", (): void => this.onZoomOut())
      this.ZoomButton(Math.round(this.zoom * 100).toString() + "%", (): void => this.onResetZoom(), 56)
      this.ZoomButton("+", (): void => this.onZoomIn())
    }
    .alignSelf(ItemAlign.Center)
    .margin({ top: S_2, bottom: S_3 })
  }

  @Builder
  ZoomButton(label: string, action: () => void, widthValue: number = 38) {
    Text(label)
      .fontSize(F_SM)
      .fontWeight(W_SEMIBOLD)
      .fontColor(TEXT_2)
      .width(widthValue)
      .height(34)
      .textAlign(TextAlign.Center)
      .borderRadius(R_FULL)
      .backgroundColor(GLASS_10)
      .border({ width: 0.5, color: BORDER })
      .onClick((): void => action())
  }

  @Builder
  SubjectSummary(system: SubjectSystem) {
    Column() {
      Row() {
        Text(system.subject + " 星系")
          .fontSize(F_BASE)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
        Blank()
        Text(system.orbits.length.toString() + " 章 · " + system.count.toString() + " 笔记")
          .fontSize(F_XS)
          .fontColor(TEXT_3)
      }
      .width("100%")

      Stack({ alignContent: Alignment.Start }) {
        Row().width("100%").height(7).borderRadius(R_FULL).backgroundColor(GLASS_10)
        Row()
          .width(pctText(system.mastery))
          .height(7)
          .borderRadius(R_FULL)
          .backgroundColor(system.color)
      }
      .width("100%")
      .height(7)
      .margin({ top: S_3, bottom: S_3 })

      Text("轨道代表章节，颜色代表笔记类型，大小随掌握度和复习次数变化。")
        .fontSize(F_XS)
        .fontColor(TEXT_3)
        .lineHeight(18)
        .width("100%")
    }
    .width("90%")
    .alignSelf(ItemAlign.Center)
    .padding({ left: S_4, right: S_4, top: S_4, bottom: S_4 })
    .borderRadius(R_LG)
    .backgroundColor(BG_CARD)
    .border({ width: 0.5, color: BORDER })
  }

  @Builder
  StarDust() {
    Circle({ width: 2, height: 2 }).fill(TEXT_2).opacity(0.28).position({ x: 28, y: 28 })
    Circle({ width: 1, height: 1 }).fill(TEXT_2).opacity(0.24).position({ x: 94, y: 70 })
    Circle({ width: 2, height: 2 }).fill(MINT).opacity(0.30).position({ x: 292, y: 34 })
    Circle({ width: 1, height: 1 }).fill(TEXT_2).opacity(0.20).position({ x: 326, y: 118 })
    Circle({ width: 2, height: 2 }).fill(MINT).opacity(0.22).position({ x: 314, y: 188 })
    Circle({ width: 2, height: 2 }).fill(TEXT_2).opacity(0.20).position({ x: 42, y: 278 })
    Circle({ width: 1, height: 1 }).fill("#DAB7FF").opacity(0.24).position({ x: 132, y: 322 })
    Circle({ width: 2, height: 2 }).fill(TEXT_2).opacity(0.22).position({ x: 204, y: 304 })
  }

  @Builder
  DetailNebulaTrails(system: SubjectSystem) {
    Ellipse()
      .width(380 * this.detailBackgroundScale())
      .height(118 * this.detailBackgroundScale())
      .stroke(system.color)
      .strokeWidth(0.35)
      .opacity(0.10)
      .rotate({ angle: -20 })
      .position({ x: -22, y: 74 })
    Ellipse()
      .width(430 * this.detailBackgroundScale())
      .height(146 * this.detailBackgroundScale())
      .stroke(MINT)
      .strokeWidth(0.3)
      .opacity(0.08)
      .rotate({ angle: -28 })
      .position({ x: -58, y: 142 })
    Ellipse()
      .width(250 * this.detailBackgroundScale())
      .height(72 * this.detailBackgroundScale())
      .stroke("#C8B6FF")
      .strokeWidth(0.3)
      .opacity(0.07)
      .rotate({ angle: 18 })
      .position({ x: 126, y: 250 })
    Row()
      .width(120 * this.detailBackgroundScale())
      .height(1)
      .backgroundColor(system.color)
      .opacity(0.08)
      .rotate({ angle: 28 })
      .position({ x: 212, y: 58 })
    Row()
      .width(154 * this.detailBackgroundScale())
      .height(1)
      .backgroundColor(MINT)
      .opacity(0.08)
      .rotate({ angle: -34 })
      .position({ x: 16, y: 316 })
  }

  @Builder
  SolarPlanet(planet: PlanetNode, sizeValue: number, alpha: number) {
    Stack() {
      if (planetVariant(planet.id) === 2) {
        Ellipse()
          .width(sizeValue * 1.68)
          .height(sizeValue * 0.58)
          .stroke(planetAccentColor(planet.id))
          .strokeWidth(Math.max(1, sizeValue * 0.08))
          .opacity(alpha * 0.62)
          .rotate({ angle: -18 })
      }

      Circle({ width: sizeValue, height: sizeValue })
        .fill(planetBaseColor(planet.id))
        .opacity(alpha)

      if (planetVariant(planet.id) === 1) {
        Ellipse().width(sizeValue * 0.84).height(sizeValue * 0.14).fill(planetAccentColor(planet.id)).opacity(alpha * 0.44).position({ x: sizeValue * 0.08, y: sizeValue * 0.25 })
        Ellipse().width(sizeValue * 0.76).height(sizeValue * 0.12).fill("#FFF4C7").opacity(alpha * 0.30).position({ x: sizeValue * 0.12, y: sizeValue * 0.50 })
        Ellipse().width(sizeValue * 0.68).height(sizeValue * 0.10).fill(planetAccentColor(planet.id)).opacity(alpha * 0.25).position({ x: sizeValue * 0.16, y: sizeValue * 0.66 })
      } else if (planetVariant(planet.id) === 3) {
        Circle({ width: sizeValue * 0.34, height: sizeValue * 0.34 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.48).position({ x: sizeValue * 0.18, y: sizeValue * 0.18 })
        Circle({ width: sizeValue * 0.22, height: sizeValue * 0.22 }).fill("#E7FFF8").opacity(alpha * 0.30).position({ x: sizeValue * 0.58, y: sizeValue * 0.50 })
      } else if (planetVariant(planet.id) === 4) {
        Circle({ width: sizeValue * 0.18, height: sizeValue * 0.18 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.54).position({ x: sizeValue * 0.20, y: sizeValue * 0.30 })
        Circle({ width: sizeValue * 0.14, height: sizeValue * 0.14 }).fill("#FFF1C1").opacity(alpha * 0.32).position({ x: sizeValue * 0.60, y: sizeValue * 0.22 })
        Circle({ width: sizeValue * 0.12, height: sizeValue * 0.12 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.34).position({ x: sizeValue * 0.52, y: sizeValue * 0.66 })
      } else if (planetVariant(planet.id) === 5) {
        Ellipse().width(sizeValue * 0.72).height(sizeValue * 0.16).fill("#FFFFFF").opacity(alpha * 0.18).position({ x: sizeValue * 0.14, y: sizeValue * 0.36 })
        Circle({ width: sizeValue * 0.20, height: sizeValue * 0.20 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.30).position({ x: sizeValue * 0.56, y: sizeValue * 0.58 })
      } else {
        Circle({ width: sizeValue * 0.28, height: sizeValue * 0.28 }).fill("#FFFFFF").opacity(alpha * 0.18).position({ x: sizeValue * 0.18, y: sizeValue * 0.16 })
        Circle({ width: sizeValue * 0.20, height: sizeValue * 0.20 }).fill(planetAccentColor(planet.id)).opacity(alpha * 0.28).position({ x: sizeValue * 0.54, y: sizeValue * 0.58 })
      }
    }
    .width(sizeValue * 1.72)
    .height(sizeValue * 1.34)
    .alignContent(Alignment.Center)
  }

  @Builder
  SolarStar(color: string, sizeValue: number, alpha: number) {
    Stack() {
      Circle({ width: sizeValue * 1.52, height: sizeValue * 1.52 })
        .fill(color)
        .opacity(alpha * 0.13)
      Circle({ width: sizeValue * 1.18, height: sizeValue * 1.18 })
        .fill(color)
        .opacity(alpha * 0.30)
      Circle({ width: sizeValue, height: sizeValue })
        .fill(color)
        .opacity(alpha * 0.70)
      Circle({ width: sizeValue * 0.58, height: sizeValue * 0.58 })
        .fill("#FFF7B8")
        .opacity(alpha * 0.76)
      Circle({ width: sizeValue * 0.22, height: sizeValue * 0.22 })
        .fill("#FFFFFF")
        .opacity(alpha * 0.50)
        .position({ x: sizeValue * 0.48, y: sizeValue * 0.42 })
    }
    .width(sizeValue * 1.52)
    .height(sizeValue * 1.52)
    .alignContent(Alignment.Center)
  }

  private detailBackgroundScale(): number {
    return clamp(1 + Math.max(0, this.zoom - 1) * 0.28, 1, 1.56)
  }

  private detailBackgroundPanPadding(): number {
    return 160
  }

  private detailBackgroundFrameSize(): number {
    return GALAXY_SIZE + this.detailBackgroundPanPadding() * 2
  }

  private detailBackgroundOffsetX(): number {
    return clamp(-this.cameraOffsetX * 0.35, -this.detailBackgroundPanPadding(), this.detailBackgroundPanPadding())
  }

  private detailBackgroundOffsetY(): number {
    return clamp(-this.cameraOffsetY * 0.35, -this.detailBackgroundPanPadding(), this.detailBackgroundPanPadding())
  }

  private detailBackgroundX(): number {
    return -this.detailBackgroundPanPadding() + this.detailBackgroundOffsetX()
  }

  private detailBackgroundY(): number {
    return -this.detailBackgroundPanPadding() + this.detailBackgroundOffsetY()
  }

  private centerStarScale(): number {
    return clamp(0.62 + this.zoom * 0.58, 0.95, 2.45)
  }

  private centerStarFrameSize(): number {
    return 86
  }

  private centerStarGlowOpacity(baseOpacity: number): number {
    return clamp(baseOpacity + Math.max(0, this.zoom - 1) * 0.045, baseOpacity, baseOpacity + 0.10)
  }

  private orbitStrokeColor(orbit: ChapterOrbit): string {
    if (this.isOrbitFocused(orbit)) {
      return MINT
    }
    if (orbit.mastery >= 0.72) {
      return MINT
    }
    if (orbit.mastery >= 0.42) {
      return "#9BE7FF"
    }
    return "#C8B6FF"
  }

  private orbitStrokeWidth(orbit: ChapterOrbit): number {
    return this.isOrbitFocused(orbit) ? 1.35 : 0.8
  }

  private orbitOpacity(orbit: ChapterOrbit): number {
    const baseOpacity: number = 0.20 + Math.min(0.18, orbit.mastery * 0.16)
    return this.isOrbitFocused(orbit) ? Math.min(0.58, baseOpacity + 0.24) : baseOpacity
  }

  private orbitLabelX(orbit: ChapterOrbit): number {
    return clamp(GALAXY_CENTER + (orbit.labelX - GALAXY_CENTER) * this.zoom - 48, 4, GALAXY_SIZE - 100)
  }

  private orbitLabelY(orbit: ChapterOrbit): number {
    return clamp(GALAXY_CENTER + (orbit.labelY - GALAXY_CENTER) * this.zoom - 12, 4, GALAXY_SIZE - 28)
  }

  private focusedLinks(): GalaxyLink[] {
    const links: GalaxyLink[] = []
    if (this.system === null || this.focusedPlanetId.length === 0) {
      return links
    }
    for (const link of this.system.links) {
      if (link.fromId === this.focusedPlanetId || link.toId === this.focusedPlanetId) {
        links.push(link)
      }
    }
    return links
  }

  private linkKey(link: GalaxyLink): string {
    return link.type + "_" + link.fromId + "_" + link.toId
  }

  private hasPlanet(id: string): boolean {
    return this.findPlanet(id) !== null && this.findOrbit(id) !== null
  }

  private findPlanet(id: string): PlanetNode | null {
    if (this.system === null || id.length === 0) {
      return null
    }
    for (const orbit of this.system.orbits) {
      for (const planet of orbit.planets) {
        if (planet.id === id) {
          return planet
        }
      }
    }
    return null
  }

  private findOrbit(id: string): ChapterOrbit | null {
    if (this.system === null || id.length === 0) {
      return null
    }
    for (const orbit of this.system.orbits) {
      for (const planet of orbit.planets) {
        if (planet.id === id) {
          return orbit
        }
      }
    }
    return null
  }

  private linkEndpointX(id: string): number {
    const orbit: ChapterOrbit | null = this.findOrbit(id)
    const planet: PlanetNode | null = this.findPlanet(id)
    if (orbit === null || planet === null) {
      return GALAXY_CENTER
    }
    return this.planetCenterX(orbit, planet)
  }

  private linkEndpointY(id: string): number {
    const orbit: ChapterOrbit | null = this.findOrbit(id)
    const planet: PlanetNode | null = this.findPlanet(id)
    if (orbit === null || planet === null) {
      return GALAXY_CENTER
    }
    return this.planetCenterY(orbit, planet)
  }

  private linkDistance(link: GalaxyLink): number {
    const dx: number = this.linkEndpointX(link.toId) - this.linkEndpointX(link.fromId)
    const dy: number = this.linkEndpointY(link.toId) - this.linkEndpointY(link.fromId)
    return Math.sqrt(dx * dx + dy * dy)
  }

  private linkAngle(link: GalaxyLink): number {
    const dx: number = this.linkEndpointX(link.toId) - this.linkEndpointX(link.fromId)
    const dy: number = this.linkEndpointY(link.toId) - this.linkEndpointY(link.fromId)
    return Math.atan2(dy, dx) * 180 / Math.PI
  }

  private linkLeftX(link: GalaxyLink): number {
    return (this.linkEndpointX(link.fromId) + this.linkEndpointX(link.toId)) / 2 - this.linkDistance(link) / 2
  }

  private linkTopY(link: GalaxyLink): number {
    return (this.linkEndpointY(link.fromId) + this.linkEndpointY(link.toId)) / 2 - this.linkStrokeWidth(link) / 2
  }

  private linkMidX(link: GalaxyLink): number {
    return (this.linkEndpointX(link.fromId) + this.linkEndpointX(link.toId)) / 2
  }

  private linkMidY(link: GalaxyLink): number {
    return (this.linkEndpointY(link.fromId) + this.linkEndpointY(link.toId)) / 2
  }

  private linkLabelX(link: GalaxyLink): number {
    return this.linkMidX(link) - 21
  }

  private linkLabelY(link: GalaxyLink): number {
    return this.linkMidY(link) - 9
  }

  private linkStrokeWidth(link: GalaxyLink): number {
    return link.type === "prerequisite" ? 1.4 : 1
  }

  private linkColor(link: GalaxyLink): string {
    if (link.type === "prerequisite") {
      return stableHash(link.fromId + link.toId) % 2 === 0 ? MINT : "#8DEBFF"
    }
    return stableHash(link.fromId + link.toId) % 2 === 0 ? "#DAB7FF" : "#8DEBFF"
  }

  private linkOpacity(link: GalaxyLink): number {
    return link.type === "prerequisite" ? 0.70 : 0.42
  }

  private linkLabel(link: GalaxyLink): string {
    return link.type === "prerequisite" ? "前置" : "关联"
  }

  private linkLabelColor(link: GalaxyLink): string {
    return link.type === "prerequisite" ? "#D8FFF3" : "#F1E3FF"
  }

  private linkLabelBackground(link: GalaxyLink): string {
    return link.type === "prerequisite" ? "#331CECD4" : "#2ADAB7FF"
  }

  private linkLabelOpacity(link: GalaxyLink): number {
    return link.type === "prerequisite" ? 0.90 : 0.76
  }

  private planetAngle(planet: PlanetNode): number {
    return (planet.angle + this.orbitOffset * planet.speed) % 360
  }

  private isOrbitFocused(orbit: ChapterOrbit): boolean {
    if (this.focusedPlanetId.length === 0) {
      return false
    }
    for (const planet of orbit.planets) {
      if (planet.id === this.focusedPlanetId) {
        return true
      }
    }
    return false
  }

  private planetHighlightPadding(planet: PlanetNode): number {
    return planet.id === this.focusedPlanetId ? 14 : 9
  }

  private planetScale(planet: PlanetNode): number {
    const radians: number = this.planetAngle(planet) * Math.PI / 180
    return 0.86 + (Math.sin(radians) + 1) * 0.09
  }

  private isPlanetBehindStar(planet: PlanetNode): boolean {
    const radians: number = this.planetAngle(planet) * Math.PI / 180
    return Math.sin(radians) < 0
  }

  private planetSize(planet: PlanetNode): number {
    return clamp(planet.size * this.planetScale(planet) * 0.39, 6, 21)
  }

  private planetVisualScale(): number {
    return clamp(this.zoom, 0.75, 3)
  }

  private planetFrameWidth(planet: PlanetNode): number {
    return Math.max(54, this.planetSize(planet) * this.planetVisualScale() * 1.9)
  }

  private planetFrameHeight(planet: PlanetNode): number {
    return this.planetSize(planet) * this.planetVisualScale() * 1.34 + 18
  }

  private planetCenterX(orbit: ChapterOrbit, planet: PlanetNode): number {
    const radians: number = this.planetAngle(planet) * Math.PI / 180
    const tilt: number = orbit.tilt * Math.PI / 180
    const x: number = Math.cos(radians) * orbit.radiusX * this.zoom
    const y: number = Math.sin(radians) * orbit.radiusY * this.zoom
    return GALAXY_CENTER + x * Math.cos(tilt) - y * Math.sin(tilt)
  }

  private planetCenterY(orbit: ChapterOrbit, planet: PlanetNode): number {
    const radians: number = this.planetAngle(planet) * Math.PI / 180
    const tilt: number = orbit.tilt * Math.PI / 180
    const x: number = Math.cos(radians) * orbit.radiusX * this.zoom
    const y: number = Math.sin(radians) * orbit.radiusY * this.zoom
    return GALAXY_CENTER + x * Math.sin(tilt) + y * Math.cos(tilt)
  }

  private planetX(orbit: ChapterOrbit, planet: PlanetNode): number {
    return this.planetCenterX(orbit, planet) - this.planetFrameWidth(planet) / 2
  }

  private planetY(orbit: ChapterOrbit, planet: PlanetNode): number {
    return this.planetCenterY(orbit, planet) - this.planetFrameHeight(planet) / 2
  }
}
