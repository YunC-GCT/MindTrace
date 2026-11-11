/**
 * AgentExtAbility.ets - 端 A2A Agent 扩展入口（手写 JSON-RPC 2.0 单帧快照）
 *
 * 路径: entry/src/main/ets/agentextability/AgentExtAbility.ets
 * 职责: 解析小艺 JSON-RPC 请求、提取 text/image parts，交给 A2AController 编排；
 *       把控制器回复拼成一条 result.task 快照经 hostProxy.sendData 发出。
 *       意图/计划/内联整理/记忆/回执在 services/A2AController（本类只做协议适配）。
 * 为什么手写: SDK 的自动应答封装会先发一帧 TASK_STATE_SUBMITTED（带 history），
 *       再发 artifactUpdate；小艺在这种序列下只渲染开头一两个词。历史实测「单帧 result.task
 *       一次给全 artifacts + COMPLETED」能完整渲染长文本，故回到手写。
 * 依赖: @kit.AbilityKit、@kit.PerformanceAnalysisKit、common.OcrRecognizerRegistry、
 *       ../services/A2AController、../services/AgentImageParts、./TaskSnapshot、../services/CoreVisionOcrRecognizer
 *
 * 进程约束（重要）: 扩展跑在独立进程 <bundle>:agent，模块加载失败表现为 exit 254 /
 *   Reason:SyntaxError 且 onCreate 一行日志都打不出来（错误发生在 import 图求值阶段）。
 *   因此本文件禁止 import ModelRouter / OnDeviceLlm（及其依赖链）；端侧路由只在 UI 进程
 *   （ConversationWorkflowPorts）使用。
 *
 * 写库模式（ADR-0024 §2.1/§2.7）: A2A 单次整理（单题/多题逐题/「全部」）在本扩展进程内联执行，
 *   这是正式路径，不经过 WriteJobScheduler；超时/失败/批量溢出才回退 inbox/agent_job。
 *   UI 进程的队列只承接兜底与恢复。两条路径共用 AgentIngestService → CapturePipeline → CommandExecutor。
 *
 * 数据流:
 *   onCreate -> 组合根安装 OCR 能力 -> new A2AController(context, replyPort).prepare()
 *   onData(proxy, data) -> JSON.parse 取 id / params.message.parts[] / taskId / contextId
 *     -> 解析失败：回一条错误快照（不崩）
 *     -> controller.handle(A2ARequestInput) -> replyPort.send() -> sendSnapshot()
 *   sendSnapshot: 拼单帧 result.task（buildTaskSnapshotWithCard 空卡片路径）-> hostProxy.sendData
 */
