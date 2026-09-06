// ============================================================================
//  viewmodels/KnowledgeGalaxyViewModel.ets - review knowledge galaxy data logic
// ============================================================================

import { relationalStore } from '@kit.ArkData'
import { DatabaseHelper, DifficultyLevel, KnowledgeUnit, NoteItem, ReviewStatus, subjectColor, typeColor } from "common"
import { NoteDao } from "../database/NoteDao"
import { unitToNoteItem } from "../utils/NoteItemMapper"

const UNCLASSIFIED_SUBJECT: string = "未分类"
const UNCLASSIFIED_CHAPTER: string = "未分章节"
const WRONG_NOTE_TYPE: string = "错题"
const ENABLE_GALAXY_PREVIEW_UNITS: boolean = false
const PREVIEW_UNIT_PREFIX: string = "galaxy_preview_"

function previewUnit(
  id: string,
  title: string,
  subject: string,
  category: string,
  chapter: string,
  summary: string,
  prerequisites: string[],
  related: string[],
  repetitions: number,
  reviewStatus: ReviewStatus,
): KnowledgeUnit {
  const now: number = Date.now()
  return {
    id: PREVIEW_UNIT_PREFIX + id,
    title: title,
    content: summary,
    summary: summary,
    tags: [subject, category, chapter],
    subject: subject,
    category: category,
    chapter: chapter,
    difficulty: DifficultyLevel.MEDIUM,
    source: "manual",
    createdAt: now - repetitions * 86400000,
    updatedAt: now - repetitions * 3600000,
    reviewStatus: reviewStatus,
    nextReviewAt: now,
    intervalDays: Math.max(1, repetitions),
    easeFactor: 2.5,
    repetitions: repetitions,
    prerequisites: prerequisites,
    related: related,
    embedding: [],
    userId: "preview",
    version: 1,
  }
}

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

@Observed
export class KnowledgeGalaxyViewModel {
  systems: SubjectSystem[] = []
  units: KnowledgeUnit[] = []
  notes: NoteItem[] = []
  totalCount: number = 0
  avgMastery: number = 0

