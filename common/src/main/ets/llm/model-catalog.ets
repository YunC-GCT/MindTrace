/**
 * model-catalog.ets — L2 内置模型清单 + 逐型号请求规格 (ModelSpec)
 *
 * 路径: common/src/main/ets/llm/model-catalog.ets
 * 职责:
 *   1. ModelListing — "能发现的清单": id / displayName / contextWindow /
 *      maxOutputTokens / inputModalities / source。只描述模型存在与容量,
 *      不描述任何请求字段。
 *   2. ModelSpec — "能构造请求的协议": 逐型号、逐 API 产品的 thinking /
 *      effort / sampling / output token / evidence。请求体只由 spec 推导。
 *   3. 两者分开: discovery 返回的 Listing 不能自动变成请求能力。
 * 依赖: 无 (纯静态数据 + 查找函数)
 *
 * 数据流:
 *   providers.ets (L1 route) → model-catalog.ets (L2 listing + spec)
 *     → model-resolver.ets (ID/alias + spec 查找)
 *     → ModelCapabilities.ets / ModelRequestBuilder.ets / LlmClient.ets
 *
 * 字段事实来源 (2026-10-26 实读):
 *   DeepSeek 官方 https://api-docs.deepseek.com
 *     - 开关 {"thinking":{"type":"enabled"}} / {"thinking":{"type":"disabled"}}
 *     - 强度顶层 reasoning_effort: none | low | high | max; none = 关闭思考
 *     - 思考默认开启, 默认强度 high; 思考开启时 temperature/top_p 不生效
 *     - deepseek-flash / deepseek-v4-pro 均支持 low/high/max
 *   阿里百炼 https://help.aliyun.com/zh/model-studio/deep-thinking
 *     - 开关 enable_thinking: true | false (扁平布尔, 非 OpenAI 标准参数)
 *     - 混合思考模型 (如 qwen3.6-plus) 可关; 仅思考模型 (如 glm-5.3 / kimi-k3) 不可关
 *     - 第三个控制 thinking_budget (本规格未建模, 见报告)
 *     - reasoning_effort 仅对百炼上的 DeepSeek-V4 系列有效, 不套到 Qwen
 *
 *   智谱 GLM 直连 https://docs.bigmodel.cn/cn/guide/capabilities/thinking-mode
 *     - 开关 {"thinking":{"type":"enabled"|"disabled"}}
 *     - GLM-5.3 / GLM-5.3-FLASH 强制思考不可关; GLM-5 / 5.1 / 5.2 / 4.7 默认可关
 *     - 无 effort / 强度参数
 *   Kimi 直连 https://platform.kimi.com/docs/api/models-overview
 *     - kimi-k2.6: thinking {"type":"enabled"(默认)|"disabled"}; 不支持 reasoning_effort
 *     - kimi-k2.7-code / -highspeed: 始终开启, 传 disabled 报错; 不支持 effort
 *     - kimi-k3: 不传 thinking, 始终推理; reasoning_effort low|high|max, 默认 max
 *     - temperature / top_p 全系固定, 传别的值报错 → sampling.temperature.support='no'
 *   火山方舟豆包 https://docs.volcengine.com/docs/ark/deep-thinking
 *     - 开关 {"thinking":{"type":"enabled"|"disabled"}}; 无 effort
 *     - 默认值文档未明写 → defaultEnabled=true + evidence.status='partial'
 *
 * 仍未核实: tongyi/qwen3-max 只有"百炼 OpenAI 兼容端点"的协议事实, 没有该型号
 * 混合/仅思考的证据, 因此 control 是 unverified。
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any / unknown; FieldWrite 的值显式收敛为 string | boolean | number。
 *   - 所有条目显式标注 ModelListing / ModelSpec, 不写裸对象字面量。
 *   - 规格是静态常量, 这里不做网络或 preferences 读写。
 */

// ==================== Listing (可发现清单) ====================

