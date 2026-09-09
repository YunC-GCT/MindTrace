// ============================================================================
//  viewmodels/KnowledgeGalaxyViewModel.ets - review knowledge galaxy data logic
// ============================================================================

import { preferences, relationalStore } from '@kit.ArkData'
import { DatabaseHelper, DifficultyLevel, KnowledgeUnit, NoteItem, ReviewStatus, subjectColor, typeColor } from "common"
import { NoteDao } from "../database/NoteDao"
import { unitToNoteItem } from "../utils/NoteItemMapper"

const UNCLASSIFIED_SUBJECT: string = "未分类"
const UNCLASSIFIED_CHAPTER: string = "未分章节"
const WRONG_NOTE_TYPE: string = "错题"
const ENABLE_GALAXY_RDB_SAMPLE_NOTES: boolean = true
const GALAXY_SAMPLE_STORE_NAME: string = "galaxy_sample_notes"
const GALAXY_SAMPLE_SEEDED_KEY: string = "seeded_v1"
const SAMPLE_UNIT_PREFIX: string = "galaxy_note_"

function sampleUnit(
  id: string,
  title: string,
  subject: string,
  category: string,
  chapter: string,
  summary: string,
  content: string,
  prerequisites: string[],
  related: string[],
  repetitions: number,
  reviewStatus: ReviewStatus,
): KnowledgeUnit {
  const now: number = Date.now()
  return {
    id: SAMPLE_UNIT_PREFIX + id,
    title: title,
    content: content,
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
    userId: "local_sample",
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
      const units: KnowledgeUnit[] = await this.loadPersistedUnits(context)
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
      const dao: NoteDao = new NoteDao(store)
      const units: KnowledgeUnit[] = await dao.queryAll()
      return await this.withRdbSampleNotes(context, dao, units)
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] persisted load failed: " + ((e as Error).message ?? String(e)))
      return []
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

  private hasUnitId(units: KnowledgeUnit[], id: string): boolean {
    for (const unit of units) {
      if (unit.id === id) {
        return true
      }
    }
    return false
  }

  private async withRdbSampleNotes(context: Context, dao: NoteDao, units: KnowledgeUnit[]): Promise<KnowledgeUnit[]> {
    if (!ENABLE_GALAXY_RDB_SAMPLE_NOTES) {
      return units
    }
    const seeded: boolean = await this.isRdbSampleSeeded(context)
    if (seeded) {
      return units
    }

    let inserted: boolean = false
    for (const unit of this.sampleUnits()) {
      if (!this.hasUnitId(units, unit.id)) {
        await dao.insert(unit)
        inserted = true
      }
    }
    await this.markRdbSampleSeeded(context)
    if (inserted) {
      this.bumpNotesVersion()
    }
    return inserted ? await dao.queryAll() : units
  }

  private bumpNotesVersion(): void {
    try {
      const version: number = AppStorage.get<number>("notesVersion") ?? 0
      AppStorage.setOrCreate("notesVersion", version + 1)
    } catch (_e) {}
  }

  private async isRdbSampleSeeded(context: Context): Promise<boolean> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, GALAXY_SAMPLE_STORE_NAME)
      return await store.get(GALAXY_SAMPLE_SEEDED_KEY, false) as boolean
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] sample seed flag read failed: " + ((e as Error).message ?? String(e)))
      return false
    }
  }

  private async markRdbSampleSeeded(context: Context): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, GALAXY_SAMPLE_STORE_NAME)
      await store.put(GALAXY_SAMPLE_SEEDED_KEY, true)
      await store.flush()
    } catch (e) {
      console.warn("[KnowledgeGalaxyViewModel] sample seed flag write failed: " + ((e as Error).message ?? String(e)))
    }
  }

  private sampleUnits(): KnowledgeUnit[] {
    const units: KnowledgeUnit[] = []
    units.push(sampleUnit(
      "limit_definition",
      "数列与函数极限定义",
      "数学分析",
      "概念",
      "极限",
      "用 epsilon-delta 语言描述函数趋近，作为连续、导数和级数判别的基础。",
      "极限描述的是变量在某个过程中无限接近某个确定值。\n\n函数极限常写作 lim_{x -> a} f(x) = L。严格定义是：对任意 epsilon > 0，存在 delta > 0，使得当 0 < |x-a| < delta 时，有 |f(x)-L| < epsilon。\n\n学习重点：先判断自变量趋近的过程，再证明函数值可以被控制到任意小的误差内。",
      [],
      [SAMPLE_UNIT_PREFIX + "limit_laws", SAMPLE_UNIT_PREFIX + "continuity"],
      2,
      ReviewStatus.LEARNING,
    ))
    units.push(sampleUnit(
      "limit_laws",
      "极限四则运算法则",
      "数学分析",
      "定理",
      "极限",
      "在极限存在的条件下，和、差、积、商的极限可分别运算。",
      "若 lim f(x)=A，lim g(x)=B，则 lim(f+g)=A+B，lim(fg)=AB。当 B 不等于 0 时，lim(f/g)=A/B。\n\n使用时要先确认两个极限都存在；商法则还要确认分母极限不为 0。很多计算题的错误来自直接套公式而忘记检查条件。",
      [SAMPLE_UNIT_PREFIX + "limit_definition"],
      [SAMPLE_UNIT_PREFIX + "continuity", SAMPLE_UNIT_PREFIX + "limit_definition"],
      5,
      ReviewStatus.REVIEW,
    ))
    units.push(sampleUnit(
      "continuity",
      "连续性的局部性质",
      "数学分析",
      "概念",
      "连续函数",
      "连续函数在一点附近保持有界、保号，并可与极限运算法则配合使用。",
      "函数 f 在点 x0 连续，等价于 lim_{x -> x0} f(x)=f(x0)。\n\n常用局部性质包括局部有界性、局部保号性，以及连续函数经过四则运算后在合法条件下仍连续。证明时经常把连续性转化为极限定义，再使用极限运算法则。",
      [SAMPLE_UNIT_PREFIX + "limit_definition"],
      [SAMPLE_UNIT_PREFIX + "limit_laws", SAMPLE_UNIT_PREFIX + "limit_definition"],
      4,
      ReviewStatus.REVIEW,
    ))
    units.push(sampleUnit(
      "derivative_definition",
      "导数定义与几何意义",
      "数学分析",
      "概念",
      "导数与微分",
      "导数是差商极限，表示曲线切线斜率和瞬时变化率。",
      "导数定义为 f'(x0)=lim_{h -> 0} [f(x0+h)-f(x0)]/h。它来自差商的极限，几何上表示曲线在该点切线的斜率。\n\n导数存在一定推出连续，但连续不一定可导。做题时常用定义处理分段函数、绝对值函数和参数函数在特殊点的可导性。",
      [SAMPLE_UNIT_PREFIX + "limit_definition", SAMPLE_UNIT_PREFIX + "continuity"],
      [SAMPLE_UNIT_PREFIX + "lagrange_mvt", SAMPLE_UNIT_PREFIX + "taylor_formula"],
      7,
      ReviewStatus.GRADUATED,
    ))
    units.push(sampleUnit(
      "lagrange_mvt",
      "拉格朗日中值定理",
      "数学分析",
      "定理",
      "微分中值定理",
      "若函数闭区间连续、开区间可导，则存在一点使导数等于割线斜率。",
      "若 f 在 [a,b] 上连续，在 (a,b) 内可导，则存在 xi 属于 (a,b)，使 f'(xi) = [f(b)-f(a)]/(b-a)。\n\n它把函数整体变化量和某点导数联系起来，常用于证明不等式、估计函数增量、判断单调性。套用前必须检查闭区间连续与开区间可导。",
      [SAMPLE_UNIT_PREFIX + "derivative_definition", SAMPLE_UNIT_PREFIX + "continuity"],
      [SAMPLE_UNIT_PREFIX + "taylor_formula", SAMPLE_UNIT_PREFIX + "derivative_definition"],
      8,
      ReviewStatus.GRADUATED,
    ))
    units.push(sampleUnit(
      "taylor_formula",
      "泰勒公式余项估计",
      "数学分析",
      "公式",
      "泰勒公式",
      "用多项式近似函数，并通过余项控制误差，是极限与近似计算的核心工具。",
      "泰勒公式把函数在一点附近表示为多项式主部加余项：f(x)=sum_{k=0}^{n} f^{(k)}(a)(x-a)^k/k! + R_n(x)。\n\n常见余项有佩亚诺余项和拉格朗日余项。计算极限时通常保留到第一个非零项；估计误差时要关注余项阶数和适用区间。",
      [SAMPLE_UNIT_PREFIX + "lagrange_mvt", SAMPLE_UNIT_PREFIX + "derivative_definition"],
      [
        SAMPLE_UNIT_PREFIX + "lagrange_mvt",
        SAMPLE_UNIT_PREFIX + "derivative_definition",
        SAMPLE_UNIT_PREFIX + "sign_error_wrong",
        SAMPLE_UNIT_PREFIX + "matrix_inverse",
      ],
      6,
      ReviewStatus.REVIEW,
    ))
    units.push(sampleUnit(
      "sign_error_wrong",
      "泰勒展开符号错题",
      "数学分析",
      WRONG_NOTE_TYPE,
      "泰勒公式",
      "错题示例：这条不应进入知识星系，也不应参与关系线。",
      "错题记录：计算 ln(1-x) 的展开时，把 -x^2/2 误写成 +x^2/2。\n\n正确展开是 ln(1-x) = -x - x^2/2 - x^3/3 - ...。这类题需要先确认基础展开式，再代入变量，最后统一检查符号。",
      [SAMPLE_UNIT_PREFIX + "taylor_formula"],
      [],
      1,
      ReviewStatus.LAPSED,
    ))
    units.push(sampleUnit(
      "vector_linear_dependence",
      "向量组线性相关",
      "线性代数",
      "概念",
      "向量空间",
      "存在不全为零的系数组合为零向量时，向量组线性相关。",
      "向量组 alpha_1,...,alpha_n 线性相关，是指存在不全为 0 的数 k_i，使 k_1 alpha_1 + ... + k_n alpha_n = 0。\n\n判断时可把向量作为列组成矩阵，通过齐次线性方程组是否有非零解、矩阵秩是否小于向量个数来判定。",
      [],
      [SAMPLE_UNIT_PREFIX + "matrix_rank"],
      3,
      ReviewStatus.LEARNING,
    ))
    units.push(sampleUnit(
      "matrix_rank",
      "矩阵秩与初等变换",
      "线性代数",
      "计算题",
      "矩阵",
      "矩阵秩可通过初等行变换化阶梯形后读取非零行数。",
      "矩阵秩是行向量组或列向量组的极大线性无关组中向量个数。实际计算通常做初等行变换，把矩阵化为阶梯形，非零行数就是秩。\n\n秩可用于判断线性方程组解的情况，也可用于判定向量组线性相关性。",
      [SAMPLE_UNIT_PREFIX + "vector_linear_dependence"],
      [SAMPLE_UNIT_PREFIX + "determinant"],
      5,
      ReviewStatus.REVIEW,
    ))
    units.push(sampleUnit(
      "determinant",
      "行列式按行展开",
      "线性代数",
      "公式",
      "行列式",
      "按某一行或列展开可将高阶行列式化为代数余子式的组合。",
      "n 阶行列式可以按第 i 行展开：D = sum_j a_ij A_ij，其中 A_ij 是元素 a_ij 的代数余子式。\n\n选择零元素较多的一行或一列展开可以减少计算量。注意代数余子式符号为 (-1)^{i+j}。",
      [],
      [SAMPLE_UNIT_PREFIX + "matrix_inverse", SAMPLE_UNIT_PREFIX + "matrix_rank"],
      4,
      ReviewStatus.REVIEW,
    ))
    units.push(sampleUnit(
      "matrix_inverse",
      "可逆矩阵判定",
      "线性代数",
      "定理",
      "矩阵",
      "方阵可逆等价于行列式非零，也等价于满秩。",
      "n 阶方阵 A 可逆的等价条件包括：det(A) != 0，rank(A)=n，齐次方程 Ax=0 只有零解，A 的列向量组线性无关。\n\n计算逆矩阵时常用初等变换 [A | I] -> [I | A^{-1}]，前提是 A 能化为单位矩阵。",
      [SAMPLE_UNIT_PREFIX + "determinant", SAMPLE_UNIT_PREFIX + "matrix_rank"],
      [SAMPLE_UNIT_PREFIX + "determinant"],
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
      return b.count - a.count
    })
    this.applyUniverseLayout(systems)
    return systems
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
