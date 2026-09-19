import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const repoRoot = process.cwd();
const llmClientPath = join(repoRoot, 'common', 'src', 'main', 'ets', 'llm', 'LlmClient.ets');
const providersPath = join(repoRoot, 'common', 'src', 'main', 'ets', 'llm', 'providers.ets');
const knowledgeModelPath = join(repoRoot, 'agents', 'src', 'main', 'ets', 'agents', 'KnowledgeModel.ets');

function readLlmClient() {
  return readFileSync(llmClientPath, 'utf8');
}

function readProviders() {
  return readFileSync(providersPath, 'utf8');
}

function readKnowledgeModel() {
  return readFileSync(knowledgeModelPath, 'utf8');
}

test('LlmClient non-200 path must not stringify response.result directly', () => {
  const source = readLlmClient();
  assert.equal(
    source.includes('response.result as string'),
    false,
    'LlmClient must not use `(response.result as string)` in the HTTP error path; use LlmErrorBodyFormatter instead.',
  );
  assert.equal(
    /\bString\s*\(\s*response\.result\s*\)/.test(source),
    false,
    'LlmClient must not use `String(response.result)` because ArrayBuffer becomes [object ArrayBuffer].',
  );
});

test('LlmClient API_ERROR path must use LlmErrorBodyFormatter', () => {
  const source = readLlmClient();
  assert.match(
    source,
    /import\s+\{\s*LlmErrorBodyFormatter[\s\S]*\}\s+from\s+'\.\/LlmErrorBodyFormatter'/,
    'LlmClient must import LlmErrorBodyFormatter from ./LlmErrorBodyFormatter.',
  );
  assert.match(
    source,
    /LlmErrorBodyFormatter\.format\(/,
    'LlmClient non-stream HTTP error branch must call LlmErrorBodyFormatter.format().',
  );
  assert.match(
    source,
    /throw\s+new\s+LlmError\([^\n]+API_ERROR/s,
    'LlmClient must preserve API_ERROR failure semantics for non-200 responses.',
  );
});

test('LlmClient non-stream request declares string response expectation', () => {
  const source = readLlmClient();
  assert.match(
    source,
    /expectDataType\s*:\s*http\.HttpDataType\.STRING/,
    'LlmClient non-stream request should request string responses while retaining formatter defensive decoding.',
  );
});

test('LlmClient error messages must not include sensitive endpoint or headers', () => {
  const source = readLlmClient();
  assert.equal(
    source.includes('endpoint=') && source.includes('stream=false'),
    false,
    'LlmClient logs must not include the full endpoint in non-stream request diagnostics.',
  );
  assert.equal(
    /Authorization[^\n]+LLM API error/.test(source),
    false,
    'LlmClient must not concatenate Authorization header data into API error messages.',
  );
  assert.equal(
    /LlmErrorBodyFormatter\.format\([\s\S]{0,240}endpointUrl/.test(source),
    false,
    'LlmClient must not pass the full endpoint URL into user-visible error formatter context.',
  );
  assert.equal(
    /LlmErrorBodyFormatter\.format\([\s\S]{0,240}apiKey/.test(source),
    false,
    'LlmClient must not pass API key or sensitive request headers into user-visible error formatter context.',
  );
});

test('DeepSeek provider must not declare strict schema response format support', () => {
  const source = readProviders();
  const match = source.match(/id\s*:\s*'deepseek'[\s\S]*?strictStructuredOutput\s*:\s*(true|false)/);
  assert.notEqual(
    match,
    null,
    'DeepSeek provider preset must declare strictStructuredOutput explicitly.',
  );
  assert.equal(
    match?.[1],
    'false',
    'DeepSeek currently rejects strict schema response_format; provider preset must keep strictStructuredOutput: false.',
  );
  assert.doesNotMatch(
    match?.[0] ?? '',
    /strictStructuredOutput\s*:\s*true/,
    'DeepSeek provider preset must not regress to strictStructuredOutput: true without explicit compatibility evidence.',
  );
});

test('KnowledgeModel keeps provider-driven JSON object fallback for structured output', () => {
  const source = readKnowledgeModel();
  assert.match(
    source,
    /supportsStrictStructuredOutput\(\)/,
    'KnowledgeModel must consume provider capabilities through LlmConfig.supportsStrictStructuredOutput().',
  );
  assert.match(
    source,
    /return\s+\{\s*type\s*:\s*'json_object'\s*\}/,
    'KnowledgeModel must keep the compatible json_object fallback when strict schema response_format is unavailable.',
  );
  assert.doesNotMatch(
    source,
    /deepseek/i,
    'KnowledgeModel must not hard-code a DeepSeek branch; provider capability belongs in common llm providers.',
  );
});