export interface ModelListing {
  id: string;
  displayName: string;
  providerId: string;
  contextWindow: number;
  maxOutputTokens: number;
  inputModalities: string[];        // 'text' | 'image'
  source: string;                   // 'catalog' | 'discovery' | 'user'
}

export interface ProviderCatalog {
  providerId: string;
  defaultModelId: string;
  models: ModelListing[];
}

// ==================== ModelSpec (请求协议) ====================

export type EvidenceStatus = 'verified' | 'partial' | 'unverified';
export type ThinkingControl = 'toggle' | 'always_on' | 'unsupported' | 'unverified';
// 'no' 不是"可传但可能失效": 该型号传了会报错, 请求必须省略这个字段。
export type SamplingSupport = 'yes' | 'no' | 'unknown';
export type SamplingWhen = 'always' | 'thinking_on' | 'thinking_off' | 'never';
export type EffortSendWhen = 'always' | 'thinking_on' | 'selected';
export type EffortRequiredWhen = 'never' | 'thinking_on' | 'always';

// JSONValue 的受限子集: 请求字段只可能是字符串 / 布尔 / 数字。
export type ModelFieldValue = string | boolean | number;

// 写入用路径: ['enable_thinking'] 写扁平布尔, ['thinking','type'] 写嵌套字符串。
export interface ModelFieldWrite {
  path: string[];
  value: ModelFieldValue;
}

export interface ModelSpecSource {
  url: string;
  verifiedAt: string;
  covers: string[];
}

export interface ModelSpecEvidence {
  status: EvidenceStatus;
  sources: ModelSpecSource[];
}

export interface ModelThinkingSpec {
  control: ThinkingControl;
  defaultEnabled: boolean | null;
  on: ModelFieldWrite[];
  off: ModelFieldWrite[];
}

export interface ModelSamplingRule {
  support: SamplingSupport;
  when: SamplingWhen;
}

export interface ModelSamplingSpec {
  temperature: ModelSamplingRule;
  topP: ModelSamplingRule;
}

export interface ModelEffortSpec {
  path: string[];
  levels: string[];
  // 设计稿字段名为 default; ArkTS 里 default 是保留字, 这里用 defaultLevel。
  defaultLevel: string | null;
  sendWhen: EffortSendWhen;
  requiredWhen: EffortRequiredWhen;
}

export interface ModelRequestSpec {
  outputTokenPath: string[];
  thinking: ModelThinkingSpec;
  effort: ModelEffortSpec | null;
  sampling: ModelSamplingSpec;
}

export interface ModelSpec {
  schemaVersion: number;
  id: string;
  providerId: string;
  displayName: string;
  protocol: string;                 // 'openai-chat-completions'
  contextWindow: number;            // 0 = 未给
  maxOutputTokens: number;          // 0 = 未给, 不夹取
  inputModalities: string[];
  evidence: ModelSpecEvidence;
  request: ModelRequestSpec;
}

const MODEL_SPEC_SCHEMA_VERSION: number = 1;

// ==================== 证据来源 ====================

const DEEPSEEK_SOURCE: ModelSpecSource = {
  url: 'https://api-docs.deepseek.com',
  verifiedAt: '2026-10-26',
  covers: ['thinking.type', 'reasoning_effort', 'temperature/top_p 思考模式', 'max_tokens'],
};

const BAILIAN_SOURCE: ModelSpecSource = {
  url: 'https://help.aliyun.com/zh/model-studio/deep-thinking',
  verifiedAt: '2026-10-26',
  covers: ['enable_thinking', 'thinking_budget', 'reasoning_effort 仅 DeepSeek-V4'],
};

const GLM_SOURCE: ModelSpecSource = {
  url: 'https://docs.bigmodel.cn/cn/guide/capabilities/thinking-mode',
  verifiedAt: '2026-10-26',
  covers: ['thinking.type', 'GLM-5.3/5.3-FLASH 强制思考', 'GLM-5/5.1/5.2/4.7 默认可关', '无 effort'],
};

