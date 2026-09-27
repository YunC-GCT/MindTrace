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
    const resolvedRequest = modulePathForRequest(normalizedPath, request);
    if (options.mocks !== undefined && Object.prototype.hasOwnProperty.call(options.mocks, resolvedRequest)) {
      return options.mocks[resolvedRequest];
    }
    if (!request.startsWith('.')) {
      if (options.mocks !== undefined && Object.prototype.hasOwnProperty.call(options.mocks, request)) {
        return options.mocks[request];
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
