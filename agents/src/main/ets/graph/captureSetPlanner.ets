/**
 * captureSetPlanner.ets — 036 阶段 2/3 的纯函数编排：逐图切题 → 跨图合并
 *
 * 路径: agents/src/main/ets/graph/captureSetPlanner.ets
 * 职责: 把「N 张图的 OCR 文本」规划成「M 道题」：每张图先 segmentProblems 切题，
 *       再把所有段交给 mergeProblems 做跨页续题 / 重拍去重，输出确认页/落库可直接消费的题目计划。
 * 依赖: ./problemSegmenter、./problemMerger（纯函数，无 Kit）。
 *
 * 数据流:
 *   SetImageText[]（imageIndex + OCR 文本）→ planCaptureSet() → SetPlan
 *   SetPlan.problems[] 交给 Stage B（classify/structure）或确认页（036 阶段 4）。
 *
 * 边界:
 *   - 不做 OCR、不读库、不发进度事件：编排层（entry）负责 I/O，本文件只做确定性规划。
 *   - OCR 为空的图进 emptyImageIndexes（不算失败）；退化整页的图进 degradedImageIndexes，
 *     其题目 needsReview=true，确认页默认不勾选（036 §7 D4）。
 */
import { ProblemSegment, SegmentResult, segmentProblems } from './problemSegmenter';
import { MergedProblem, SourceSegment, mergeProblems } from './problemMerger';

// 一张图的 OCR 结果（imageIndex 由调用方按用户选择顺序给）。
export interface SetImageText {
  imageIndex: number;
  text: string;
}

// 计划中的一道题（确认页/落库的最小单位）。
export interface PlannedProblem {
  index: number;
  text: string;
  sourceImageIndexes: number[];
  anchors: string[];
  needsReview: boolean;
  fingerprint: string;
}

export interface SetPlan {
  problems: PlannedProblem[];
  degradedImageIndexes: number[];
  emptyImageIndexes: number[];
  totalSegments: number;
}

// 逐图切题 → 扁平化 SourceSegment → 跨图合并 → PlannedProblem[]。
// 空文本是「没有可整理内容」，进 emptyImageIndexes，不参与合并。
export function planCaptureSet(images: SetImageText[]): SetPlan {
  const sources: SourceSegment[] = [];
  const degradedImageIndexes: number[] = [];
  const emptyImageIndexes: number[] = [];
  let totalSegments: number = 0;

  for (let i: number = 0; i < images.length; i += 1) {
    const image: SetImageText = images[i];
    const text: string = image.text !== undefined ? image.text : '';
    if (text.trim().length === 0) {
      emptyImageIndexes.push(image.imageIndex);
      continue;
    }
    const segmented: SegmentResult = segmentProblems(text);
    if (segmented.degraded) {
      degradedImageIndexes.push(image.imageIndex);
    }
    for (let j: number = 0; j < segmented.segments.length; j += 1) {
      const segment: ProblemSegment = segmented.segments[j];
      totalSegments += 1;
      const source: SourceSegment = {
        imageIndex: image.imageIndex,
        segmentIndex: segment.index,
        anchor: segment.anchor,
        text: segment.rawText,
        needsReview: segment.needsReview || segmented.degraded,
      };
      sources.push(source);
    }
  }

  const merged: MergedProblem[] = mergeProblems(sources);
  const problems: PlannedProblem[] = [];
  for (let k: number = 0; k < merged.length; k += 1) {
    const item: MergedProblem = merged[k];
    const imageIndexes: number[] = [];
    const anchors: string[] = [];
    for (let s: number = 0; s < item.sources.length; s += 1) {
      const source: SourceSegment = item.sources[s];
      if (imageIndexes.indexOf(source.imageIndex) < 0) {
        imageIndexes.push(source.imageIndex);
      }
      if (source.anchor.length > 0 && anchors.indexOf(source.anchor) < 0) {
        anchors.push(source.anchor);
      }
    }
    const planned: PlannedProblem = {
      index: item.index,
      text: item.text,
      sourceImageIndexes: imageIndexes,
      anchors: anchors,
      needsReview: item.needsReview,
      fingerprint: item.fingerprint,
    };
    problems.push(planned);
  }

  const plan: SetPlan = {
    problems: problems,
    degradedImageIndexes: degradedImageIndexes,
    emptyImageIndexes: emptyImageIndexes,
    totalSegments: totalSegments,
  };
  return plan;
}