const KIMI_SOURCE: ModelSpecSource = {
  url: 'https://platform.kimi.com/docs/api/models-overview',
  verifiedAt: '2026-10-26',
  covers: ['thinking.type', 'thinking.keep', 'reasoning_effort', 'temperature/top_p 固定'],
};

const DOUBAO_SOURCE: ModelSpecSource = {
  url: 'https://docs.volcengine.com/docs/ark/deep-thinking',
  verifiedAt: '2026-10-26',
  covers: ['thinking.type', '无 effort', '默认值未明写'],
};

const DEEPSEEK_EVIDENCE: ModelSpecEvidence = {
  status: 'verified',
  sources: [DEEPSEEK_SOURCE],
};

const BAILIAN_EVIDENCE: ModelSpecEvidence = {
  status: 'verified',
  sources: [BAILIAN_SOURCE],
};

const GLM_EVIDENCE: ModelSpecEvidence = {
  status: 'verified',
  sources: [GLM_SOURCE],
};

const KIMI_EVIDENCE: ModelSpecEvidence = {
  status: 'verified',
  sources: [KIMI_SOURCE],
};

// 思考字段已证实, 但文档未明写默认开启/关闭 → partial。
const DOUBAO_EVIDENCE: ModelSpecEvidence = {
  status: 'partial',
  sources: [DOUBAO_SOURCE],
};

// ==================== 可复用规格片段 ====================

// DeepSeek: 思考开启时 temperature/top_p 不生效, 只在关闭时下发。
const DEEPSEEK_SAMPLING: ModelSamplingSpec = {
  temperature: { support: 'yes', when: 'thinking_off' },
  topP: { support: 'yes', when: 'thinking_off' },
};

// DeepSeek 关闭思考: 文档同时给出 thinking.type=disabled 与 reasoning_effort=none,
// 两者语义一致; 关闭分支固定写这两个字段, 不写 active effort。
const DEEPSEEK_THINKING: ModelThinkingSpec = {
  control: 'toggle',
  defaultEnabled: true,
  on: [{ path: ['thinking', 'type'], value: 'enabled' }],
  off: [
    { path: ['thinking', 'type'], value: 'disabled' },
    { path: ['reasoning_effort'], value: 'none' },
  ],
};

// none 是关闭分支的固定写入值, 不是 UI 档位 — levels 只列 low/high/max。
const DEEPSEEK_EFFORT: ModelEffortSpec = {
  path: ['reasoning_effort'],
  levels: ['low', 'high', 'max'],
  defaultLevel: 'high',
  sendWhen: 'thinking_on',
  requiredWhen: 'thinking_on',
};

// 百炼混合思考: 扁平布尔开关, 默认值未核实 → null (不选就不写)。
const BAILIAN_TOGGLE_THINKING: ModelThinkingSpec = {
  control: 'toggle',
  defaultEnabled: null,
  on: [{ path: ['enable_thinking'], value: true }],
  off: [{ path: ['enable_thinking'], value: false }],
};

// 百炼仅思考模型: 不可关闭, on/off 均为空。
const BAILIAN_ALWAYS_ON_THINKING: ModelThinkingSpec = {
  control: 'always_on',
  defaultEnabled: true,
  on: [],
  off: [],
};

// 百炼 Qwen 没有 reasoning_effort (只对 DeepSeek-V4 系列有效); sampling 未核实。
const BAILIAN_SAMPLING_UNKNOWN: ModelSamplingSpec = {
  temperature: { support: 'unknown', when: 'never' },
  topP: { support: 'unknown', when: 'never' },
};

// 智谱 GLM / Kimi / 豆包直连都是嵌套 {"thinking":{"type":...}} 开关。
const NESTED_TOGGLE_THINKING: ModelThinkingSpec = {
  control: 'toggle',
  defaultEnabled: true,
  on: [{ path: ['thinking', 'type'], value: 'enabled' }],
  off: [{ path: ['thinking', 'type'], value: 'disabled' }],
};

