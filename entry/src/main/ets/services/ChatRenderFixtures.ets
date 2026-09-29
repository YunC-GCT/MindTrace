/**
 * ChatRenderFixtures.ets — chat 渲染基准确定性 fixtures 与冻结指标/统计/预算推导纯函数
 *
 * 路径: entry/src/main/ets/services/ChatRenderFixtures.ets
 * 职责: 定义 A/B/C/C′ 四组确定性 fixture(每组恰 2000 UTF-16 code-unit,公式数 0/2/6/6),
 *       并冻结 percentile(p50/p95)、visible 判定、长帧规则、时序指标(T_firstDeltaToVisible /
 *       finish→visible / T_finishToStable)与渲染调度器预算推导公式。
 *       本文件为纯逻辑,无 UI/网络/LLM/随机依赖。
 * 依赖: 无外部模块
 *
 * 数据流:
 *   fixture 常量/运行样本 → 纯函数 → 统计结果/预算提案
 *
 * 设计要点:
 *   - 四组 fixture 共享同一确定性基础文本;公式槽以等长替换保持总长 2000 code-unit。
 *   - C′ 的 6 个公式排列为 3 对连续闭合(对间仅 1 个最小分隔 code unit)。
 *   - percentile 使用 nearest-rank 法(ceil(p/100*n)),空输入返回 0。
 *   - 预算推导(spec 021 §6 / ADR-0017):
 *       maxWebCreatesPerFrame = clamp(floor(32 / median(perCreateWorkMs)), 1, 4)
 *       maxWebWorkMsPerFrame   = clamp(round(p75(perCreateWorkMs)), 1, 16)
 *   - T_firstDeltaToVisible p95 >1.5s 仅为观测告警(不阻塞门禁);
 *     T_finishToStable p95 >500ms 是门禁 FAIL 条件(不得通过降低阈值规避)。
 *
 * ArkTS 1.1 strict 适配:
 *   - 全部对象字面量带显式接口类型上下文;无 any/unknown、无解构。
 */

// ============================================================================
//  Fixture 定义
// ============================================================================

export type FixtureId = 'A' | 'B' | 'C' | 'C_P';

export type FixtureLayout = 'none' | 'sparse' | 'dense' | 'consecutive_pairs';

// 一个公式槽在 bodyText 中的 UTF-16 code-unit 区间 [start, start+length)
export interface FixtureFormulaSlot {
  start: number;
  length: number;
}

export interface ChatRenderFixture {
  id: FixtureId;
  bodyText: string;
  formulaCount: number;
  layout: FixtureLayout;
  formulaSlots: FixtureFormulaSlot[];
}

// 与 Q19 offset 决策相同的计量单位: UTF-16 code-unit
export const FIXTURE_TARGET_CODE_UNITS: number = 2000;

// 确定性基础文本(不含 '$',避免污染公式计数);重复填充后截断到恰好 2000 code-unit
const BASE_SENTENCE: string = 'Quadratic equations appear throughout algebra. ';

// 冻结的公式字面量(19 code-unit);所有公式槽等长替换
const FORMULA_TEXT: string = '$$x^2 + y^2 = z^2$$';
const FORMULA_CODE_UNITS: number = 19;

// C′ 对内连续闭合使用 1 code-unit 最小分隔;对间使用更长的无公式 filler,让 3 对结构可观测。
const PAIR_INNER_SEPARATOR: string = ' ';
const PAIR_GROUP_SEPARATOR: string = '....................';

function buildBaseText(): string {
  let text: string = '';
  while (text.length < FIXTURE_TARGET_CODE_UNITS) {
    text += BASE_SENTENCE;
  }
  return text.substring(0, FIXTURE_TARGET_CODE_UNITS);
}

function replaceRange(original: string, start: number, length: number, replacement: string): string {
  return original.substring(0, start) + replacement + original.substring(start + length);
}

function buildFixture(id: FixtureId, formulaCount: number, layout: FixtureLayout,
  formulaSlots: FixtureFormulaSlot[], bodyText: string): ChatRenderFixture {
  return {
    id: id,
    bodyText: bodyText,
    formulaCount: formulaCount,
    layout: layout,
    formulaSlots: formulaSlots,
  };
}

const BASE_TEXT: string = buildBaseText();

function buildSlot(start: number, length: number): FixtureFormulaSlot {
  return {
    start: start,
    length: length,
  };
}

function buildFixtureA(): ChatRenderFixture {
  return buildFixture('A', 0, 'none', [], BASE_TEXT);
}

function buildFixtureB(): ChatRenderFixture {
  let body: string = BASE_TEXT;
  body = replaceRange(body, 500, FORMULA_CODE_UNITS, FORMULA_TEXT);
  body = replaceRange(body, 1300, FORMULA_CODE_UNITS, FORMULA_TEXT);
  const slots: FixtureFormulaSlot[] = [
    buildSlot(500, FORMULA_CODE_UNITS),
    buildSlot(1300, FORMULA_CODE_UNITS),
  ];
  return buildFixture('B', 2, 'sparse', slots, body);
}

