// ============================================================================
//  viewmodels/KnowledgeGalaxyViewModel.ets - review knowledge galaxy data logic
// ============================================================================

import { relationalStore } from '@kit.ArkData'
import {
  DatabaseHelper,
  KnowledgeRelation,
  KnowledgeUnit,
  NoteItem,
  subjectColor,
  typeColor,
} from "common"
import { KnowledgeRelationDao } from "../database/KnowledgeRelationDao"
import { NoteDao } from "../database/NoteDao"
import { UiDataCacheService } from "../services/UiDataCacheService"
import { GalaxyPreviewSeedService } from "../services/GalaxyPreviewSeedService"
import { unitToNoteItem } from "../utils/NoteItemMapper"

const UNCLASSIFIED_SUBJECT: string = "未分类"
const UNCLASSIFIED_CHAPTER: string = "未分章节"
const WRONG_NOTE_TYPE: string = "错题"
export type GalaxyLinkType = "prerequisite" | "related"

export class GalaxyLink {
  fromId: string = ""
  toId: string = ""
  type: GalaxyLinkType = "related"
  fromChapter: string = ""
  toChapter: string = ""

  constructor(
    fromId: string,
    toId: string,
    type: GalaxyLinkType,
    fromChapter: string,
    toChapter: string,
  ) {
    this.fromId = fromId
    this.toId = toId
    this.type = type
    this.fromChapter = fromChapter
    this.toChapter = toChapter
  }
}

export class PlanetNode {
  id: string = ""
  note: NoteItem = new NoteItem(0, "", "", "", "", 0, "", [], "")
  unit: KnowledgeUnit | null = null
  subject: string = ""
  chapter: string = ""
  type: string = ""
  color: string = ""
  angle: number = 0
  speed: number = 0
  size: number = 0
  mastery: number = 0
  alpha: number = 1

  constructor(
    id: string,
    note: NoteItem,
    unit: KnowledgeUnit,
    subject: string,
    chapter: string,
    type: string,
    color: string,
    angle: number,
    speed: number,
    size: number,
    mastery: number,
    alpha: number,
  ) {
    this.id = id
    this.note = note
    this.unit = unit
    this.subject = subject
    this.chapter = chapter
    this.type = type
    this.color = color
    this.angle = angle
    this.speed = speed
    this.size = size
    this.mastery = mastery
    this.alpha = alpha
  }
}

export class ChapterOrbit {
  chapter: string = ""
  count: number = 0
  mastery: number = 0
  radiusX: number = 0
  radiusY: number = 0
  tilt: number = 0
  labelX: number = 0
  labelY: number = 0
  planets: PlanetNode[] = []

  constructor(
    chapter: string,
    count: number,
    mastery: number,
    radiusX: number,
    radiusY: number,
    tilt: number,
    labelX: number,
    labelY: number,
    planets: PlanetNode[],
  ) {
    this.chapter = chapter
    this.count = count
    this.mastery = mastery
    this.radiusX = radiusX
    this.radiusY = radiusY
    this.tilt = tilt
    this.labelX = labelX
    this.labelY = labelY
    this.planets = planets
  }
}

export class SubjectSystem {
  subject: string = ""
  color: string = ""
  count: number = 0
  mastery: number = 0
  x: number = 0
  y: number = 0
  size: number = 0
  planets: PlanetNode[] = []
  orbits: ChapterOrbit[] = []
  links: GalaxyLink[] = []

  constructor(
    subject: string,
    color: string,
    count: number,
    mastery: number,
    x: number,
    y: number,
    size: number,
    planets: PlanetNode[],
    orbits: ChapterOrbit[],
    links: GalaxyLink[],
  ) {
    this.subject = subject
    this.color = color
    this.count = count
    this.mastery = mastery
    this.x = x
    this.y = y
    this.size = size
    this.planets = planets
    this.orbits = orbits
    this.links = links
  }
}

class UnitBundle {
  unit: KnowledgeUnit
  note: NoteItem
  subject: string
  chapter: string

  constructor(unit: KnowledgeUnit, note: NoteItem, subject: string, chapter: string) {
    this.unit = unit
    this.note = note
    this.subject = subject
    this.chapter = chapter
  }
}

class GalaxyGraphData {
  units: KnowledgeUnit[]
  relations: KnowledgeRelation[]

  constructor(units: KnowledgeUnit[], relations: KnowledgeRelation[]) {
    this.units = units
    this.relations = relations
  }
}

@Observed
export class KnowledgeGalaxyViewModel {
  systems: SubjectSystem[] = []
  units: KnowledgeUnit[] = []
  notes: NoteItem[] = []
  totalCount: number = 0
  avgMastery: number = 0