// 强制思考: on/off 必须为空 — 请求层按 on/off 写开关, 空数组 = 一个字段都不写。
const NESTED_ALWAYS_ON_THINKING: ModelThinkingSpec = {
  control: 'always_on',
  defaultEnabled: true,
  on: [],
  off: [],
};

// 文档只证实了 thinking 字段, 没给 temperature/top_p 事实 → 不猜、不写。
const UNSET_SAMPLING: ModelSamplingSpec = {
  temperature: { support: 'unknown', when: 'never' },
  topP: { support: 'unknown', when: 'never' },
};

// Kimi: temperature/top_p 固定, 传别的值报错。
// support='no' 的语义是"必须省略", 不是"可以传但可能失效"。
const KIMI_FIXED_SAMPLING: ModelSamplingSpec = {
  temperature: { support: 'no', when: 'never' },
  topP: { support: 'no', when: 'never' },
};

// Kimi k3: 不传 thinking 字段, 始终推理; effort 支持 low|high|max, 默认 max。
const KIMI_K3_EFFORT: ModelEffortSpec = {
  path: ['reasoning_effort'],
  levels: ['low', 'high', 'max'],
  defaultLevel: 'max',
  sendWhen: 'thinking_on',
  requiredWhen: 'thinking_on',
};

const UNVERIFIED_THINKING: ModelThinkingSpec = {
  control: 'unverified',
  defaultEnabled: null,
  on: [],
  off: [],
};

const UNVERIFIED_SAMPLING: ModelSamplingSpec = {
  temperature: { support: 'unknown', when: 'never' },
  topP: { support: 'unknown', when: 'never' },
};

const OPENAI_CHAT_PROTOCOL: string = 'openai-chat-completions';

// ==================== 内置 Listing ====================

const DEEPSEEK_FLASH: ModelListing = {
  id: 'deepseek-flash',
  displayName: 'DeepSeek-V4.1-Flash',
  providerId: 'deepseek',
  contextWindow: 1048576,
  maxOutputTokens: 393216,
  inputModalities: ['text', 'image'],
  source: 'catalog',
};

const DEEPSEEK_V4_PRO: ModelListing = {
  id: 'deepseek-v4-pro',
  displayName: 'DeepSeek-V4-Pro',
  providerId: 'deepseek',
  contextWindow: 1048576,
  maxOutputTokens: 393216,
  inputModalities: ['text'],
  source: 'catalog',
};

const DEEPSEEK_CATALOG: ProviderCatalog = {
  providerId: 'deepseek',
  defaultModelId: 'deepseek-v4-pro',
  models: [DEEPSEEK_FLASH, DEEPSEEK_V4_PRO],
};

// 能力待 discovery 或人工补齐 — 只保留 providers.ets 已有的默认模型 ID。
// Listing 为空不等于"不支持思考", 只是"还没有可发现清单"; 请求规格另由
// ModelSpec 表达 (见下方 tongyi 的 unverified spec 与 GLM/Kimi/豆包 spec)。
const TONGYI_CATALOG: ProviderCatalog = {
  providerId: 'tongyi',
  defaultModelId: 'qwen3-max',
  models: [],
};

const GLM_CATALOG: ProviderCatalog = {
  providerId: 'glm',
  defaultModelId: 'glm-5.3',
  models: [],
};

const KIMI_CATALOG: ProviderCatalog = {
  providerId: 'kimi',
  defaultModelId: 'kimi-k2.6',
  models: [],
};

const DOUBAO_CATALOG: ProviderCatalog = {
  providerId: 'doubao',
  defaultModelId: 'doubao-seed-1.6',
  models: [],
};

const PROVIDER_CATALOGS: ProviderCatalog[] = [
  DEEPSEEK_CATALOG,
  TONGYI_CATALOG,
  GLM_CATALOG,
  KIMI_CATALOG,
  DOUBAO_CATALOG,
];

