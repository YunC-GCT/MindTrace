/**
 * ModelRequestBuilder.ets — 由 ModelSpec 推导请求字段 (纯函数, 无 IO)
 *
 * 路径: common/src/main/ets/llm/ModelRequestBuilder.ets
 * 职责: 唯一一份请求构造逻辑。JSON 与 SSE 两条 transport 都调用它,
 *       不再出现 vendorId === 'deepseek' 之类的厂商特判。
 * 依赖: ./model-catalog (仅类型; 运行时不 import)
 *
 * 数据流:
 *   LlmClient.composeRequest
 *     → planModelRequest(spec, selection) → ModelFieldWrite[]
 *     → applyFieldWrites(body) → JSON.stringify → HTTP(JSON / SSE)
 *
 * 构造契约 (design §请求构造契约):
 *   - 基础 body 由调用方先写 model/messages/stream; 本模块只产出 FieldWrite[]。
 *   - 输出 token 字段名由 spec.request.outputTokenPath 提供。
 *   - toggle: 用户选择优先, 否则用该型号 defaultEnabled; 应用 on[] / off[]。
 *   - always_on: 不写任何 on/off 字段。
 *   - unsupported / unverified: 不写 thinking / effort。
 *   - effort: 用户值不在 levels 里 → 只用合法 defaultLevel; 默认也缺失且
 *     requiredWhen 命中 → 返回 null (规格不完整), 绝不静默取 levels[0]。
 *   - sampling: 只在 support='yes' 且 when 条件成立时下发; 无值不下发。
 *   - max_tokens: min(max(1, floor(value)), maxOutputTokens); maxOutputTokens
 *     缺失或非正数时不夹取。
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any / unknown; FieldWrite 的值是 string | boolean | number。
 *   - 路径写入用变量 key (record[key]), 不写 record['literal'] 字面量索引。
 */

import type {
  EffortRequiredWhen,
  EffortSendWhen,
  ModelEffortSpec,
  ModelFieldWrite,
  ModelSamplingRule,
  ModelSamplingSpec,
  ModelSpec,
  ThinkingControl,
} from './model-catalog';

// 运行偏好 + 本次调用参数; 缺省字段 = 调用方没给, 由规格决定。
export interface ModelRequestSelection {
  maxTokens: number;
  maxOutputTokens: number;
  temperature?: number;
  topP?: number;
  thinking?: boolean;
  effort?: string;
}

export interface ModelRequestPlan {
  writes: ModelFieldWrite[];
  thinkingControl: ThinkingControl;
  thinkingEnabled: boolean;
  effort: string;        // 实际写出的强度; '' = 本次不写
  effortPath: string[];
}

interface EffortChoice {
  value: string;
  fromUser: boolean;
}

// JSONValue 的受限子集, 与 ModelFieldValue 同构 (避免跨文件类型别名耦合)。
type RequestFieldValue = string | boolean | number;

// ==================== 路径写入 ====================

// 把 value 写到 path 末端; 中间层不存在时创建嵌套 record。
export function putField(body: Record<string, Object>, path: string[], value: Object): void {
  if (path.length === 0) {
    return;
  }
  const lastIndex: number = path.length - 1;
  let target: Record<string, Object> = body;
  let index: number = 0;
  for (const key of path) {
    if (key.length === 0) {
      return;
    }
    if (index === lastIndex) {
      target[key] = value;
      return;
    }
    const existing: Object | undefined = target[key];
    if (existing === undefined || existing === null) {
      const child: Record<string, Object> = {};
      target[key] = child;
      target = child;
    } else {
      target = existing as Record<string, Object>;
    }
    index += 1;
  }
}

export function applyFieldWrites(body: Record<string, Object>, writes: ModelFieldWrite[]): void {
  for (const write of writes) {
    putField(body, write.path, write.value);
  }
}

// ==================== 输出 token ====================

// min(max(1, floor(value)), maxOutputTokens); cap 缺失/非正数时不夹取。
export function boundOutputTokens(value: number, maxOutputTokens: number): number {
  let requested: number = Math.floor(value);
  if (requested !== requested) {
    // NaN
    requested = 1;
  }
  if (requested < 1) {
    requested = 1;
  }
  if (maxOutputTokens <= 0) {
    if (requested === Infinity) {
      return 1;
    }
    return requested;
  }
  if (requested > maxOutputTokens || requested === Infinity) {
    return maxOutputTokens;
  }
  return requested;
}

// ==================== 条件 ====================

function samplingConditionMet(rule: ModelSamplingRule, thinkingEnabled: boolean): boolean {
  if (rule.support !== 'yes') {
    return false;
  }
  if (rule.when === 'always') {
    return true;
  }
  if (rule.when === 'thinking_on') {
    return thinkingEnabled;
  }
  if (rule.when === 'thinking_off') {
    return !thinkingEnabled;
  }
  return false;
}

function requiredNow(requiredWhen: EffortRequiredWhen, thinkingEnabled: boolean): boolean {
  if (requiredWhen === 'always') {
    return true;
  }
  if (requiredWhen === 'thinking_on') {
    return thinkingEnabled;
  }
  return false;
}

