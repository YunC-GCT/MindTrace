import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, extname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const typescript = require('../node_modules/typescript');
const testDir = dirname(fileURLToPath(import.meta.url));
const root = resolve(testDir, '../../..');

function normalizeRelativePath(relativePath) {
  return relativePath.replace(/\\/g, '/').replace(/^\.\//, '');
}

function modulePathForRequest(fromRelativePath, request) {
  if (!request.startsWith('.')) {
    return request;
  }
  const fromDir = dirname(fromRelativePath);
  const candidate = normalizeRelativePath(resolve(root, fromDir, request).slice(root.length + 1));
  if (extname(candidate).length > 0) {
    return candidate;
  }
  return `${candidate}.ets`;
}

// 'common' 是模块名而非文件路径，Node 侧无法 require。这里只装配纯模型/纯算法文件
// （无 Kit 依赖），够加载 entry 服务的单测用；需要别的符号时请用 options.mocks 覆盖。
const COMMON_MODEL_FILES = [
  'common/src/main/ets/models/AgentJobModels.ets',
  'common/src/main/ets/models/AgentMemoryModels.ets',
  'common/src/main/ets/models/ConversationSnapshotModels.ets',
  'common/src/main/ets/models/KnowledgeUnitWriteModels.ets',
  'common/src/main/ets/models/NoteEvidenceModels.ets',
  'common/src/main/ets/models/NoteReviewModels.ets',
  'common/src/main/ets/models/CommonTypes.ets',
  'common/src/main/ets/models/NoteGenerationModels.ets',
  'common/src/main/ets/models/CaptureChain.ets',
  'common/src/main/ets/render/ContentProtocol.ets',
  'common/src/main/ets/render/ContentExcerptBuilder.ets',
  'common/src/main/ets/models/GalaxyModels.ets',
  'common/src/main/ets/utils/NoteRetrievalQuery.ets',
  'common/src/main/ets/utils/CitationText.ets',
  'common/src/main/ets/utils/AnswerTextSanitizer.ets',
  'common/src/main/ets/utils/MathSignature.ets',
  'common/src/main/ets/utils/LexicalEmbedding.ets',
  'common/src/main/ets/utils/RrfFusion.ets',
  'common/src/main/ets/utils/EmbeddingModels.ets',
  'common/src/main/ets/ports/EvidencePolicy.ets',
  'entry/src/main/ets/pages/Review/GalaxyGraphProjection.ets',
  'agents/src/main/ets/chat/StreamErrorText.ets',
  'common/src/main/ets/utils/ConversationIdentity.ets',
  'agents/src/main/ets/note/NoteDedupe.ets',
  'entry/src/main/ets/services/RagQueryPlan.ets',
  'agents/src/main/ets/chat/ReplyStyleRules.ets',
];

// 测试可以用 options.mocks.common 覆盖；没覆盖到的符号回落到真实纯模型文件。
function loadCommonModule(options) {
  // Logger 依赖 @ohos.hilog，Node 侧无法求值：给个空实现，免去每个测试重复打桩。
  return loadFacadeModule('common', COMMON_MODEL_FILES, options, {
    Logger: class Logger {
      constructor(_tag) {}
      debug() {}
      info() {}
      warn() {}
      error() {}
    },
  });
}

// agents 也按模块名切了一刀：只装配对话链路（不碰 core/workflows 的图执行）。
const AGENTS_CHAT_FILES = [
  'agents/src/main/ets/chat/IntentClassifier.ets',
  'agents/src/main/ets/chat/ReplyService.ets',
  'agents/src/main/ets/chat/ModelRouter.ets',
  'agents/src/main/ets/chat/AppIntentRules.ets',
  'agents/src/main/ets/chat/AppIntentRouter.ets',
  'agents/src/main/ets/conversation/ConversationState.ets',
  'agents/src/main/ets/conversation/ConversationToolReplyFlags.ets',
  'agents/src/main/ets/conversation/ConversationFormatting.ets',
  'agents/src/main/ets/conversation/ConversationServicePorts.ets',
  'agents/src/main/ets/conversation/ConversationDraftWorkflow.ets',
  'agents/src/main/ets/conversation/ConversationMemoryProjection.ets',
  'agents/src/main/ets/conversation/ConversationWorkflowPorts.ets',
];

function loadAgentsModule(options) {
  return loadFacadeModule('agents', AGENTS_CHAT_FILES, options);
}

function loadFacadeModule(name, files, options, defaults) {
  const facade = Object.assign({}, defaults ?? {});
  const cache = options.cache ?? new Map();
  for (const file of files) {
    if (options.mocks !== undefined && Object.prototype.hasOwnProperty.call(options.mocks, file)) {
      Object.assign(facade, options.mocks[file]);
      continue;
    }
    Object.assign(facade, loadNoteReviewEtsModule(file, { ...options, cache }));
  }
  const override = options.mocks !== undefined
    && Object.prototype.hasOwnProperty.call(options.mocks, name)
    ? options.mocks[name]
    : undefined;
  if (override === undefined) {
    return facade;
  }
  return new Proxy(override, {
    get(target, prop) {
      if (prop in target) {
        return target[prop];
      }
      return prop in facade ? facade[prop] : undefined;
    },
    has(target, prop) {
      return prop in target || prop in facade;
    },
  });
}

export function loadNoteReviewEtsModule(relativePath, options = {}) {
  const normalizedPath = normalizeRelativePath(relativePath);
  const cache = options.cache ?? new Map();
  if (cache.has(normalizedPath)) {
    return cache.get(normalizedPath).exports;
  }

  const absolutePath = resolve(root, normalizedPath);
  const source = readFileSync(absolutePath, 'utf8');
  const transpiled = typescript.transpileModule(source, {
    compilerOptions: {
      esModuleInterop: true,
      module: typescript.ModuleKind.CommonJS,
      target: typescript.ScriptTarget.ES2020,
    },
    fileName: absolutePath,
  }).outputText;

  const module = { exports: {} };
  cache.set(normalizedPath, module);

  const localRequire = (request) => {
    // common / agents 是模块名：先走各自 facade（内部会合并 options.mocks）
    if (request === 'common') {
      return loadCommonModule(options);
    }
    if (request === 'agents') {
      return loadAgentsModule(options);
    }
    const resolvedRequest = modulePathForRequest(normalizedPath, request);
    if (options.mocks !== undefined && Object.prototype.hasOwnProperty.call(options.mocks, resolvedRequest)) {
      return options.mocks[resolvedRequest];
    }
    if (options.mocks !== undefined && Object.prototype.hasOwnProperty.call(options.mocks, request)) {
      return options.mocks[request];
    }
    if (!request.startsWith('.')) {
      // 子 barrel 与深路径（agents/... / common/... / entry/...）：按仓库内路径加载
      if (/^(agents|common|entry)\/src\//.test(request)) {
        return loadNoteReviewEtsModule(`${request}.ets`, { ...options, cache });
      }
      // 系统 Kit 在 Node 侧不可用：给最小桩，保证纯逻辑测试能加载；默认降级路径。
      if (request === '@kit.NaturalLanguageKit') {
        if (options.mocks !== undefined && Object.prototype.hasOwnProperty.call(options.mocks, request)) {
          return options.mocks[request];
        }
        return {
          textProcessing: {
            init: async () => false,
            getWordSegment: async () => [],
            release: async () => true,
          },
        };
      }
      return require(request);
    }
    return loadNoteReviewEtsModule(resolvedRequest, { ...options, cache });
  };

  const context = {
    exports: module.exports,
    module,
    require: localRequire,
    console,
    setTimeout,
    clearTimeout,
    URL,
    ...(options.globals ?? {}),
    __dirname: dirname(absolutePath),
    __filename: absolutePath,
  };
  vm.runInNewContext(transpiled, context, {
    filename: pathToFileURL(absolutePath).href,
  });
  return module.exports;
}

export const chatModelsDependencyMocks = {
  'entry/src/main/ets/overlays/AgentFloatWindow/chat/AgentRunModels.ets': {
    agentRunRevision(_parts) {
      return 0;
    },
    applyStreamEventToAgentRun(parts, _event, _messageId) {
      return parts.map((part) => ({ ...part }));
    },
    copyAgentRunParts(parts) {
      return parts.map((part) => ({ ...part }));
    },
    finishAgentRun(parts) {
      return parts.map((part) => ({ ...part, done: true }));
    },
    projectLegacyAgentRun(_messageId, _reasoning, _content, _streaming) {
      return [];
    },
  },
};
