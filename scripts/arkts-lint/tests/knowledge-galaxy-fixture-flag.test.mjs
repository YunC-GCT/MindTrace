/**
 * knowledge-galaxy-fixture-flag.test.mjs — built-in galaxy sample notes
 *
 * Asserts the source-level state of:
 *   entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets
 *
 * The built-in notes intentionally remain enabled so a fresh install has a
 * populated galaxy. Their reserved IDs must remain protected from deletion.
 *
 * This is a SOURCE-LEVEL test (parses the .ets file and inspects the AST).
 * It does not need a HarmonyOS runtime to run. The companion Hypium
 * test in entry/src/ohosTest/ets/test/ is the behavior-level test that
 * runs in Deveco Studio + emulator.
 *
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse as tsParse } from '@typescript-eslint/parser';
import { preprocessArkUI } from '../parser/index.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
// From tests/ → arkts-lint/ → scripts/ → MindMind/  (3 levels up)
const REPO_ROOT = resolve(__dirname, '../../..');
const TARGET_FILE = join(REPO_ROOT, 'entry/src/main/ets/viewmodels/KnowledgeGalaxyViewModel.ets');

/**
 * Find the `ENABLE_GALAXY_PREVIEW_UNITS` VariableDeclaration in the AST
 * and return the boolean value of its initializer.
 *
 * Returns null if not found (file may have been renamed/restructured).
 */
function readFixtureFlag() {
  const source = readFileSync(TARGET_FILE, 'utf8');
  const preprocessed = preprocessArkUI(source);
  const ast = tsParse(preprocessed, {
    ecmaVersion: 'latest', sourceType: 'module',
    ecmaFeatures: { decorators: true, jsx: true },
    range: true, loc: true, errorRecovery: true,
    errorOnUnknownASTType: false, loggerFn: false,
  });

  function walk(node) {
    if (!node || typeof node !== 'object') return null;
    if (
      node.type === 'VariableDeclarator' &&
      node.id?.type === 'Identifier' &&
      node.id.name === 'ENABLE_GALAXY_PREVIEW_UNITS'
    ) {
      return node.init;
    }
    for (const key of Object.keys(node)) {
      const value = node[key];
      if (Array.isArray(value)) {
        for (const child of value) {
          const r = walk(child);
          if (r !== null) return r;
        }
      } else if (value && typeof value === 'object' && typeof value.type === 'string') {
        const r = walk(value);
        if (r !== null) return r;
      }
    }
    return null;
  }

  return walk(ast);
}

test('built-in galaxy notes remain enabled', () => {
  const init = readFixtureFlag();
  assert.ok(init, 'Could not find ENABLE_GALAXY_PREVIEW_UNITS declaration');
  assert.equal(
    init.type,
    'Literal',
    `Expected Literal initializer, got ${init.type} (${JSON.stringify(init).slice(0, 100)})`
  );
  assert.strictEqual(
    init.value,
    true,
    'ENABLE_GALAXY_PREVIEW_UNITS must stay enabled for the built-in galaxy notes'
  );
});

test('built-in galaxy notes remain protected and include long formulas', () => {
  const source = readFileSync(TARGET_FILE, 'utf8');
  assert.match(source, /if \(this\.isPreviewUnitId\(id\)\) \{\s*return false/);
  assert.match(source, /\\\\sum_\{k=0\}\^\{n\}/);
  assert.match(source, /\\\\operatorname\{rank\}/);
  assert.match(source, /\\\\forall \\\\varepsilon>0/);
});

test('the file is still parseable (regression check)', () => {
  // Just make sure we can read the file and that the search found the declaration.
  const init = readFixtureFlag();
  assert.ok(init, 'KnowledgeGalaxyViewModel.ets was not parseable, or declaration was renamed');
});