function buildFixtureC(): ChatRenderFixture {
  let body: string = BASE_TEXT;
  const offsets: number[] = [250, 500, 750, 1000, 1250, 1500];
  const slots: FixtureFormulaSlot[] = [];
  for (const offset of offsets) {
    body = replaceRange(body, offset, FORMULA_CODE_UNITS, FORMULA_TEXT);
    slots.push(buildSlot(offset, FORMULA_CODE_UNITS));
  }
  return buildFixture('C', 6, 'dense', slots, body);
}

function buildFixtureCP(): ChatRenderFixture {
  // 3 对连续闭合: (f1,f2) -- filler -- (f3,f4) -- filler -- (f5,f6)。
  // 对内 gap = 1,对间 gap > 1,避免退化成 6 个公式平铺。
  const pair: string = FORMULA_TEXT + PAIR_INNER_SEPARATOR + FORMULA_TEXT;
  const run: string = pair + PAIR_GROUP_SEPARATOR + pair + PAIR_GROUP_SEPARATOR + pair;
  const runStart: number = 500;
  const body: string = replaceRange(BASE_TEXT, runStart, run.length, run);
  const slots: FixtureFormulaSlot[] = [buildSlot(runStart, run.length)];
  return buildFixture('C_P', 6, 'consecutive_pairs', slots, body);
}

export const FIXTURE_A: ChatRenderFixture = buildFixtureA();
export const FIXTURE_B: ChatRenderFixture = buildFixtureB();
export const FIXTURE_C: ChatRenderFixture = buildFixtureC();
export const FIXTURE_C_P: ChatRenderFixture = buildFixtureCP();

export const ALL_FIXTURES: ChatRenderFixture[] = [FIXTURE_A, FIXTURE_B, FIXTURE_C, FIXTURE_C_P];

export function getFixtureById(id: FixtureId): ChatRenderFixture {
  if (id === 'A') {
    return FIXTURE_A;
  }
  if (id === 'B') {
    return FIXTURE_B;
  }
  if (id === 'C') {
    return FIXTURE_C;
  }
  return FIXTURE_C_P;
}

// ============================================================================
//  Fixture 结构纯函数
// ============================================================================

// 统计文本中闭合的 $$...$$ 公式对数
export function countFormulaPairs(text: string): number {
  let count: number = 0;
  let searchFrom: number = 0;
  while (true) {
    const openIndex: number = text.indexOf('$$', searchFrom);
    if (openIndex < 0) {
      break;
    }
    const closeIndex: number = text.indexOf('$$', openIndex + 2);
    if (closeIndex < 0) {
      break;
    }
    count += 1;
    searchFrom = closeIndex + 2;
  }
  return count;
}

// 相邻公式对之间的间隔(上一对闭合定界符结束到下一对开启定界符之间的 code-unit 数)
export function formulaPairCloseGaps(text: string): number[] {
  const gaps: number[] = [];
  let searchFrom: number = 0;
  let previousCloseEnd: number = -1;
  while (true) {
    const openIndex: number = text.indexOf('$$', searchFrom);
    if (openIndex < 0) {
      break;
    }
    const closeIndex: number = text.indexOf('$$', openIndex + 2);
    if (closeIndex < 0) {
      break;
    }
    if (previousCloseEnd >= 0) {
      gaps.push(openIndex - previousCloseEnd);
    }
    previousCloseEnd = closeIndex + 2;
    searchFrom = closeIndex + 2;
  }
  return gaps;
}

// ============================================================================
//  冻结指标定义
// ============================================================================

// nearest-rank percentile: index = ceil(p/100 * n) - 1;空输入返回 0
export function percentile(values: number[], p: number): number {
  if (values.length === 0) {
    return 0;
  }
  const sorted: number[] = values.slice().sort((a: number, b: number): number => a - b);
  const rank: number = Math.ceil(p / 100 * sorted.length);
  const index: number = rank < 1 ? 0 : rank - 1;
  return sorted[index];
}

export interface VisibleSampleInput {
  rendered: boolean;
  inViewport: boolean;
  renderedHeight: number;
}

// spec 021 §12 冻结定义: 已完成渲染 + 在视口内 + 高度回传已应用 (renderedHeight > 0)
export function isVisibleSample(sample: VisibleSampleInput): boolean {
  return sample.rendered && sample.inViewport && sample.renderedHeight > 0;
}

// 长帧规则(spec 021 §12): 帧耗时 >32ms 为长帧;禁止连续两帧长帧
export const LONG_FRAME_MS: number = 32;

export interface LongFrameAnalysis {
  longFrameCount: number;
  consecutiveLongFramePairCount: number;
  hasConsecutiveLongFrames: boolean;
}

export function classifyLongFrames(frameDurationsMs: number[]): LongFrameAnalysis {
  let longFrameCount: number = 0;
  let consecutiveLongFramePairCount: number = 0;
  let previousWasLong: boolean = false;
  for (const duration of frameDurationsMs) {
    const isLong: boolean = duration > LONG_FRAME_MS;
    if (isLong) {
      longFrameCount += 1;
      if (previousWasLong) {
        consecutiveLongFramePairCount += 1;
      }
    }
    previousWasLong = isLong;
  }
  return {
    longFrameCount: longFrameCount,
    consecutiveLongFramePairCount: consecutiveLongFramePairCount,
    hasConsecutiveLongFrames: consecutiveLongFramePairCount > 0,
  };
}