// ==================== 内置 ModelSpec ====================

const DEEPSEEK_FLASH_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'deepseek-flash',
  providerId: 'deepseek',
  displayName: 'DeepSeek-V4.1-Flash',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 1048576,
  maxOutputTokens: 393216,
  inputModalities: ['text', 'image'],
  evidence: DEEPSEEK_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: DEEPSEEK_THINKING,
    effort: DEEPSEEK_EFFORT,
    sampling: DEEPSEEK_SAMPLING,
  },
};

const DEEPSEEK_V4_PRO_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'deepseek-v4-pro',
  providerId: 'deepseek',
  displayName: 'DeepSeek-V4-Pro',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 1048576,
  maxOutputTokens: 393216,
  inputModalities: ['text'],
  evidence: DEEPSEEK_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: DEEPSEEK_THINKING,
    effort: DEEPSEEK_EFFORT,
    sampling: DEEPSEEK_SAMPLING,
  },
};

// 百炼默认型号: 有协议事实, 但没有该型号 toggle / always_on 的证据。
const QWEN3_MAX_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'qwen3-max',
  providerId: 'tongyi',
  displayName: 'qwen3-max',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: { status: 'unverified', sources: [BAILIAN_SOURCE] },
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: UNVERIFIED_THINKING,
    effort: null,
    sampling: UNVERIFIED_SAMPLING,
  },
};

// 用户明确给出的"混合思考模型可关"例子。
const QWEN36_PLUS_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'qwen3.6-plus',
  providerId: 'tongyi',
  displayName: 'qwen3.6-plus',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: BAILIAN_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: BAILIAN_TOGGLE_THINKING,
    effort: null,
    sampling: BAILIAN_SAMPLING_UNKNOWN,
  },
};

// 百炼上的仅思考模型: 同一 modelId 在直连有各自证据 (如 kimi-k3 直连有 effort),
// 所以 spec 必须按 providerId 分开 — 不能按 vendor 名推导字段。
const TONGYI_GLM53_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-5.3',
  providerId: 'tongyi',
  displayName: 'glm-5.3',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: BAILIAN_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: BAILIAN_ALWAYS_ON_THINKING,
    effort: null,
    sampling: BAILIAN_SAMPLING_UNKNOWN,
  },
};

const TONGYI_KIMI_K3_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k3',
  providerId: 'tongyi',
  displayName: 'kimi-k3',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: BAILIAN_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: BAILIAN_ALWAYS_ON_THINKING,
    effort: null,
    sampling: BAILIAN_SAMPLING_UNKNOWN,
  },
};

// ===== 智谱 GLM 直连 =====
// GLM-5.3 / GLM-5.3-FLASH: 强制思考, 不能关闭; 没有 effort 参数。
const GLM53_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-5.3',
  providerId: 'glm',
  displayName: 'glm-5.3',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: GLM_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

const GLM53_FLASH_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-5.3-flash',
  providerId: 'glm',
  displayName: 'glm-5.3-flash',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: GLM_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

// GLM-5 / 5.1 / 5.2 / 4.7: 默认开启 thinking, 可关闭; 没有 effort 参数。
const GLM5_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-5',
  providerId: 'glm',
  displayName: 'glm-5',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: GLM_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_TOGGLE_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

const GLM51_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-5.1',
  providerId: 'glm',
  displayName: 'glm-5.1',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: GLM_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_TOGGLE_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

const GLM52_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-5.2',
  providerId: 'glm',
  displayName: 'glm-5.2',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: GLM_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_TOGGLE_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

const GLM47_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'glm-4.7',
  providerId: 'glm',
  displayName: 'glm-4.7',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: GLM_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_TOGGLE_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

// ===== Kimi 直连 =====
// kimi-k2.6: 默认开启, 可关; 不支持 reasoning_effort。
const KIMI_K26_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k2.6',
  providerId: 'kimi',
  displayName: 'kimi-k2.6',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: KIMI_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_TOGGLE_THINKING,
    effort: null,
    sampling: KIMI_FIXED_SAMPLING,
  },
};

