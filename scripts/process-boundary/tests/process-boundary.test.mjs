#!/usr/bin/env node
/**
 * scripts/process-boundary/tests/process-boundary.test.mjs
 *
 * 回归测试：检查器必须抓住 2026-10-24 的真实事故形态
 * （barrel 导出受限 Kit → 扩展入口仅 import 别的符号也会被传染），
 * 同时不能把 export type 误判成运行时加载。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { runCheck } from '../check.mjs';

function fixture(files) {
  const root = mkdtempSync(join(tmpdir(), 'proc-boundary-'));
  for (const [rel, content] of Object.entries(files)) {
    const abs = join(root, rel);
    mkdirSync(join(abs, '..'), { recursive: true });
    writeFileSync(abs, content, 'utf8');
  }
  return root;
}

const AGENT_MANIFEST = `{
  "module": {
    "name": "entry",
    "type": "entry",
    "abilities": [{ "name": "EntryAbility", "srcEntry": "./ets/entryability/EntryAbility.ets" }],
    "extensionAbilities": [
      { "name": "AgentExtAbility", "srcEntry": "./ets/agentextability/AgentExtAbility.ets", "type": "agent" }
    ]
  }
}`;

test('barrel 传染：扩展入口只 import LlmConfig，也会被受限 Kit 命中', () => {
  const root = fixture({
    'entry/src/main/module.json5': AGENT_MANIFEST,
    'entry/src/main/ets/entryability/EntryAbility.ets': `import { LlmConfig } from 'common';\n`,
    'entry/src/main/ets/agentextability/AgentExtAbility.ets': `import { LlmConfig } from 'common';\n`,
    'common/oh-package.json5': '{ "name": "common", "main": "./src/main/ets/Index.ets" }',
    'common/src/main/ets/Index.ets': [
      `export { LlmConfig } from './llm/LlmConfig';`,
      `export { LocalChatProvider } from './llm/LocalChatProvider';`,
    ].join('\n'),
    'common/src/main/ets/llm/LlmConfig.ets': `export class LlmConfig {}\n`,
    'common/src/main/ets/llm/LocalChatProvider.ets': `import { localChatModel } from '@kit.DataAugmentationKit';\n`,
  });

  const { ok, graph } = runCheck(root);
  assert.equal(ok, false, '应当拦下扩展进程可达受限 Kit');
  assert.ok(graph.hits.some((h) => h.kit === '@kit.DataAugmentationKit' && h.process === 'agent'));
  const hit = graph.hits.find((h) => h.kit === '@kit.DataAugmentationKit');
  assert.ok(hit.chain.join(' → ').includes('LocalChatProvider'), '报错要带上完整链');
});

test('export type 不算运行时加载：类型导出不应触发命中', () => {
  const root = fixture({
    'entry/src/main/module.json5': AGENT_MANIFEST,
    'entry/src/main/ets/entryability/EntryAbility.ets': `import { T } from 'common';\n`,
    'entry/src/main/ets/agentextability/AgentExtAbility.ets': `import type { T } from 'common';\nexport class A {}\n`,
    'common/oh-package.json5': '{ "name": "common", "main": "./src/main/ets/Index.ets" }',
    'common/src/main/ets/Index.ets': `export type { T } from './models/T';\n`,
    'common/src/main/ets/models/T.ets': `import { localChatModel } from '@kit.DataAugmentationKit';\nexport interface T { a: string }\n`,
  });

  const { ok, graph } = runCheck(root);
  assert.equal(ok, true, '类型导出在运行时被擦除，不应命中');
  assert.equal(graph.hits.length, 0);
});

test('loadContent 页面要进可达图', () => {
  const root = fixture({
    'entry/src/main/module.json5': `{
      "module": { "name": "entry", "type": "entry",
        "extensionAbilities": [
          { "name": "AgentUIExtAbility", "srcEntry": "./ets/agentextability/AgentUIExtAbility.ets", "type": "agentUI" }
        ] }
    }`,
    'entry/src/main/ets/agentextability/AgentUIExtAbility.ets':
      `class S { loadContent(p: string) {} }\nconst s = new S();\ns.loadContent('pages/AgentUiCard');\n`,
    'entry/src/main/ets/pages/AgentUiCard.ets': `import { localChatModel } from '@kit.DataAugmentationKit';\n`,
  });

  const { ok, graph } = runCheck(root);
  assert.equal(ok, false, '页面里的受限能力必须被抓到');
  assert.ok(graph.hits.some((h) => h.kit === '@kit.DataAugmentationKit' && h.process === 'agentUI'));
});

test('动态 import 只算警告：懒加载不构成加载期越界', () => {
  const root = fixture({
    'entry/src/main/module.json5': AGENT_MANIFEST,
    'entry/src/main/ets/entryability/EntryAbility.ets': `import { P } from 'common';\n`,
    'entry/src/main/ets/agentextability/AgentExtAbility.ets': `import { P } from 'common';\n`,
    'common/oh-package.json5': '{ "name": "common", "main": "./src/main/ets/Index.ets" }',
    'common/src/main/ets/Index.ets': `export { P } from './llm/P';\n`,
    'common/src/main/ets/llm/P.ets':
      `let ns: ESObject | null = null;\nasync function k(): Promise<ESObject> {\n  if (ns === null) { ns = await import('@kit.DataAugmentationKit') as ESObject; }\n  return ns;\n}\nexport class P {}\n`,
  });

  const { ok, graph } = runCheck(root);
  assert.equal(ok, true, '懒加载不应让 gate 失败');
  const hit = graph.hits.find((h) => h.kit === '@kit.DataAugmentationKit');
  assert.ok(hit, '仍要报出来，供人确认该路径不会被扩展调用');
  assert.equal(hit.lazy, true);
});

test('import type 不是加载边（运行时被擦除）', () => {
  const root = fixture({
    'entry/src/main/module.json5': AGENT_MANIFEST,
    'entry/src/main/ets/entryability/EntryAbility.ets': `import type { T } from 'common';\n`,
    'entry/src/main/ets/agentextability/AgentExtAbility.ets': `import type { T } from 'common';\n`,
    'common/oh-package.json5': '{ "name": "common", "main": "./src/main/ets/Index.ets" }',
    'common/src/main/ets/Index.ets': `export { kitHolder } from './llm/kitHolder';\n`,
    'common/src/main/ets/llm/kitHolder.ets': `import { localChatModel } from '@kit.DataAugmentationKit';\nexport const kitHolder = localChatModel;\n`,
  });

  const { ok, graph } = runCheck(root);
  assert.equal(ok, true);
  assert.equal(graph.hits.length, 0, '类型导入不该把 Kit 拉进图');
});

test('卡片宿主进程允许 FormKit，main 进程也允许（推快照）', () => {
  const root = fixture({
    'entry/src/main/module.json5': AGENT_MANIFEST.replace(
      `{ "name": "AgentExtAbility", "srcEntry": "./ets/agentextability/AgentExtAbility.ets", "type": "agent" }`,
      `{ "name": "FormAbility", "srcEntry": "./ets/formability/FormAbility.ets", "type": "form" }`,
    ),
    'entry/src/main/ets/entryability/EntryAbility.ets': `import { formProvider } from '@kit.FormKit';\n`,
    'entry/src/main/ets/formability/FormAbility.ets': `import { FormExtensionAbility } from '@kit.FormKit';\n`,
  });

  const { ok } = runCheck(root);
  assert.equal(ok, true);
});