import { AgentExtensionAbility, common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { OcrRecognizerRegistry } from 'common';
import { A2AController, A2ARequestInput, A2AReplyPort } from '../services/A2AController';
import { a2aErrorText } from '../services/A2AErrorTaxonomy';
import { AgentPart, mediaTypeOf } from '../services/AgentImageParts';
import { CoreVisionOcrRecognizer } from '../services/CoreVisionOcrRecognizer';
import { buildTaskSnapshotWithCard, buildTaskStreamStart, buildArtifactUpdate, buildTaskStreamEnd, unicodeCharCount, utf8ByteLength } from './TaskSnapshot';

const TAG: string = 'MindTraceA2A';
const DOMAIN: number = 0xA2A0;

/** 请求解析失败时统一走错误文案，避免 ability 自己拼字符串。 */

// 小艺发来的 JSON-RPC 请求（proto-JSON）：文本 part 只有 mediaType + text，没有 kind/type；
// 图片/文件 part 用 raw（base64）或 url（file:// 等）+ mediaType（image/png…）承载。
// part 的形状判定与图片提取集中在 services/AgentImageParts（纯函数，可单测），这里只做透传。
interface A2AMessage {
  parts?: AgentPart[];
  /** 小艺会话 id：taskId 为空时用它做多轮记忆键 */
  contextId?: string;
}

interface A2AParams {
  message?: A2AMessage;
  /** 请求若带 task id，优先用它回填快照，保证 artifactId 稳定 */
  taskId?: string;
}

interface A2ARequest {
  id?: string | number;
  params?: A2AParams;
}

/** 把扩展的发送方法包成 A2AReplyPort（ArkTS 不允许用对象字面量实现带方法的接口）。 */
class AbilityReplyPort implements A2AReplyPort {
  private readonly onSend: (taskId: string, text: string, requestStartedAt: number) => void;
  private readonly onStreamStart: ((taskId: string) => void) | undefined;
  private readonly onStreamChunk: ((taskId: string, text: string, append: boolean,
    lastChunk: boolean) => void) | undefined;
  private readonly onStreamEnd: ((taskId: string) => void) | undefined;

  constructor(onSend: (taskId: string, text: string, requestStartedAt: number) => void,
    onStreamStart?: (taskId: string) => void,
    onStreamChunk?: (taskId: string, text: string, append: boolean, lastChunk: boolean) => void,
    onStreamEnd?: (taskId: string) => void) {
    this.onSend = onSend;
    this.onStreamStart = onStreamStart;
    this.onStreamChunk = onStreamChunk;
    this.onStreamEnd = onStreamEnd;
  }

  send(taskId: string, text: string, requestStartedAt: number): void {
    this.onSend(taskId, text, requestStartedAt);
  }

  streamStart(taskId: string): void {
    if (this.onStreamStart !== undefined) {
      this.onStreamStart(taskId);
    }
  }

  streamChunk(taskId: string, text: string, append: boolean, lastChunk: boolean): void {
    if (this.onStreamChunk !== undefined) {
      this.onStreamChunk(taskId, text, append, lastChunk);
    }
  }

  streamEnd(taskId: string): void {
    if (this.onStreamEnd !== undefined) {
      this.onStreamEnd(taskId);
    }
  }
}

export default class AgentExtAbility extends AgentExtensionAbility {
  /** onData 收到的宿主代理，最终 task 快照直接由它发出 */
  private hostProxy: common.AgentHostProxy | null = null;
  /** 当前请求的 jsonrpc id：回复快照必须回填同一个 id，否则小艺不认这一帧 */
  private lastRequestId: string = '';
  /** 编排/策略在控制器；本类只负责协议适配与快照发送 */
  private controller: A2AController | null = null;

  onCreate(want: Want): void {
    const abilityName: string = want.abilityName ?? 'unknown';
    hilog.info(DOMAIN, TAG, 'onCreate: 扩展被拉起 ability=%{public}s（手写单帧快照模式）', abilityName);
    // 组合根：:agent 进程自己安装 OCR 实现。主进程由 EntryAbility.onCreate 安装同一份实现。
    if (!OcrRecognizerRegistry.isInstalled()) {
      OcrRecognizerRegistry.install(new CoreVisionOcrRecognizer());
      hilog.info(DOMAIN, TAG, 'OCR 能力已安装（:agent 组合根）');
    }
    this.controller = new A2AController(this.context, this.buildReplyPort());
    this.controller.prepare();
  }

  onData(proxy: common.AgentHostProxy, data: string): void {
    hilog.info(DOMAIN, TAG, 'onData 收到 %{public}d 字节', data.length);
    // 诊断：把原始报文前 1200 字打进日志。小艺侧“发了图但 parts 里没有图”的判定只能靠它，
    // 否则看不到客户端到底往报文里塞了什么（file 形状、metadata.fileInfos 等）。
    hilog.info(DOMAIN, TAG, 'raw=%{public}s', data.substring(0, Math.min(data.length, 1200)));
    this.hostProxy = proxy;
    if (this.controller === null) {
      this.sendAnswer('', a2aErrorText('A2A_PARSE_ERROR'), 0);
      return;
    }
    // 新请求一到达就作废上一条在途请求（含后面的 parse-error 分支），
    // 避免旧 session 晚到的回复套用新 requestId 发出去。
    this.controller.cancelActive();

    // 解析失败（JSON 非法 / 顶层不是对象）统一回错误快照，绝不让异常冒出去
    const request: A2ARequest | null = this.parseRequest(data);
    if (request === null) {
      this.lastRequestId = '';
      this.sendAnswer('', a2aErrorText('A2A_PARSE_ERROR'), 0);
      return;
    }

    this.lastRequestId = this.readRequestId(request.id);
    this.logParts(request);
    const input: A2ARequestInput = {
      requestId: this.lastRequestId,
      taskId: this.readTaskId(request),
      contextId: this.readContextId(request),
      query: this.readQuery(request),
      parts: this.readParts(request),
    };
    this.controller.handle(input);
  }

  onDestroy(): void {
    // 扩展销毁时取消在途请求。
    if (this.controller !== null) {
      this.controller.cancelActive();
    }
    this.hostProxy = null;
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  /** 控制器回话端口：拼快照 + 发一帧（requestStartedAt 只用于日志耗时）。 */
  private buildReplyPort(): A2AReplyPort {
    return new AbilityReplyPort(
      (taskId: string, text: string, requestStartedAt: number): void => {
        this.sendSnapshot(taskId, text, requestStartedAt, '');
      },
      (taskId: string): void => {
        this.sendStreamFrame(buildTaskStreamStart(this.lastRequestId, taskId), 'start', taskId);
      },
      (taskId: string, text: string, append: boolean, lastChunk: boolean): void => {
        this.sendStreamFrame(buildArtifactUpdate(this.lastRequestId, taskId, text, append, lastChunk),
          lastChunk ? 'last' : 'chunk', taskId);
      },
      (taskId: string): void => {
        this.sendStreamFrame(buildTaskStreamEnd(this.lastRequestId, taskId), 'end', taskId);
      },
    );
  }

  /** 流式探针帧：只打帧类型与字节数，不打印正文。 */
  private sendStreamFrame(payload: string, kind: string, taskId: string): void {
    if (this.hostProxy === null) {
      hilog.error(DOMAIN, TAG, 'hostProxy 为空，无法发送流式帧');
      return;
    }
    try {
      this.hostProxy.sendData(payload);
      hilog.info(DOMAIN, TAG, 'A2A_STREAM_FRAME kind=%{public}s taskId=%{public}s bytes=%{public}d',
        kind, taskId, utf8ByteLength(payload));
    } catch (error) {
      hilog.error(DOMAIN, TAG, '发送流式帧失败: %{public}s', (error as Error).message);
    }
  }

  /** 手写解析：JSON.parse 失败或结果为 null 都返回 null，由 onData 回错误快照 */
  private parseRequest(data: string): A2ARequest | null {
    try {
      return JSON.parse(data) as A2ARequest;
    } catch (e) {
      hilog.error(DOMAIN, TAG, '请求 JSON 解析失败: %{public}s', (e as Error).message);
      return null;
    }
  }

  /** jsonrpc id 可能是字符串或数字，统一转成字符串供回填 */
  private readRequestId(id: string | number | undefined): string {
    if (typeof id === 'string') {
      return id as string;
    }
    if (typeof id === 'number') {
      return (id as number).toString();
    }
    return '';
  }

  /** 取出所有 parts（文本 + 图片/文件），解析层与诊断日志共用 */
  private readParts(request: A2ARequest): AgentPart[] {
    const params: A2AParams | undefined = request.params;
    if (params === undefined) {
      return [];
    }
    const message: A2AMessage | undefined = params.message;
    if (message === undefined) {
      return [];
    }
    const parts: AgentPart[] | undefined = message.parts;
    if (parts === undefined) {
      return [];
    }
    return parts;
  }

  /** 诊断：把每个 part 的形状打进日志（媒体类型 + 各字段长度），确认小艺到底发了什么 */
  private logParts(request: A2ARequest): void {
    const parts: AgentPart[] = this.readParts(request);
    hilog.info(DOMAIN, TAG, 'parts=%{public}d', parts.length);
    let i: number = 0;
    for (const part of parts) {
      const media: string = mediaTypeOf(part);
      const textLen: number = (part.text ?? '').length;
      const rawLen: number = (part.raw ?? '').length;
      const url: string = part.url ?? '';
      const fileUri: string = part.file !== undefined && part.file.uri !== undefined ? part.file.uri : '';
      const dataKind: string = part.data === undefined ? 'none' : typeof part.data;
      hilog.info(DOMAIN, TAG,
        'part[%{public}d] media=%{public}s text=%{public}d raw=%{public}d data=%{public}s url=%{public}s file=%{public}s',
        i, media, textLen, rawLen, dataKind, url.length > 0 ? url : 'none',
        fileUri.length > 0 ? fileUri : 'none');
      i = i + 1;
    }
  }

  /** 小艺的 parts 只有 mediaType + text：取第一个 text 为 string 的 part */
  private readQuery(request: A2ARequest): string {
    const parts: AgentPart[] = this.readParts(request);
    for (const part of parts) {
      const text: string | undefined = part.text;
      if (text !== undefined && typeof text === 'string') {
        return text as string;
      }
    }
    return '';
  }

  /** 请求里带 task id 就用它（保证 artifactId 稳定），没带则由 sendSnapshot 生成 */
  private readTaskId(request: A2ARequest): string {
    const params: A2AParams | undefined = request.params;
    if (params === undefined) {
      return '';
    }
    const tid: string | undefined = params.taskId;
    if (tid !== undefined && tid.length > 0) {
      return tid;
    }
    return '';
  }

  /** 小艺会话 id（message.contextId）：taskId 为空时做多轮记忆/计划键。 */
  private readContextId(request: A2ARequest): string {
    const params: A2AParams | undefined = request.params;
    if (params === undefined || params.message === undefined) {
      return '';
    }
    const cid: string | undefined = params.message.contextId;
    return cid === undefined ? '' : cid;
  }

  private sendAnswer(taskId: string, text: string, requestStartedAt: number): void {
    this.sendSnapshot(taskId, text, requestStartedAt, '');
  }

  /**
   * 单帧 result.task 快照：一次给全 artifacts + TASK_STATE_COMPLETED。
   * 不拆 statusUpdate / artifactUpdate —— 小艺对增量帧只渲染开头几个词。
   * 报文拼装由 TaskSnapshot（纯函数）负责，这里只选 taskId 并发送。
   *
   * #234 可观测性: 发送成功后只打计数摘要（chars/字节/特殊符号/耗时），
   * 不打印正文、正文前缀或哈希（AGENTS 红线）。requestStartedAt 由调用方传入
   * 当前 session 的模型调用起点；无 session 的分支传 0，elapsedMs 记 0。
   */
  private sendSnapshot(taskId: string, text: string, requestStartedAt: number, cardPartJson: string): void {
    const finalTaskId: string = taskId.length > 0 ? taskId : 'task-' + Date.now().toString();
    const payload: string = buildTaskSnapshotWithCard(this.lastRequestId, finalTaskId, text, cardPartJson);
    if (this.hostProxy === null) {
      hilog.error(DOMAIN, TAG, 'hostProxy 为空，无法发送 task 快照');
      return;
    }
    try {
      this.hostProxy.sendData(payload);
      const elapsedMs: number = requestStartedAt > 0 ? Date.now() - requestStartedAt : 0;
      hilog.info(DOMAIN, TAG,
        'A2A_REPLY_SENT chars=%{public}d utf8Bytes=%{public}d snapshotBytes=%{public}d dollar=%{public}d backslash=%{public}d zeroWidth=%{public}d sqrt=%{public}d ge=%{public}d elapsedMs=%{public}d taskId=%{public}s',
        unicodeCharCount(text), utf8ByteLength(text), utf8ByteLength(payload),
        this.countOccurrences(text, '$'), this.countOccurrences(text, '\\'),
        this.countZeroWidth(text), text.indexOf('√') >= 0 ? 1 : 0,
        text.indexOf('≥') >= 0 ? 1 : 0, elapsedMs, finalTaskId);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '发送 task 快照失败: %{public}s', (error as Error).message);
    }
  }

  /** 统计子串出现次数：只把计数写日志，永远不写正文。 */
  private countOccurrences(text: string, needle: string): number {
    if (needle.length === 0) {
      return 0;
    }
    let count: number = 0;
    let index: number = text.indexOf(needle);
    while (index >= 0) {
      count += 1;
      index = text.indexOf(needle, index + needle.length);
    }
    return count;
  }

  /** 零宽字符计数（U+200B/200C/200D/FEFF）：小艺吞公式时会留下 U+200B 占位。 */
  private countZeroWidth(text: string): number {
    let count: number = 0;
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code === 0x200B || code === 0x200C || code === 0x200D || code === 0xFEFF) {
        count += 1;
      }
    }
    return count;
  }
}