// kimi-k2.7-code / -highspeed: 始终开启, 传 disabled 会报错; 不支持 effort。
const KIMI_K27_CODE_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k2.7-code',
  providerId: 'kimi',
  displayName: 'kimi-k2.7-code',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: KIMI_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: null,
    sampling: KIMI_FIXED_SAMPLING,
  },
};

const KIMI_K27_CODE_HIGHSPEED_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k2.7-code-highspeed',
  providerId: 'kimi',
  displayName: 'kimi-k2.7-code-highspeed',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: KIMI_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: null,
    sampling: KIMI_FIXED_SAMPLING,
  },
};

// kimi-k3: 不传 thinking 字段, 始终推理; reasoning_effort 默认 max。
const KIMI_K3_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k3',
  providerId: 'kimi',
  displayName: 'kimi-k3',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: KIMI_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: KIMI_K3_EFFORT,
    sampling: KIMI_FIXED_SAMPLING,
  },
};

// kimi-k3.1-pro / kimi-k3.1-pro-highspeed: 参数约束与 kimi-k3 完全一致
// （platform.kimi.com/docs/api/models-overview: "均适用于这两个模型"）。
// 高速版与标准版同一模型, 仅输出速度不同。
const KIMI_K31_PRO_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k3.1-pro',
  providerId: 'kimi',
  displayName: 'kimi-k3.1-pro',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: KIMI_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: KIMI_K3_EFFORT,
    sampling: KIMI_FIXED_SAMPLING,
  },
};

const KIMI_K31_PRO_HIGHSPEED_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'kimi-k3.1-pro-highspeed',
  providerId: 'kimi',
  displayName: 'kimi-k3.1-pro-highspeed',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: KIMI_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_ALWAYS_ON_THINKING,
    effort: KIMI_K3_EFFORT,
    sampling: KIMI_FIXED_SAMPLING,
  },
};

// ===== 火山方舟豆包 =====
// 只对带「深度思考」标签的模型生效; 默认值未明写 → defaultEnabled=true 但 evidence partial。
const DOUBAO_SEED_16_SPEC: ModelSpec = {
  schemaVersion: MODEL_SPEC_SCHEMA_VERSION,
  id: 'doubao-seed-1.6',
  providerId: 'doubao',
  displayName: 'doubao-seed-1.6',
  protocol: OPENAI_CHAT_PROTOCOL,
  contextWindow: 0,
  maxOutputTokens: 0,
  inputModalities: [],
  evidence: DOUBAO_EVIDENCE,
  request: {
    outputTokenPath: ['max_tokens'],
    thinking: NESTED_TOGGLE_THINKING,
    effort: null,
    sampling: UNSET_SAMPLING,
  },
};

const BUILTIN_MODEL_SPECS: ModelSpec[] = [
  DEEPSEEK_FLASH_SPEC,
  DEEPSEEK_V4_PRO_SPEC,
  QWEN3_MAX_SPEC,
  QWEN36_PLUS_SPEC,
  TONGYI_GLM53_SPEC,
  TONGYI_KIMI_K3_SPEC,
  GLM53_SPEC,
  GLM53_FLASH_SPEC,
  GLM5_SPEC,
  GLM51_SPEC,
  GLM52_SPEC,
  GLM47_SPEC,
  KIMI_K26_SPEC,
  KIMI_K27_CODE_SPEC,
  KIMI_K27_CODE_HIGHSPEED_SPEC,
  KIMI_K3_SPEC,
  KIMI_K31_PRO_SPEC,
  KIMI_K31_PRO_HIGHSPEED_SPEC,
  DOUBAO_SEED_16_SPEC,
];

// 落盘的 model_specs 覆盖层: 缺省/非法项一律回落内置规格。
let MODEL_SPEC_OVERRIDES: Record<string, ModelSpec> = {};

// ==================== 查找 ====================