  async load(context: Context): Promise<boolean> {
    try {
      await GalaxyPreviewSeedService.ensureSeeded(context)
      const graphData: GalaxyGraphData = await this.loadPersistedGraph(context)
      const units: KnowledgeUnit[] = graphData.units
      const relations: KnowledgeRelation[] = graphData.relations
      this.units = units
      this.notes = this.unitsToNotes(units)
      this.systems = this.buildSystems(units, this.notes, relations)
      this.totalCount = this.countGalaxyPlanets(this.systems)
      this.avgMastery = this.calcAverageMastery(this.systems)
      return true
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] load failed: " + ((e as Error).message ?? String(e)))
      this.units = []
      this.notes = []
      this.systems = []
      this.totalCount = 0
      this.avgMastery = 0
      return false
    }
  }

  private async loadPersistedGraph(context: Context): Promise<GalaxyGraphData> {
    try {
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      const units: KnowledgeUnit[] = await new NoteDao(store).queryAllGraphMetadata()
      const relations: KnowledgeRelation[] = await new KnowledgeRelationDao(store).queryAcceptedEdges()
      return new GalaxyGraphData(units, relations)
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] persisted graph load failed: " + ((e as Error).message ?? String(e)))
      return new GalaxyGraphData([], [])
    }
  }

  async loadNote(context: Context, id: string): Promise<KnowledgeUnit | null> {
    if (id.length === 0) {
      return null
    }
    try {
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      return await new NoteDao(store).queryById(id)
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] loadNote failed: " + ((e as Error).message ?? String(e)))
      return null
    }
  }

  async deleteNote(context: Context, id: string): Promise<boolean> {
    if (id.length === 0) {
      return false
    }
    try {
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      await new NoteDao(store).deleteById(id)
      UiDataCacheService.notifyNoteChanged(id)
      return await this.load(context)
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] deleteNote failed: " + ((e as Error).message ?? String(e)))
      return false
    }
  }

  private unitsToNotes(units: KnowledgeUnit[]): NoteItem[] {
    const notes: NoteItem[] = []
    for (const unit of units) {
      notes.push(unitToNoteItem(unit))
    }
    return notes
  }

  private buildSystems(units: KnowledgeUnit[], notes: NoteItem[], relations: KnowledgeRelation[]): SubjectSystem[] {
    const subjectNames: string[] = []
    const subjectBundles: UnitBundle[][] = []

    let unitIndex: number = 0
    while (unitIndex < units.length) {
      const unit: KnowledgeUnit = units[unitIndex]
      const note: NoteItem = notes[unitIndex]
      if (this.isWrongNote(note)) {
        unitIndex++
        continue
      }
      const subject: string = this.resolveSubject(note)
      const chapter: string = this.resolveChapter(unit)
      const bundle: UnitBundle = new UnitBundle(unit, note, subject, chapter)
      let index: number = subjectNames.indexOf(subject)
      if (index < 0) {
        subjectNames.push(subject)
        subjectBundles.push([])
        index = subjectNames.length - 1
      }
      subjectBundles[index].push(bundle)
      unitIndex++
    }

    const allBundles: UnitBundle[] = this.flattenBundles(subjectBundles)
    const globalLinks: GalaxyLink[] = this.buildLinks(allBundles, relations)
    const systems: SubjectSystem[] = []
    let index: number = 0
    while (index < subjectNames.length) {
      const orbits: ChapterOrbit[] = this.buildChapterOrbits(subjectBundles[index])
      const planets: PlanetNode[] = this.flattenPlanets(orbits)
      const links: GalaxyLink[] = this.linksFromPlanets(globalLinks, planets)
      const mastery: number = this.calcPlanetMastery(planets)
      const count: number = planets.length
      const size: number = this.clamp(38 + Math.sqrt(count) * 5 + mastery * 8, 46, 76)
      systems.push(new SubjectSystem(
        subjectNames[index],
        subjectColor(subjectNames[index], index),
        count,
        mastery,
        0,
        0,
        size,
        planets,
        orbits,
        links,
      ))
      index++
    }

    systems.sort((a: SubjectSystem, b: SubjectSystem): number => {
      return b.count - a.count
    })
    this.applyUniverseLayout(systems)
    return systems
  }

  private flattenBundles(groups: UnitBundle[][]): UnitBundle[] {
    const bundles: UnitBundle[] = []
    for (const group of groups) {
      for (const bundle of group) {
        bundles.push(bundle)
      }
    }
    return bundles
  }

  private linksFromPlanets(links: GalaxyLink[], planets: PlanetNode[]): GalaxyLink[] {
    const planetIds: string[] = planets.map((planet: PlanetNode): string => planet.id)
    return links.filter((link: GalaxyLink): boolean => planetIds.indexOf(link.fromId) >= 0)
  }

  private buildChapterOrbits(bundles: UnitBundle[]): ChapterOrbit[] {
    const chapterNames: string[] = []
    const chapterBundles: UnitBundle[][] = []

    for (const bundle of bundles) {
      let index: number = chapterNames.indexOf(bundle.chapter)
      if (index < 0) {
        chapterNames.push(bundle.chapter)
        chapterBundles.push([])
        index = chapterNames.length - 1
      }
      chapterBundles[index].push(bundle)
    }

    const orbits: ChapterOrbit[] = []
    let index: number = 0
    while (index < chapterNames.length) {
      const planets: PlanetNode[] = this.buildPlanets(chapterBundles[index])
      const mastery: number = this.calcPlanetMastery(planets)
      const radiusX: number = Math.min(164, 92 + index * 26)
      const radiusY: number = Math.min(82, 32 + index * 12)
      const tilt: number = this.orbitTilt(index)
      const labelX: number = 180 + Math.cos((18 + index * 47) * Math.PI / 180) * (radiusX + 6)
      const labelY: number = 180 + Math.sin((18 + index * 47) * Math.PI / 180) * (radiusY + 16)
      orbits.push(new ChapterOrbit(
        chapterNames[index],
        planets.length,
        mastery,
        radiusX,
        radiusY,
        tilt,
        labelX,
        labelY,
        planets,
      ))
      index++
    }

    orbits.sort((a: ChapterOrbit, b: ChapterOrbit): number => b.count - a.count)
    this.reapplyOrbitLayout(orbits)
    return orbits
  }

  private reapplyOrbitLayout(orbits: ChapterOrbit[]): void {
    let index: number = 0
    while (index < orbits.length) {
      const orbit: ChapterOrbit = orbits[index]
      orbit.radiusX = Math.min(164, 92 + index * 26)
      orbit.radiusY = Math.min(82, 32 + index * 12)
      orbit.tilt = this.orbitTilt(index)
      orbit.labelX = 180 + Math.cos((18 + index * 47) * Math.PI / 180) * (orbit.radiusX + 6)
      orbit.labelY = 180 + Math.sin((18 + index * 47) * Math.PI / 180) * (orbit.radiusY + 16)
      index++
    }
  }

  private buildPlanets(bundles: UnitBundle[]): PlanetNode[] {
    const planets: PlanetNode[] = []
    const count: number = bundles.length
    let index: number = 0
    while (index < count) {
      const bundle: UnitBundle = bundles[index]
      const mastery: number = Math.max(0, Math.min(1, bundle.note.conf))
      const angle: number = count <= 0 ? 0 : ((360 / count) * index + (index % 2) * 18) % 360
      const speed: number = 0.42 + (index % 4) * 0.07
      const size: number = 19 + mastery * 13 + Math.min(7, Math.sqrt(Math.max(1, bundle.unit.repetitions)) * 1.8)
      const alpha: number = Math.max(0.46, Math.min(1, mastery + 0.2))
      planets.push(new PlanetNode(
        bundle.unit.id,
        bundle.note,
        bundle.unit,
        bundle.subject,
        bundle.chapter,
        bundle.note.type,
        typeColor(bundle.note.type),
        angle,
        speed,
        size,
        mastery,
        alpha,
      ))
      index++
    }
    return planets
  }

  private buildLinks(bundles: UnitBundle[], relations: KnowledgeRelation[]): GalaxyLink[] {
    const links: GalaxyLink[] = []
    const prerequisiteKeys: string[] = []
    const relatedKeys: string[] = []

    for (const relation of relations) {
      if (relation.status !== "accepted") {
        continue
      }
      if (relation.relationType === "prerequisite") {
        const fromBundle: UnitBundle | null = this.findBundleById(bundles, relation.fromUnitId)
        const toBundle: UnitBundle | null = this.findBundleById(bundles, relation.toUnitId)
        if (fromBundle !== null && toBundle !== null && fromBundle.unit.id !== toBundle.unit.id) {
          const key: string = fromBundle.unit.id + "->" + toBundle.unit.id
          if (prerequisiteKeys.indexOf(key) < 0) {
            prerequisiteKeys.push(key)
            links.push(new GalaxyLink(
              fromBundle.unit.id,
              toBundle.unit.id,
              "prerequisite",
              fromBundle.chapter,
              toBundle.chapter,
            ))
          }
        }
      } else if (relation.relationType === "related") {
        const fromBundle: UnitBundle | null = this.findBundleById(bundles, relation.fromUnitId)
        const toBundle: UnitBundle | null = this.findBundleById(bundles, relation.toUnitId)
        if (fromBundle !== null && toBundle !== null && fromBundle.unit.id !== toBundle.unit.id) {
          const key: string = this.relatedKey(fromBundle.unit.id, toBundle.unit.id)
          if (relatedKeys.indexOf(key) < 0) {
            relatedKeys.push(key)
            links.push(new GalaxyLink(
              fromBundle.unit.id,
              toBundle.unit.id,
              "related",
              fromBundle.chapter,
              toBundle.chapter,
            ))
          }
        }
      }
    }

    return links
  }

  private findBundleById(bundles: UnitBundle[], id: string): UnitBundle | null {
    const normalizedId: string = id.trim()
    if (normalizedId.length === 0) {
      return null
    }
    for (const bundle of bundles) {
      if (bundle.unit.id === normalizedId) {
        return bundle
      }
    }
    return null
  }

  private relatedKey(leftId: string, rightId: string): string {
    if (leftId < rightId) {
      return leftId + "->" + rightId
    }
    return rightId + "->" + leftId
  }

  private flattenPlanets(orbits: ChapterOrbit[]): PlanetNode[] {
    const planets: PlanetNode[] = []
    for (const orbit of orbits) {
      for (const planet of orbit.planets) {
        planets.push(planet)
      }
    }
    return planets
  }

  private applyUniverseLayout(systems: SubjectSystem[]): void {
    const count: number = systems.length
    if (count === 0) {
      return
    }
    const stageWidth: number = 360
    const stageHeight: number = 520
    if (count === 1) {
      this.placeSystem(systems[0], stageWidth * 0.5, stageHeight * 0.33)
      return
    }

    const slotX: number[] = [0.52, 0.25, 0.76, 0.34, 0.67, 0.18, 0.85, 0.50]
    const slotY: number[] = [0.24, 0.42, 0.40, 0.62, 0.65, 0.23, 0.64, 0.80]
    const densityScale: number = count <= 3 ? 1 : (count <= 6 ? 0.88 : 0.74)
    let index: number = 0
    while (index < count) {
      const system: SubjectSystem = systems[index]
      system.size = this.clamp(system.size * densityScale, 42, 76)
      if (index < slotX.length) {
        this.placeSystem(system, stageWidth * slotX[index], stageHeight * slotY[index])
      } else {
        const angle: number = -90 + index * 360 / count
        const radians: number = angle * Math.PI / 180
        const ringX: number = 128
        const ringY: number = 190
        this.placeSystem(
          system,
          stageWidth * 0.5 + Math.cos(radians) * ringX,
          stageHeight * 0.52 + Math.sin(radians) * ringY,
        )
      }
      index++
    }
  }

  private placeSystem(system: SubjectSystem, centerX: number, centerY: number): void {
    system.x = this.clamp(centerX - (system.size + 122) / 2, 0, 360 - (system.size + 122))
    system.y = this.clamp(centerY - (system.size + 118) / 2, 0, 520 - (system.size + 118))
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value))
  }

  private orbitTilt(index: number): number {
    const tilts: number[] = [-7, 9, -14, 16, -3, 12]
    return tilts[index % tilts.length]
  }

  private resolveSubject(note: NoteItem): string {
    const subject: string = note.subject.trim()
    return subject.length > 0 ? subject : UNCLASSIFIED_SUBJECT
  }

  private resolveChapter(unit: KnowledgeUnit): string {
    const chapter: string = unit.chapter.trim()
    return chapter.length > 0 ? chapter : UNCLASSIFIED_CHAPTER
  }

  private isWrongNote(note: NoteItem): boolean {
    return note.type.trim() === WRONG_NOTE_TYPE
  }

  private calcPlanetMastery(planets: PlanetNode[]): number {
    if (planets.length === 0) {
      return 0
    }
    let total: number = 0
    for (const planet of planets) {
      total += planet.mastery
    }
    return Math.round((total / planets.length) * 100) / 100
  }

  private calcAverageMastery(systems: SubjectSystem[]): number {
    let total: number = 0
    let count: number = 0
    for (const system of systems) {
      total += system.mastery * system.count
      count += system.count
    }
    if (count === 0) {
      return 0
    }
    return Math.round((total / count) * 100) / 100
  }

  private countGalaxyPlanets(systems: SubjectSystem[]): number {
    let count: number = 0
    for (const system of systems) {
      count += system.count
    }
    return count
  }
}