function sendEffortNow(
  sendWhen: EffortSendWhen,
  choice: EffortChoice,
  thinkingEnabled: boolean,
): boolean {
  if (choice.value.length === 0) {
    return false;
  }
  if (sendWhen === 'always') {
    return true;
  }
  if (sendWhen === 'thinking_on') {
    return thinkingEnabled;
  }
  // 'selected': 只写用户显式选择的档位, 不把默认值当用户选择。
  return choice.fromUser;
}

// 用户值非法 → 合法默认值; 默认也非法/缺失 → '' (由调用方判 requiredWhen)。
function chooseEffort(spec: ModelEffortSpec, requested: string | undefined): EffortChoice {
  if (requested !== undefined && spec.levels.indexOf(requested) >= 0) {
    const userChoice: EffortChoice = { value: requested, fromUser: true };
    return userChoice;
  }
  const fallback: string | null = spec.defaultLevel;
  if (fallback !== null && spec.levels.indexOf(fallback) >= 0) {
    const defaultChoice: EffortChoice = { value: fallback, fromUser: false };
    return defaultChoice;
  }
  const emptyChoice: EffortChoice = { value: '', fromUser: false };
  return emptyChoice;
}

// ==================== 主入口 ====================

// 返回 null = 规格不完整 (必填 effort 无合法值 / outputTokenPath 缺失)。
export function planModelRequest(
  spec: ModelSpec | null,
  selection: ModelRequestSelection,
): ModelRequestPlan | null {
  const writes: ModelFieldWrite[] = [];

  // 输出 token: 字段名由规格提供; 无规格时按 OpenAI 兼容默认 max_tokens。
  const outputTokenPath: string[] = spec !== null
    ? spec.request.outputTokenPath.slice(0) : ['max_tokens'];
  if (outputTokenPath.length === 0) {
    return null;
  }
  const outputTokens: RequestFieldValue = boundOutputTokens(
    selection.maxTokens, selection.maxOutputTokens);
  const outputWrite: ModelFieldWrite = { path: outputTokenPath, value: outputTokens };
  writes.push(outputWrite);

  if (spec === null) {
    // 没有规格: 不写 thinking / effort / temperature / top_p, 只保留基础字段。
    const noSpecPlan: ModelRequestPlan = {
      writes: writes,
      thinkingControl: 'unverified',
      thinkingEnabled: false,
      effort: '',
      effortPath: [],
    };
    return noSpecPlan;
  }

  const control: ThinkingControl = spec.request.thinking.control;
  let thinkingEnabled: boolean = false;
  let thinkingDecided: boolean = false;

  if (control === 'toggle') {
    if (selection.thinking !== undefined) {
      thinkingEnabled = selection.thinking;
      thinkingDecided = true;
    } else if (spec.request.thinking.defaultEnabled !== null) {
      thinkingEnabled = spec.request.thinking.defaultEnabled;
      thinkingDecided = true;
    }
  } else if (control === 'always_on') {
    thinkingEnabled = true;
    thinkingDecided = true;
  }
  // unsupported / unverified: thinkingDecided 保持 false, 不写任何开关字段。

  // always_on 的 on/off 按规格恒为空; 这里再显式跳过, 防止规格写错时误发关闭字段。
  if (control === 'toggle' && thinkingDecided) {
    const branch: ModelFieldWrite[] = thinkingEnabled
      ? spec.request.thinking.on : spec.request.thinking.off;
    for (const write of branch) {
      writes.push(write);
    }
  }

  // effort: 只有 toggle / always_on 且规格声明了 effort 时才参与。
  let effortValue: string = '';
  let effortPath: string[] = [];
  const effortSpec: ModelEffortSpec | null = spec.request.effort;
  const thinkingCapable: boolean = control === 'toggle' || control === 'always_on';
  if (thinkingCapable && effortSpec !== null) {
    effortPath = effortSpec.path.slice(0);
    if (effortPath.length === 0) {
      return null;
    }
    const choice: EffortChoice = chooseEffort(effortSpec, selection.effort);
    if (requiredNow(effortSpec.requiredWhen, thinkingEnabled) && choice.value.length === 0) {
      // 规格不完整: 必填强度没有合法值, 不静默取 levels[0]。
      return null;
    }
    if (sendEffortNow(effortSpec.sendWhen, choice, thinkingEnabled)) {
      const effortWrite: ModelFieldWrite = { path: effortPath, value: choice.value };
      writes.push(effortWrite);
      effortValue = choice.value;
    }
  }

  // sampling: support / when / 有值 三者同时满足才下发。
  const sampling: ModelSamplingSpec = spec.request.sampling;
  if (selection.temperature !== undefined
    && samplingConditionMet(sampling.temperature, thinkingEnabled)) {
    const temperatureWrite: ModelFieldWrite = {
      path: ['temperature'],
      value: selection.temperature,
    };
    writes.push(temperatureWrite);
  }
  if (selection.topP !== undefined && samplingConditionMet(sampling.topP, thinkingEnabled)) {
    const topPWrite: ModelFieldWrite = { path: ['top_p'], value: selection.topP };
    writes.push(topPWrite);
  }

  const plan: ModelRequestPlan = {
    writes: writes,
    thinkingControl: control,
    thinkingEnabled: thinkingEnabled,
    effort: effortValue,
    effortPath: effortPath,
  };
  return plan;
}