// 稳定定义: 最后高度回传时刻 + 500ms 无变化(spec 021 §12)
export const STABILITY_QUIET_MS: number = 500;

// T_firstDeltaToVisible 观测告警线(仅观测,不阻塞门禁;产品阈值是独立决策)
export const T_FIRST_DELTA_TO_VISIBLE_ALARM_MS: number = 1500;

// T_finishToStable p95 门禁门槛(超过即 FAIL,不得降低阈值规避)
export const T_FINISH_TO_STABLE_P95_GATE_MS: number = 500;

export interface TimingSampleInput {
  deltaStartTs: number;
  firstVisibleTs: number;      // -1 = 从未可见
  finishTs: number;
  lastHeightChangeTs: number;  // -1 = 无高度回传
  stableObserved: boolean;     // 是否观察到 500ms 无高度变化
}

export interface TimingMetrics {
  tFirstDeltaToVisibleMs: number;  // -1 = 从未可见
  finishToVisibleMs: number;       // -1 = 从未可见(T_sealedToVisible 的实测对应,seal 记 N/A)
  tFinishToStableMs: number;       // -1 = 从未稳定
}

export function computeTimingMetrics(sample: TimingSampleInput): TimingMetrics {
  const tFirstDeltaToVisibleMs: number = sample.firstVisibleTs >= 0
    ? sample.firstVisibleTs - sample.deltaStartTs
    : -1;
  const finishToVisibleMs: number = sample.firstVisibleTs >= 0
    ? sample.firstVisibleTs - sample.finishTs
    : -1;
  const stableTs: number = sample.stableObserved && sample.lastHeightChangeTs >= 0
    ? sample.lastHeightChangeTs + STABILITY_QUIET_MS
    : -1;
  const tFinishToStableMs: number = stableTs >= 0 ? stableTs - sample.finishTs : -1;
  return {
    tFirstDeltaToVisibleMs: tFirstDeltaToVisibleMs,
    finishToVisibleMs: finishToVisibleMs,
    tFinishToStableMs: tFinishToStableMs,
  };
}

export function isFirstDeltaAlarmObserved(metrics: TimingMetrics): boolean {
  return metrics.tFirstDeltaToVisibleMs > T_FIRST_DELTA_TO_VISIBLE_ALARM_MS;
}

export function isFinishToStableGateViolated(p95FinishToStableMs: number): boolean {
  return p95FinishToStableMs > T_FINISH_TO_STABLE_P95_GATE_MS;
}

// ============================================================================
//  渲染调度器预算推导(spec 021 §6 冻结公式)
// ============================================================================

// 冻结的帧预算: 32ms
export const BUDGET_FRAME_MS: number = 32;
export const MAX_WEB_CREATES_PER_FRAME_MIN: number = 1;
export const MAX_WEB_CREATES_PER_FRAME_MAX: number = 4;
export const MAX_WEB_WORK_MS_PER_FRAME_MIN: number = 1;
export const MAX_WEB_WORK_MS_PER_FRAME_MAX: number = 16;

export interface RendererBudgets {
  maxWebCreatesPerFrame: number;
  maxWebWorkMsPerFrame: number;
}

function medianValue(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  const sorted: number[] = values.slice().sort((a: number, b: number): number => a - b);
  const middle: number = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) {
    return sorted[middle];
  }
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

function clampInt(value: number, minValue: number, maxValue: number): number {
  if (value < minValue) {
    return minValue;
  }
  if (value > maxValue) {
    return maxValue;
  }
  return Math.floor(value);
}

// perCreateWorkMs = 每个 Web 工作单元从创建到首次高度回传应用的实测耗时样本集。
// maxWebCreatesPerFrame = clamp(floor(32 / median(perCreateWorkMs)), 1, 4)
// maxWebWorkMsPerFrame   = clamp(round(p75(perCreateWorkMs)), 1, 16)
export function deriveRendererBudgets(perCreateWorkMs: number[]): RendererBudgets {
  const median: number = medianValue(perCreateWorkMs);
  const p75: number = percentile(perCreateWorkMs, 75);
  const createsPerFrame: number = median > 0 ? Math.floor(BUDGET_FRAME_MS / median) : 0;
  const maxWebCreatesPerFrame: number = clampInt(
    createsPerFrame, MAX_WEB_CREATES_PER_FRAME_MIN, MAX_WEB_CREATES_PER_FRAME_MAX);
  const maxWebWorkMsPerFrame: number = clampInt(
    Math.round(p75), MAX_WEB_WORK_MS_PER_FRAME_MIN, MAX_WEB_WORK_MS_PER_FRAME_MAX);
  return {
    maxWebCreatesPerFrame: maxWebCreatesPerFrame,
    maxWebWorkMsPerFrame: maxWebWorkMsPerFrame,
  };
}
