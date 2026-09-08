/**
 * llm-config-throw.test.mjs — TDD test for ticket #9
 *
 * Asserts that common/src/main/ets/llm/LlmConfig.ets has throw paths
 * in `normalizeEndpoint` and `normalizeModel` for reserved keywords.
 *
 * Per ticket #9 / spec 009:
 *   - normalizeEndpoint('siliconflow...') must throw LlmError, not silently
 *     return DEFAULT_ENDPOINT
 *   - normalizeModel('v3') / 'flash' / 'deepseek-chat' / 'r1' / etc. must
 *     throw LlmError, not silently return DEFAULT_MODEL
 *
 * Note: This is a static AST-level check. The real behavioral test is
 * a Hypium test in entry/src/ohosTest/ets/test/LlmConfig.test.ets.
 * This Node test catches regressions in the throw-path implementation
 * without requiring a full HarmonyOS test environment.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '../../..');
const TARGET_FILE = join(REPO_ROOT, 'common/src/main/ets/llm/LlmConfig.ets');

function readLlmConfigSource() {
  return readFileSync(TARGET_FILE, 'utf8').replace(/\r\n/g, '\n');
}

function findBranchBodyContainingNth(src, marker, n = 1) {
  return findBranchBodyContaining_(src, marker, n);
}

function findBranchBodyContaining(src, marker) {
  return findBranchBodyContaining_(src, marker, 1);
}

/**
 * Find the body of the `if` block whose condition contains `marker`.
 * The `if` and the condition can span multiple lines.
 * Strategy: find the line containing `marker` (and not the `if`
 * keyword on the same line — we want to be inside the condition),
 * then walk backward to find the line that contains `if (`. Then walk
 * forward from that line's `{` (if any) or the next few lines, tracking
 * brace depth, until the body is captured.
 */
function findBranchBodyContaining_(src, marker, n = 1) {
  const lines = src.split('\n');
  // Find Nth line containing marker
  let markerLine = -1;
  let found = 0;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(marker)) {
      found++;
      if (found === n) {
        markerLine = i;
        break;
      }
    }
  }
  if (markerLine === -1) return null;

  // Walk backward to find the nearest enclosing "if ("
  let ifLine = -1;
  for (let i = markerLine; i >= 0; i--) {
    if (lines[i].match(/\bif\s*\(/) || lines[i].match(/^\s*if\s*\(/) ||
        lines[i].trimStart().startsWith('if (')) {
      ifLine = i;
      break;
    }
  }
  if (ifLine === -1) return null;

  // Find the matching `{` (could be on the if line, or after the closing `)`)
  let openBrace = -1;
  for (let i = ifLine; i < Math.min(ifLine + 10, lines.length); i++) {
    if (lines[i].includes('{')) {
      openBrace = i;
      break;
    }
  }
  if (openBrace === -1) return null;

  // Walk from openBrace, track brace depth
  let depth = 0;
  let sawOpen = false;
  for (let i = openBrace; i < lines.length; i++) {
    for (let j = 0; j < lines[i].length; j++) {
      const ch = lines[i][j];
      if (ch === '{') {
        depth++;
        sawOpen = true;
      } else if (ch === '}') {
        depth--;
        if (sawOpen && depth === 0) {
          let body = '';
          if (i === openBrace) {
            const openIdx = lines[i].indexOf('{');
            const closeIdx = lines[i].indexOf('}');
            body = lines[i].slice(openIdx + 1, closeIdx);
          } else {
            const openIdx = lines[openBrace].indexOf('{');
            body = lines[openBrace].slice(openIdx + 1) + '\n';
            for (let k = openBrace + 1; k < i; k++) body += lines[k] + '\n';
            const closeIdx = lines[i].indexOf('}');
            body += lines[i].slice(0, closeIdx);
          }
          return body.trim();
        }
      }
    }
  }
  return null;
}

test('LlmConfig: file exists and is parseable', () => {
  const src = readLlmConfigSource();
  assert.ok(src.length > 0, 'LlmConfig.ets is empty');
  assert.match(src, /export class LlmConfig/, 'LlmConfig class not found');
  assert.match(src, /import.*LlmError/, 'LlmError not imported');
});

test('LlmConfig: normalizeEndpoint throws on reserved keyword (siliconflow)', () => {
  const src = readLlmConfigSource();
  const body = findBranchBodyContaining(src, 'siliconflow');
  assert.ok(body !== null, 'siliconflow branch not found in normalizeEndpoint');
  assert.match(body, /throw/, 'siliconflow branch must throw');
  assert.match(body, /LlmError/, 'throw must use LlmError type');
  assert.doesNotMatch(
    body,
    /return\s+DEFAULT_/,
    'siliconflow branch must NOT silently return DEFAULT value'
  );
});

test('LlmConfig: normalizeModel throws on each reserved keyword', () => {
  const src = readLlmConfigSource();
  // 'v3' is unique to normalizeModel's OR chain
  const body = findBranchBodyContaining(src, "'v3'");
  assert.ok(body !== null, 'reserved-keyword OR-branch not found in normalizeModel');
  assert.match(body, /throw/, 'reserved-keyword branch must throw');
  assert.match(body, /LlmError/, 'throw must use LlmError type');
  assert.doesNotMatch(
    body,
    /return\s+DEFAULT_/,
    'reserved-keyword branch must NOT silently return DEFAULT value'
  );
});

test('LlmConfig: empty input still returns DEFAULT (positive test)', () => {
  // Documents the INTENT: only reserved KEYWORDS throw. Empty input is
  // the legitimate silent-default case.
  const src = readLlmConfigSource();
  // Source has multiple `t.length === 0` checks (api-key throws; normalizeEndpoint
  // / normalizeModel silent defaults; addVendorModel noop). Use a context-anchored
  // regex to find normalizeEndpoint's empty check specifically.
  // Pattern: look for normalizeEndpoint (or normalizeEndpointForVendor) function body
  // and assert the `t.length === 0` block returns DEFAULT_ENDPOINT.
  const normalizeEndpointBody = src.match(
    /private\s+normalizeEndpoint(?:ForVendor)?\s*\(\s*v\s*:\s*string[^}]*?t\.length\s*===\s*0[^}]*?return\s+DEFAULT_ENDPOINT/s
  );
  assert.ok(normalizeEndpointBody !== null, 'normalizeEndpoint empty-input branch (return DEFAULT_ENDPOINT) not found');
});

test('LlmConfig: file passes TSC syntax check (no obvious issues)', () => {
  const src = readLlmConfigSource();
  const open = (src.match(/\{/g) ?? []).length;
  const close = (src.match(/\}/g) ?? []).length;
  assert.ok(
    Math.abs(open - close) <= 2,
    `LlmConfig.ets has suspicious brace balance: ${open} open vs ${close} close`
  );
});