export function modelSpecKey(providerId: string, modelId: string): string {
  return providerId.trim() + '/' + modelId.trim();
}

// ==================== 能力信号 (chip 与规格控件共用的唯一真源) ====================

// 'verified'     字段已核实, 可放心按规格构造请求
// 'partial'      字段已核实, 但默认值未证实 (如豆包未明写默认开关)
// 'unconfirmed'  没有规格, 或规格标了 unverified — 两者都是"不知道", 不是"不支持"
export type CapabilitySignal = 'verified' | 'partial' | 'unconfirmed';

// 只看规格证据, 不看清单是否存在: 清单为空只代表"没有可发现清单"。
export function capabilitySignal(spec: ModelSpec | null): CapabilitySignal {
  if (spec === null) {
    return 'unconfirmed';
  }
  if (spec.evidence.status === 'verified') {
    return 'verified';
  }
  if (spec.evidence.status === 'partial') {
    return 'partial';
  }
  return 'unconfirmed';
}

export function getProviderCatalog(providerId: string): ProviderCatalog | null {
  const id: string = providerId.trim();
  for (const catalog of PROVIDER_CATALOGS) {
    if (catalog.providerId === id) {
      return catalog;
    }
  }
  return null;
}

export function getCatalogDefaultListing(providerId: string): ModelListing | null {
  const catalog: ProviderCatalog | null = getProviderCatalog(providerId);
  if (catalog === null) {
    return null;
  }
  for (const listing of catalog.models) {
    if (listing.id === catalog.defaultModelId) {
      return listing;
    }
  }
  return null;
}

export function getModelSpec(providerId: string, modelId: string): ModelSpec | null {
  const provider: string = providerId.trim();
  const model: string = modelId.trim();
  if (provider.length === 0 || model.length === 0) {
    return null;
  }
  const override: ModelSpec | undefined = MODEL_SPEC_OVERRIDES[modelSpecKey(provider, model)];
  if (override !== undefined) {
    return override;
  }
  for (const spec of BUILTIN_MODEL_SPECS) {
    if (spec.providerId === provider && spec.id === model) {
      return spec;
    }
  }
  return null;
}

export function getBuiltinModelSpecs(): ModelSpec[] {
  return BUILTIN_MODEL_SPECS.slice(0);
}

export function setModelSpecOverrides(overrides: Record<string, ModelSpec>): void {
  MODEL_SPEC_OVERRIDES = overrides;
}

// 松散校验: 只放行结构完整的规格; 任何一层缺失都让该条回落内置 / 无规格。
export function isValidModelSpec(value: ModelSpec): boolean {
  if (value === null || value === undefined) {
    return false;
  }
  if (typeof value.id !== 'string' || value.id.trim().length === 0) {
    return false;
  }
  if (typeof value.providerId !== 'string' || value.providerId.trim().length === 0) {
    return false;
  }
  if (typeof value.schemaVersion !== 'number') {
    return false;
  }
  if (typeof value.protocol !== 'string' || value.protocol.length === 0) {
    return false;
  }
  const evidence: ModelSpecEvidence = value.evidence;
  if (evidence === null || evidence === undefined
    || typeof evidence.status !== 'string' || !Array.isArray(evidence.sources)) {
    return false;
  }
  const request: ModelRequestSpec = value.request;
  if (request === null || request === undefined) {
    return false;
  }
  if (!Array.isArray(request.outputTokenPath) || request.outputTokenPath.length === 0) {
    return false;
  }
  const thinking: ModelThinkingSpec = request.thinking;
  if (thinking === null || thinking === undefined || typeof thinking.control !== 'string') {
    return false;
  }
  if (!Array.isArray(thinking.on) || !Array.isArray(thinking.off)) {
    return false;
  }
  const sampling: ModelSamplingSpec = request.sampling;
  if (sampling === null || sampling === undefined
    || sampling.temperature === undefined || sampling.topP === undefined) {
    return false;
  }
  return true;
}
