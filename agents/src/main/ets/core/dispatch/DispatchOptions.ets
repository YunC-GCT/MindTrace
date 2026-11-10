/**
 * DispatchOptions.ets — CommandExecutor 的调用选项契约（按消费者分组）
 *
 * 路径: agents/src/main/ets/core/dispatch/DispatchOptions.ets
 * 职责: 把一次命令执行所需的选项拆成五组：
 *       WritePorts（持久化端口）/ Observability（事件与计时）/ RunControl（取消与预算）/
 *       DispatchMode（命令形状）/ DispatchDomain（领域注入）。
 *       扁平 DispatchOptions 是 dispatchCommand 的公共入参；WorkflowContext 只暴露五组。
 * 依赖: common 类型 + agents 的 NoteDaoInterface / KnowledgeModel（仅类型）。
 *
 * 数据流: CommandExecutor.dispatchCommand → groupDispatchOptions → WorkflowContext
 *         → workflow 按组消费。
 */
import type {
  CancellationToken,
  CaptureSetItemResult,
  NoteGenerationProgressSink,
  NoteGenerationRepository,
  NoteWritePort,
  RunContext,
} from 'common';
import type { KnowledgeModel } from '../../subagents/KnowledgeModel';
import type { NoteDaoInterface } from '../../models/NoteDaoInterface';
import type { RunEventSink } from './RunEventSink';

/** 持久化端口：谁负责写、写到哪。 */
export interface WritePorts {
  dao?: NoteDaoInterface;
  /** #238 切片 A1：capture 持久化端口；提供时优先于 dao（幂等 / CAS / 结构化错误） */
  noteWritePort?: NoteWritePort;
  generationRepository?: NoteGenerationRepository;
}

/** 可观测性：节点计时与 run 事件。 */
export interface Observability {
  onNodeTiming?: (step: string, elapsedMs: number) => void;
  /** A4：run 级事件流（start/terminal）；未装配时行为零变化（NullRunEventSink）。 */
  runEventSink?: RunEventSink;
}

/** 运行控制：取消与父级 run 上下文。 */
export interface RunControl {
  cancellationToken?: CancellationToken;
  /** #243：调用方自带的 run 上下文；不传则由执行器自建根上下文 */
  runContext?: RunContext;
}

/** 命令形状：这次执行是采集 / 只分析 / 是否落库 / 是否跳过分类 LLM。 */
export interface DispatchMode {
  persist?: boolean;
  includeRawText?: boolean;
  analysisOnly?: boolean;
  /** 快速路由：跳过独立的分类 LLM，让 structure 在同一次调用里自分类（省一次往返）。 */
  skipLlmClassification?: boolean;
  /** A2A 快速整理：短 prompt + 小输出上限，优先低延迟。 */
  compactStructure?: boolean;
}

/** 领域注入：模型/进度/学科词表等业务侧依赖。 */
export interface DispatchDomain {
  knowledgeModel?: KnowledgeModel;
  progressSink?: NoteGenerationProgressSink;
  /** 库里已有的学科名（含内置学科）；structure 用它决定复用还是新建 */
  subjectVocabulary?: string[];
}

/** 扁平选项：兼容旧调用方与尚未迁移的 branch；新代码按组消费。 */
export interface DispatchOptions
  extends WritePorts, Observability, RunControl, DispatchMode, DispatchDomain {}

// spec 036 阶段 1：集合级整理的可选项。
// DispatchOptions 定义在 agents，common 不能反向依赖 agents，所以这里承载 onItem；
// 每完成一项就回调一次，UI 用它原地更新对话记录。
export interface CaptureSetOptions extends DispatchOptions {
  onItem?: (item: CaptureSetItemResult) => void;
}

/** 五组选项：CommandExecutor 构造 WorkflowContext 时使用。 */
export interface DispatchGroups {
  writePorts: WritePorts;
  observability: Observability;
  runControl: RunControl;
  mode: DispatchMode;
  domain: DispatchDomain;
}

/** 把扁平选项拆成五组；未设置的可选字段保持 undefined。 */
export function groupDispatchOptions(options: DispatchOptions): DispatchGroups {
  const writePorts: WritePorts = {
    dao: options.dao,
    noteWritePort: options.noteWritePort,
    generationRepository: options.generationRepository,
  };
  const observability: Observability = {
    onNodeTiming: options.onNodeTiming,
    runEventSink: options.runEventSink,
  };
  const runControl: RunControl = {
    cancellationToken: options.cancellationToken,
    runContext: options.runContext,
  };
  const mode: DispatchMode = {
    persist: options.persist,
    includeRawText: options.includeRawText,
    analysisOnly: options.analysisOnly,
    skipLlmClassification: options.skipLlmClassification,
    compactStructure: options.compactStructure,
  };
  const domain: DispatchDomain = {
    knowledgeModel: options.knowledgeModel,
    progressSink: options.progressSink,
    subjectVocabulary: options.subjectVocabulary,
  };
  const groups: DispatchGroups = {
    writePorts: writePorts,
    observability: observability,
    runControl: runControl,
    mode: mode,
    domain: domain,
  };
  return groups;
}
