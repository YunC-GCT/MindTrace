/**
 * DispatchOptions.ets — Dispatcher 的调用选项契约（从 Dispatcher.ets 抽出，便于分支模块复用）
 *
 * 路径: agents/src/main/ets/core/dispatch/DispatchOptions.ets
 * 职责: 只声明调用选项形状；Dispatcher 负责默认值与装配，分支模块只消费。
 * 依赖: common 类型 + agents 的 NoteDaoInterface / KnowledgeModel（仅类型）。
 *
 * 拆出原因（2026-10-31）：Dispatcher.ets 近 1800 行，分支不断往同一文件堆；
 * 先把跨分支共享的选项契约抽成叶子模块，避免分支模块反向 import Dispatcher 造成环。
 */
import type {
  CancellationToken,
  CaptureSetItemResult,
  NoteGenerationProgressSink,
  NoteGenerationRepository,
  NoteWritePort,
  RunContext,
} from 'common';
import type { KnowledgeModel } from '../../agents/KnowledgeModel';
import type { NoteDaoInterface } from '../../models/NoteDaoInterface';
import type { RunEventSink } from './RunEventSink';

export interface DispatchOptions {
  persist?: boolean;
  includeRawText?: boolean;
  analysisOnly?: boolean;
  dao?: NoteDaoInterface;
  /** #238 切片 A1：capture 持久化端口；提供时优先于 dao（幂等 / CAS / 结构化错误） */
  noteWritePort?: NoteWritePort;
  generationRepository?: NoteGenerationRepository;
  knowledgeModel?: KnowledgeModel;
  cancellationToken?: CancellationToken;
  /** #243：调用方自带的 run 上下文；不传则捕获路径自建一个根上下文 */
  runContext?: RunContext;
  progressSink?: NoteGenerationProgressSink;
  onNodeTiming?: (step: string, elapsedMs: number) => void;
  /** 库里已有的学科名（含内置学科）；structure 用它决定复用还是新建 */
  subjectVocabulary?: string[];
  /** A4：run 级事件流（start/terminal）；未装配时行为零变化（NullRunEventSink）。 */
  runEventSink?: RunEventSink;
  /** 快速路由：跳过独立的分类 LLM，让 structure 在同一次调用里自分类（省一次往返）。 */
  skipLlmClassification?: boolean;
}

// spec 036 阶段 1：集合级整理的可选项。
// DispatchOptions 定义在 agents，common 不能反向依赖 agents，所以这里承载 onItem；
// 每完成一项就回调一次，UI 用它原地更新对话记录。
export interface CaptureSetOptions extends DispatchOptions {
  onItem?: (item: CaptureSetItemResult) => void;
}