  async load(context: Context): Promise<boolean> {
    try {
      const units: KnowledgeUnit[] = this.withPreviewUnits(await this.loadPersistedUnits(context))
      this.units = units
      this.notes = this.unitsToNotes(units)
      this.systems = this.buildSystems(units, this.notes)
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

  private async loadPersistedUnits(context: Context): Promise<KnowledgeUnit[]> {
    try {
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      return await new NoteDao(store).queryAll()
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] persisted load failed: " + ((e as Error).message ?? String(e)))
      return []
    }
  }

  async loadNote(context: Context, id: string): Promise<KnowledgeUnit | null> {
    if (id.length === 0) {
      return null
    }
    const previewUnit: KnowledgeUnit | null = this.findLoadedPreviewUnit(id)
    if (previewUnit !== null) {
      return previewUnit
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
    if (this.isPreviewUnitId(id)) {
      return false
    }
    try {
      const store: relationalStore.RdbStore = await DatabaseHelper.init(context)
      await new NoteDao(store).deleteById(id)
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

  private withPreviewUnits(units: KnowledgeUnit[]): KnowledgeUnit[] {
    if (!ENABLE_GALAXY_PREVIEW_UNITS) {
      return units
    }
    const result: KnowledgeUnit[] = units.slice(0)
    for (const unit of this.previewUnits()) {
      if (!this.hasUnitId(result, unit.id)) {
        result.push(unit)
      }
    }
    return result
  }

  private hasUnitId(units: KnowledgeUnit[], id: string): boolean {
    for (const unit of units) {
      if (unit.id === id) {
        return true
      }
    }
    return false
  }

  private findLoadedPreviewUnit(id: string): KnowledgeUnit | null {
    if (!this.isPreviewUnitId(id)) {
      return null
    }
    for (const unit of this.units) {
      if (unit.id === id) {
        return unit
      }
    }
    return null
  }

  private isPreviewUnitId(id: string): boolean {
    return id.indexOf(PREVIEW_UNIT_PREFIX) === 0
  }

  private previewUnits(): KnowledgeUnit[] {
    const units: KnowledgeUnit[] = []
    units.push(previewUnit(
      "limit_definition",
      "数列与函数极限定义",
      "示例：数学分析",
      "概念",
      "极限",
      "用 epsilon-delta 语言描述函数趋近，作为连续、导数和级数判别的基础。",
      [],
      [PREVIEW_UNIT_PREFIX + "limit_laws", PREVIEW_UNIT_PREFIX + "continuity"],
      2,
      ReviewStatus.LEARNING,
    ))
    units.push(previewUnit(
      "limit_laws",
      "极限四则运算法则",
      "示例：数学分析",
      "定理",
      "极限",
      "在极限存在的条件下，和、差、积、商的极限可分别运算。",
      [PREVIEW_UNIT_PREFIX + "limit_definition"],
      [PREVIEW_UNIT_PREFIX + "continuity", PREVIEW_UNIT_PREFIX + "limit_definition"],
      5,
      ReviewStatus.REVIEW,
    ))
    units.push(previewUnit(
      "continuity",
      "连续性的局部性质",
      "示例：数学分析",
      "概念",
      "连续函数",
      "连续函数在一点附近保持有界、保号，并可与极限运算法则配合使用。",
      [PREVIEW_UNIT_PREFIX + "limit_definition"],
      [PREVIEW_UNIT_PREFIX + "limit_laws", PREVIEW_UNIT_PREFIX + "limit_definition"],
      4,
      ReviewStatus.REVIEW,
    ))
    units.push(previewUnit(
      "derivative_definition",
      "导数定义与几何意义",
      "示例：数学分析",
      "概念",
      "导数与微分",
      "导数是差商极限，表示曲线切线斜率和瞬时变化率。",
      [PREVIEW_UNIT_PREFIX + "limit_definition", PREVIEW_UNIT_PREFIX + "continuity"],
      [PREVIEW_UNIT_PREFIX + "lagrange_mvt", PREVIEW_UNIT_PREFIX + "taylor_formula"],
      7,
      ReviewStatus.GRADUATED,
    ))
    units.push(previewUnit(
      "lagrange_mvt",
      "拉格朗日中值定理",
      "示例：数学分析",
      "定理",
      "微分中值定理",
      "若函数闭区间连续、开区间可导，则存在一点使导数等于割线斜率。",
      [PREVIEW_UNIT_PREFIX + "derivative_definition", PREVIEW_UNIT_PREFIX + "continuity"],
      [PREVIEW_UNIT_PREFIX + "taylor_formula", PREVIEW_UNIT_PREFIX + "derivative_definition"],
      8,
      ReviewStatus.GRADUATED,
    ))
    units.push(previewUnit(
      "taylor_formula",
      "泰勒公式余项估计",
      "示例：数学分析",
      "公式",
      "泰勒公式",
      "用多项式近似函数，并通过余项控制误差，是极限与近似计算的核心工具。",
      [PREVIEW_UNIT_PREFIX + "lagrange_mvt", PREVIEW_UNIT_PREFIX + "derivative_definition"],
      [
        PREVIEW_UNIT_PREFIX + "lagrange_mvt",
        PREVIEW_UNIT_PREFIX + "derivative_definition",
        PREVIEW_UNIT_PREFIX + "missing_note",
        PREVIEW_UNIT_PREFIX + "sign_error_wrong",
        PREVIEW_UNIT_PREFIX + "matrix_inverse",
      ],
      6,
      ReviewStatus.REVIEW,
    ))
    units.push(previewUnit(
      "sign_error_wrong",
      "泰勒展开符号错题",
      "示例：数学分析",
      WRONG_NOTE_TYPE,
      "泰勒公式",
      "错题示例：这条不应进入知识星系，也不应参与关系线。",
      [PREVIEW_UNIT_PREFIX + "taylor_formula"],
      [],
      1,
      ReviewStatus.LAPSED,
    ))
    units.push(previewUnit(
      "vector_linear_dependence",
      "向量组线性相关",
      "示例：线性代数",
      "概念",
      "向量空间",
      "存在不全为零的系数组合为零向量时，向量组线性相关。",
      [],
      [PREVIEW_UNIT_PREFIX + "matrix_rank"],
      3,
      ReviewStatus.LEARNING,
    ))
    units.push(previewUnit(
      "matrix_rank",
      "矩阵秩与初等变换",
      "示例：线性代数",
      "计算题",
      "矩阵",
      "矩阵秩可通过初等行变换化阶梯形后读取非零行数。",
      [PREVIEW_UNIT_PREFIX + "vector_linear_dependence"],
      [PREVIEW_UNIT_PREFIX + "determinant"],
      5,
      ReviewStatus.REVIEW,
    ))
    units.push(previewUnit(
      "determinant",
      "行列式按行展开",
      "示例：线性代数",
      "公式",
      "行列式",
      "按某一行或列展开可将高阶行列式化为代数余子式的组合。",
      [],
      [PREVIEW_UNIT_PREFIX + "matrix_inverse", PREVIEW_UNIT_PREFIX + "matrix_rank"],
      4,
      ReviewStatus.REVIEW,
    ))
    units.push(previewUnit(
      "matrix_inverse",
      "可逆矩阵判定",
      "示例：线性代数",
      "定理",
      "矩阵",
      "方阵可逆等价于行列式非零，也等价于满秩。",
      [PREVIEW_UNIT_PREFIX + "determinant", PREVIEW_UNIT_PREFIX + "matrix_rank"],
      [PREVIEW_UNIT_PREFIX + "determinant"],
      9,
      ReviewStatus.GRADUATED,
    ))
    return units
  }

  private buildSystems(units: KnowledgeUnit[], notes: NoteItem[]): SubjectSystem[] {
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

    const systems: SubjectSystem[] = []
    let index: number = 0
    while (index < subjectNames.length) {
      const orbits: ChapterOrbit[] = this.buildChapterOrbits(subjectBundles[index])
      const planets: PlanetNode[] = this.flattenPlanets(orbits)
      const links: GalaxyLink[] = this.buildLinks(subjectBundles[index])
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
      const previewDelta: number = this.previewSubjectRank(a.subject) - this.previewSubjectRank(b.subject)
      if (previewDelta !== 0) {
        return previewDelta
      }
      return b.count - a.count
    })
    this.applyUniverseLayout(systems)
    return systems
  }

  private previewSubjectRank(subject: string): number {
    if (!ENABLE_GALAXY_PREVIEW_UNITS) {
      return 1
    }
    return subject.indexOf("示例：") === 0 ? 0 : 1
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

  private buildLinks(bundles: UnitBundle[]): GalaxyLink[] {
    const links: GalaxyLink[] = []
    const prerequisiteKeys: string[] = []
    const relatedKeys: string[] = []

    for (const bundle of bundles) {
      for (const prerequisiteId of bundle.unit.prerequisites) {
        const fromBundle: UnitBundle | null = this.findBundleById(bundles, prerequisiteId)
        if (fromBundle !== null && fromBundle.unit.id !== bundle.unit.id) {
          const key: string = fromBundle.unit.id + "->" + bundle.unit.id
          if (prerequisiteKeys.indexOf(key) < 0) {
            prerequisiteKeys.push(key)
            links.push(new GalaxyLink(
              fromBundle.unit.id,
              bundle.unit.id,
              "prerequisite",
              fromBundle.chapter,
              bundle.chapter,
            ))
          }
        }
      }

      for (const relatedId of bundle.unit.related) {
        const relatedBundle: UnitBundle | null = this.findBundleById(bundles, relatedId)
        if (relatedBundle !== null && relatedBundle.unit.id !== bundle.unit.id) {
          const key: string = this.relatedKey(bundle.unit.id, relatedBundle.unit.id)
          if (relatedKeys.indexOf(key) < 0) {
            relatedKeys.push(key)
            links.push(new GalaxyLink(
              bundle.unit.id,
              relatedBundle.unit.id,
              "related",
              bundle.chapter,
              relatedBundle.chapter,
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
