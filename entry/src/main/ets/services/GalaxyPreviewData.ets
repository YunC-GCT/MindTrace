/**
 * GalaxyPreviewData.ets — 星系测试数据定义
 * 路径: entry/src/main/ets/services/GalaxyPreviewData.ets
 * 职责: 提供固定 ID 的样例笔记与关系，仅供一次性入库。
 * 依赖: common KnowledgeUnit / KnowledgeRelation。
 * 数据流: GalaxyPreviewSeedService → 样例定义 → RDB。
 */
import { DifficultyLevel, KnowledgeRelation, KnowledgeUnit, ReviewStatus } from 'common';
const WRONG_NOTE_TYPE: string = "错题";
export const ENABLE_GALAXY_PREVIEW_UNITS: boolean = true;
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
  content: string = "",
): KnowledgeUnit {
  const now: number = Date.now()
  return {
    id: PREVIEW_UNIT_PREFIX + id,
    title: title,
    content: content.length > 0 ? content : summary,
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


export class GalaxyPreviewData {
  private isPreviewUnitId(id: string): boolean {
    return id.indexOf(PREVIEW_UNIT_PREFIX) === 0;
  }

  units(): KnowledgeUnit[] {
    const units: KnowledgeUnit[] = []
    units.push(previewUnit(
      "limit_definition",
      "数列与函数极限定义",
      "数学分析",
      "概念",
      "极限",
      "极限用 epsilon-delta 语言精确描述函数趋近，是连续、导数和级数判别的基础。",
      [],
      [PREVIEW_UNIT_PREFIX + "limit_laws", PREVIEW_UNIT_PREFIX + "continuity"],
      2,
      ReviewStatus.LEARNING,
      "极限用 epsilon-delta 语言精确描述函数的趋近过程，是连续、导数和级数判别的基础。\n\n"
        + "函数极限的定义为：\n\n$$\n"
        + "\\forall \\varepsilon>0,\\ \exists \\delta>0,\\ 0<|x-x_0|<\\delta"
        + "\\Longrightarrow |f(x)-A|<\\varepsilon.\n$$\n\n"
        + "数列极限可写成：\n\n$$\n"
        + "\\forall \\varepsilon>0,\\ \exists N\\in\\mathbb{N},\\ n>N"
        + "\\Longrightarrow |a_n-A|<\\varepsilon.\n$$\n\n"
        + "若两个函数的极限分别存在，则可进一步讨论复合函数、"
        + "四则运算以及夹逼定理。",
    ))
    units.push(previewUnit(
      "limit_laws",
      "极限四则运算法则",
      "数学分析",
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
      "数学分析",
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
      "数学分析",
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
      "数学分析",
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
      "数学分析",
      "公式",
      "泰勒公式",
      "泰勒公式用多项式近似函数，并通过余项控制误差。",
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
      "泰勒公式用多项式近似函数，并通过余项控制误差，是极限与近似计算的核心工具。\n\n"
        + "在展开点附近的 n 阶展开为：\n\n$$\n"
        + "f(x)=\\sum_{k=0}^{n}\\frac{f^{(k)}(x_0)}{k!}(x-x_0)^k+R_n(x).\n$$\n\n"
        + "拉格朗日余项给出显式误差：\n\n$$\n"
        + "R_n(x)=\\frac{f^{(n+1)}(\\xi)}{(n+1)!}(x-x_0)^{n+1},"
        + "\\qquad \\xi\\in(x_0,x).\n$$\n\n"
        + "积分余项形式为：\n\n$$\n"
        + "R_n(x)=\\frac{1}{n!}\\int_{x_0}^{x}f^{(n+1)}(t)(x-t)^n\\,dt.\n$$\n\n"
        + "例如指数函数满足：\n\n$$\n"
        + "e^x=1+x+\\frac{x^2}{2!}+\\frac{x^3}{3!}+\\cdots"
        + "+\\frac{x^n}{n!}+\\frac{e^{\\xi}x^{n+1}}{(n+1)!}.\n$$",
    ))
    units.push(previewUnit(
      "sign_error_wrong",
      "泰勒展开符号错题",
      "数学分析",
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
      "线性代数",
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
      "线性代数",
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
      "线性代数",
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
      "线性代数",
      "定理",
      "矩阵",
      "方阵可逆、行列式非零、满秩以及齐次方程只有零解彼此等价。",
      [PREVIEW_UNIT_PREFIX + "determinant", PREVIEW_UNIT_PREFIX + "matrix_rank"],
      [PREVIEW_UNIT_PREFIX + "determinant"],
      9,
      ReviewStatus.GRADUATED,
      "方阵可逆、行列式非零、满秩以及齐次方程只有零解彼此等价。\n\n"
        + "对 n 阶方阵，核心等价关系为：\n\n$$\n"
        + "A\\text{ 可逆}\\Longleftrightarrow \\det(A)\\ne 0"
        + "\\Longleftrightarrow \\operatorname{rank}(A)=n"
        + "\\Longleftrightarrow \\ker(A)=\\{0\\}.\n$$\n\n"
        + "伴随矩阵公式为：\n\n$$\n"
        + "A^{-1}=\\frac{1}{\\det(A)}\\operatorname{adj}(A),\\qquad \\det(A)\\ne0.\n$$\n\n"
        + "线性方程组的唯一解可由逆矩阵求得，也可由克拉默法则表示：\n\n$$\n"
        + "x_i=\\frac{\\det(A_i)}{\\det(A)},\\qquad i=1,2,\\ldots,n.\n$$",
    ))
    return units
  }

  relations(units: KnowledgeUnit[]): KnowledgeRelation[] {
    const relations: KnowledgeRelation[] = []
    for (const unit of units) {
      if (!this.isPreviewUnitId(unit.id)) {
        continue
      }
      for (const prerequisiteId of unit.prerequisites) {
        if (this.isPreviewUnitId(prerequisiteId) && prerequisiteId !== unit.id) {
          relations.push(this.toPreviewRelation(prerequisiteId, unit.id, "prerequisite"))
        }
      }
      for (const relatedId of unit.related) {
        if (this.isPreviewUnitId(relatedId) && relatedId !== unit.id) {
          const fromId: string = unit.id < relatedId ? unit.id : relatedId
          const toId: string = unit.id < relatedId ? relatedId : unit.id
          if (!this.hasPreviewRelatedRelation(relations, fromId, toId)) {
            relations.push(this.toPreviewRelation(fromId, toId, "related"))
          }
        }
      }
    }
    return relations
  }

  private toPreviewRelation(fromUnitId: string, toUnitId: string, relationType: "prerequisite" | "related"): KnowledgeRelation {
    const now: number = Date.now()
    return {
      id: "preview_relation_" + fromUnitId + "_" + relationType + "_" + toUnitId,
      fromUnitId: fromUnitId,
      toUnitId: toUnitId,
      relationType: relationType,
      source: "manual",
      status: "accepted",
      confidence: 1,
      weight: 1,
      reason: "preview",
      createdAt: now,
      updatedAt: now,
      version: 1,
    }
  }

  private hasPreviewRelatedRelation(relations: KnowledgeRelation[], fromUnitId: string, toUnitId: string): boolean {
    for (const relation of relations) {
      if (relation.relationType === "related"
        && relation.fromUnitId === fromUnitId
        && relation.toUnitId === toUnitId) {
        return true
      }
    }
    return false
  }

}
