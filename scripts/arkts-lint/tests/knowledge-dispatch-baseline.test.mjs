import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRuntime, generationRequest, draft, memoryStorage } from './knowledge-dispatch-runtime.mjs';

test('light preview keeps source fallback, transport budget and zero DAO writes', async () => {
  const runtime = createRuntime(() => draft(''));
  const storage = memoryStorage();
  const progress = [];
  const result = await runtime.dispatcher.dispatch(generationRequest(), {
    generationRepository: storage.repository, dao: storage.dao, progressSink: e => progress.push(e),
  });
  assert.equal(result.success, true, JSON.stringify(result));
  assert.equal(result.generation.status, 'ready-preview');
  assert.match(result.data.content, /函数在一点连续/);
  assert.equal(storage.writes.length, 0);
  assert.equal(runtime.requests[0].maxTokens, 1200);
  assert.equal(runtime.requests[0].timeoutMs, 300000);
  assert.equal(runtime.requests[0].enableThinking, false);
  assert.equal(progress[0].phase, 'prepare');
  assert.equal(progress[0].state, 'running');
  assert.equal(progress.at(-1).phase, 'compose');
  assert.equal(progress.at(-1).state, 'success');
});

test('preview confirmation persists before commit receipt and duplicate confirmation is idempotent', async () => {
  const runtime = createRuntime(() => draft());
  const storage = memoryStorage();
  const options = { generationRepository: storage.repository, dao: storage.dao };
  const preview = await runtime.dispatcher.dispatch(generationRequest(), options);
  const checkpoint = storage.checkpoints[0];
  const preparedCandidate = { runId: 'baseline-run', checkpointId: checkpoint.id,
    candidate: preview.data, candidateHash: checkpoint.candidateHash, commitKey: 'baseline-commit' };
  const request = { ...generationRequest(), generation: undefined, preparedCandidate };
  const saved = await runtime.dispatcher.dispatch(request, options);
  assert.equal(saved.success, true, JSON.stringify(saved));
  assert.equal(storage.writes.length, 1);
  assert.ok(storage.events.indexOf('insert') < storage.events.indexOf('commit'));
  assert.equal(storage.commits[0].candidateJson, JSON.stringify(saved.data));
  const duplicate = await runtime.dispatcher.dispatch(request, options);
  assert.equal(duplicate.success, true);
  assert.equal(duplicate.data.id, saved.data.id);
  assert.equal(storage.writes.length, 1);
  assert.equal(runtime.requests.length, 1);
});

test('TruthCheck rejects an authenticated but invalid checkpoint before any durable write', async () => {
  const runtime = createRuntime(() => draft());
  const storage = memoryStorage();
  const options = { generationRepository: storage.repository, dao: storage.dao };
  const preview = await runtime.dispatcher.dispatch(generationRequest(), options);
  const candidate = { ...preview.data, content: '' };
  const candidateHash = runtime.common.sourceFingerprint(JSON.stringify(candidate));
  storage.checkpoints[0] = { ...storage.checkpoints[0], candidateHash };
  const result = await runtime.dispatcher.dispatch({ ...generationRequest(), generation: undefined,
    preparedCandidate: { runId: 'baseline-run', checkpointId: storage.checkpoints[0].id,
      candidate, candidateHash, commitKey: 'bad-commit' } }, options);
  assert.equal(result.success, false);
  assert.match(result.errorMessage, /emptyInput/);
  assert.equal(storage.writes.length, 0);
  assert.equal(storage.commits.length, 0);
});

function standardResponse() {
  const value = draft();
  delete value.sections[0].sourceIds;
  return { outline: { schemaVersion: 'mm-note-outline-v1', sections: [
    { id: 'sec-1', label: '定义', order: 0, mustInclude: [] },
  ] }, draft: value };
}

test('standard recovers from incomplete verifier coverage without regenerating the draft', async () => {
  const runtime = createRuntime((_request, index) => index === 1 ? standardResponse() : {
    status: 'supported', issues: [], evidenceStatuses: index === 2 ? [] : ['supported'],
  });
  const result = await runtime.dispatcher.dispatch(generationRequest('standard'));
  assert.equal(result.success, true, JSON.stringify(result));
  assert.equal(result.generation.status, 'ready-preview');
  assert.equal(result.generation.verification.decisions.length, 1);
  assert.equal(result.generation.verification.decisions[0].evidenceId, result.generation.evidence[0].id);
  assert.equal(runtime.requests.length, 3);
  assert.equal(runtime.requests.filter(r => r.messages[0].content.includes('read-only independent note verifier')).length, 2);
});

test('deep dispatch retains multi-source attribution and bounded section transport', async () => {
  const runtime = createRuntime(request => {
    const prompt = request.messages[0].content;
    if (prompt.includes('read-only independent note verifier')) {
      return { status: 'supported', issues: [], evidenceStatuses: ['supported', 'supported'] };
    }
    const label = prompt.match(/section label=([^\n]+)/)[1];
    const value = draft(label.includes('公式') ? '公式：$\\pi$。' : '定义：\\(f(x)\\) 在一点连续。');
    value.sections[0].label = label;
    value.sections[0].sourceIds = [];
    return value;
  });
  const request = generationRequest('deep');
  request.generation.sources.fragments.push({ id: 'src-2', kind: 'conversation', originId: 'origin-2',
    sequence: 1, fingerprint: 'fp-2', text: '$$\n\\pi\n$$' });
  const storage = memoryStorage();
  const progress = [];
  const result = await runtime.dispatcher.dispatch(request, { generationRepository: storage.repository,
    dao: storage.dao, progressSink: e => progress.push(e) });
  assert.equal(result.success, true, JSON.stringify(result));
  assert.equal(result.generation.route, 'deep');
  const evidence = JSON.parse(storage.checkpoints[0].evidenceJson);
  assert.deepEqual(evidence.map(e => e.sourceRefs[0].sourceId), ['src-1', 'src-2']);
  assert.ok(evidence.every(e => e.origin === 'pipeline'));
  assert.equal(result.data.content.includes('\\('), false);
  assert.equal(storage.writes.length, 0);
  assert.deepEqual(runtime.requests.map(r => r.maxTokens), [4800, 4800, 2600]);
  assert.ok(runtime.requests.every(r => r.timeoutMs === 300000));
  assert.ok(progress.some(e => e.activity === 'write_section' && e.current === 2 && e.total === 2));
  assert.equal(progress.at(-1).phase, 'verify');
  assert.equal(progress.at(-1).state, 'success');
});

test('deep compatibility interface caps ledger values and keeps conclusions scoped and unique', async () => {
  const runtime = createRuntime(request => {
    if (request.messages[0].content.includes('read-only independent note verifier')) {
      return { status: 'supported', issues: [], evidenceStatuses: ['supported', 'supported'] };
    }
    return draft(request.messages[0].content.match(/section label=([^\n]+)/)[1] + '$x$。' + '说明'.repeat(120));
  });
  const request = generationRequest('deep').generation;
  request.sources.fragments[0].text = '因此' + '连续'.repeat(100);
  request.sources.fragments.push({ id: 'src-2', kind: 'conversation', originId: 'origin-2',
    sequence: 1, fingerprint: 'fp-2', text: '因此' + '成立'.repeat(100) });
  // Deliberately oversized synthetic values exercise the compatibility interface;
  // Dispatcher preflight can reject repetitive synthetic source text before drafting.
  const result = await runtime.model.structureDeepDraft(request);
  assert.equal(result.draft.sections.length, 2);
  assert.equal(result.ledger.formulas.length, 2);
  assert.equal(result.ledger.conclusions.length, 2);
  assert.equal(new Set(result.ledger.conclusions.map(e => e.key)).size, 2);
  assert.ok(result.ledger.formulas.every(e => e.value.length === 160));
  assert.ok(result.ledger.conclusions.every(e => e.value.length === 160));
  assert.deepEqual(Array.from(result.ledger.conclusions, e => e.sourceIds[0]), ['src-1', 'src-2']);
  assert.ok(result.ledger.terminology.every(e => e.value.length <= 24));
});

const classification = { category: '概念', subject: '数学分析', chapter: '连续性', confidence: 0.95,
  cleaned_text: '函数在一点连续。' };
const captureJson = { category: '概念', subject: '数学分析', chapter: '连续性', title: '连续函数',
  tags: ['连续'], difficulty: 1, importance: 3,
  fields: [{ key: 'definition', label: '定义', value: '函数在一点连续。' }] };

for (const analysisOnly of [true, false]) {
  test(`Capture ${analysisOnly ? 'analysis' : 'persist'} keeps classification and write contract`, async () => {
    const runtime = createRuntime((_request, index) => index === 1 ? classification : captureJson);
    const storage = memoryStorage();
    const result = await runtime.dispatcher.dispatch({ source: 'app',
      payload: { kind: 'text', text: '函数在一点连续。' } },
    { analysisOnly, includeRawText: true, dao: storage.dao });
    assert.equal(result.success, true, JSON.stringify(result));
    assert.equal(result.classification.type, '概念');
    assert.equal(result.recognizedText, '函数在一点连续。');
    assert.equal(storage.writes.length, analysisOnly ? 0 : 1);
    assert.equal(runtime.requests[0].maxTokens, 8000);
    assert.equal(runtime.requests[0].timeoutMs, 120000);
    if (analysisOnly) {
      assert.equal(result.data, undefined);
      assert.equal(runtime.requests.length, 1);
    } else {
      assert.equal(result.data.content, '## 定义\n函数在一点连续。\n\n## 原文\n函数在一点连续。');
      assert.equal(storage.writes[0], result.data);
      assert.equal(runtime.requests[1].maxTokens, 12000);
      assert.equal(runtime.requests[1].timeoutMs, 300000);
    }
  });
}

test('Capture surfaces DAO failure without returning a successful KnowledgeUnit', async () => {
  const runtime = createRuntime((_request, index) => index === 1 ? classification : captureJson);
  const result = await runtime.dispatcher.dispatch({ source: 'app', payload: { kind: 'text', text: '连续函数' } },
    { dao: { async insert() { throw new Error('disk unavailable'); } } });
  assert.equal(result.success, false);
  assert.match(result.errorMessage, /disk unavailable/);
  assert.equal(result.data, undefined);
});

test('Capture falls back from classifier LLM failure and still preserves write behavior', async () => {
  let runtime;
  runtime = createRuntime((_request, index) => {
    if (index === 1) throw new runtime.common.LlmError('classifier offline', 'NETWORK_ERROR');
    return captureJson;
  });
  const storage = memoryStorage();
  const result = await runtime.dispatcher.dispatch({ source: 'app',
    payload: { kind: 'text', text: '函数在一点连续。' } }, { dao: storage.dao });
  assert.equal(result.success, true, JSON.stringify(result));
  assert.equal(result.classification.type, '概念');
  assert.equal(result.classification.confidence, 0.45);
  assert.equal(result.classification.ocrTextQuality, 'fallback');
  assert.equal(storage.writes.length, 1);
  assert.equal(runtime.requests[0].maxTokens, 8000);
  assert.equal(runtime.requests[1].maxTokens, 12000);
});

test('Capture returns structure errors with classification context and zero writes', async () => {
  const runtime = createRuntime((_request, index) => index === 1 ? classification : 'not json');
  const storage = memoryStorage();
  const result = await runtime.dispatcher.dispatch({ source: 'app',
    payload: { kind: 'text', text: '函数在一点连续。' } }, { dao: storage.dao });
  assert.equal(result.success, false);
  assert.match(result.errorMessage, /AI 结构化失败/);
  assert.match(result.errorMessage, /JSON object extraction failed/);
  assert.equal(result.classification.type, '概念');
  assert.equal(result.classification.ocrTextQuality, 'refined');
  assert.equal(result.data, undefined);
  assert.equal(storage.writes.length, 0);
  assert.equal(runtime.requests.length, 4); // one classifier call + bounded three structure guard attempts
});

test('cancellation at dispatch entry prevents LLM and storage side effects', async () => {
  const runtime = createRuntime();
  const token = new runtime.common.CancellationToken();
  token.cancel();
  const storage = memoryStorage();
  await assert.rejects(runtime.dispatcher.dispatch(generationRequest(), {
    cancellationToken: token, dao: storage.dao, generationRepository: storage.repository,
  }), /CONVERSATION_CANCELLED/);
  assert.equal(runtime.requests.length, 0);
  assert.equal(storage.events.length, 0);
});

test('mid-flight cancellation propagates token and prevents preview/DAO commit', async () => {
  let token;
  const runtime = createRuntime(request => {
    assert.equal(request.cancellationToken, token);
    token.cancel();
    return draft();
  });
  token = new runtime.common.CancellationToken();
  const storage = memoryStorage();
  const result = await runtime.dispatcher.dispatch(generationRequest(), {
    cancellationToken: token, dao: storage.dao, generationRepository: storage.repository,
  });
  assert.equal(result.success, false);
  assert.match(result.errorMessage, /CONVERSATION_CANCELLED/);
  assert.equal(result.generation.issues[0].code, 'NODE_ERROR');
  assert.equal(storage.writes.length, 0);
  assert.equal(storage.checkpoints.length, 0);
});

for (const [kind, retriable] of [
  ['NETWORK_ERROR', true], ['TIMEOUT', true], ['STREAM_FAILED', true], ['API_ERROR', false],
]) {
  test(`generation preserves ${kind} classification and retriable=${retriable}`, async () => {
    let runtime;
    runtime = createRuntime(() => { throw new runtime.common.LlmError('provider unavailable', kind); });
    // Compatibility Seam: DispatchResult intentionally does not expose retriable.
    await assert.rejects(runtime.model.structureLightDraft(generationRequest().generation), error => {
      assert.equal(error.kind, 'LLM_TRANSPORT');
      assert.equal(error.retriable, retriable);
      assert.equal(error.cause.kind, kind);
      return true;
    });
    assert.equal(runtime.requests.length, 1); // transport failure is not guard-retried
    const result = await runtime.dispatcher.dispatch(generationRequest());
    assert.equal(result.success, false);
    assert.equal(result.generation.issues[0].code, 'STRUCTURE_ERROR');
    assert.match(result.errorMessage, /provider unavailable/);
    assert.equal(runtime.requests.length, 2);
  });
}

for (const [response, kind, attempts] of [
  ['not json', 'JSON_EXTRACTION_ERROR', 3],
  ['{}', 'JSON_SCHEMA_ERROR', 3],
]) {
  test(`generation preserves ${kind} and bounded guard retry`, async () => {
    const runtime = createRuntime(() => response);
    await assert.rejects(runtime.model.structureLightDraft(generationRequest().generation), error => {
      assert.equal(error.kind, kind);
      assert.equal(error.retriable, false);
      return true;
    });
    assert.equal(runtime.requests.length, attempts);
  });
}

test('truncation is non-retriable and never becomes a partial preview', async () => {
  let runtime;
  runtime = createRuntime(() => JSON.stringify(draft()) + runtime.common.TRUNCATION_MARKER);
  await assert.rejects(runtime.model.structureLightDraft(generationRequest().generation), error => {
    assert.equal(error.kind, 'LLM_TRUNCATED');
    assert.equal(error.retriable, false);
    return true;
  });
  assert.equal(runtime.requests.length, 1);
  const result = await runtime.dispatcher.dispatch(generationRequest());
  assert.equal(result.success, false);
  assert.equal(result.data, undefined);
  assert.match(result.errorMessage, /truncated/);
});

for (const attackLocked of [false, true]) {
  test(`incremental ${attackLocked ? 'rejects a patch to' : 'preserves'} user-locked sections`, async () => {
    let targetId, lockedId;
    const runtime = createRuntime(() => ({ patches: [{ sectionId: attackLocked ? lockedId : targetId,
      operation: 'replace', content: '新增例子', sourceIds: ['src-1'] }] }));
    const storage = memoryStorage();
    const sections = runtime.common.parseIncrementalSections('## 定义\n原定义\n## 例子\n旧例子');
    lockedId = sections[0].id;
    targetId = sections[1].id;
    const unit = { id: 'note-104', title: '连续函数', content: '## 定义\n用户改过的定义\n## 例子\n旧例子',
      summary: '连续函数', tags: ['连续'], subject: '数学分析', category: '概念', chapter: '连续性',
      difficulty: 1, source: 'note_generation', createdAt: 10, updatedAt: 20, reviewStatus: 'review',
      nextReviewAt: 30, intervalDays: 5, easeFactor: 2.5, repetitions: 3,
      prerequisites: ['pre-1'], related: ['related-1'], embedding: [0.1], userId: 'u1', version: 2 };
    storage.repository.getRegenerationBase = async () => ({ unit, baseVersion: 2,
      manifest: runtime.common.buildIncrementalManifest(unit.id, 2, sections, ['old-source']),
      sources: { fragments: [{ id: 'old-source', kind: 'conversation', originId: 'old', sequence: 0,
        fingerprint: 'old', text: '旧例子' }] } });
    const request = generationRequest('standard');
    Object.assign(request.generation, { mode: 'regenerate', targetNoteId: unit.id, baseVersion: 2,
      instruction: '增加一个例子' });
    const options = { generationRepository: storage.repository, dao: storage.dao };
    if (attackLocked) {
      // Existing incremental dispatch propagates the domain error instead of wrapping it.
      await assert.rejects(runtime.dispatcher.dispatch(request, options), error => {
        assert.equal(error.kind, 'DOMAIN_VALIDATION_ERROR');
        assert.equal(error.retriable, false);
        return true;
      });
      assert.equal(storage.checkpoints.length, 0);
    } else {
      const result = await runtime.dispatcher.dispatch(request, options);
      assert.equal(result.success, true, JSON.stringify(result));
      assert.equal(result.generation.status, 'ready-preview');
      assert.match(result.data.content, /用户改过的定义/);
      assert.match(result.data.content, /新增例子/);
      assert.equal(result.data.id, unit.id);
      assert.equal(result.data.version, 2);
      assert.equal(result.data.nextReviewAt, 30);
      assert.equal(result.data.easeFactor, 2.5);
      assert.equal(result.generation.incrementalDiff.find(d => d.sectionId === lockedId).kind, 'locked');
      const updated = runtime.common.parseIncrementalSections(result.data.content);
      assert.equal(updated[0].content, '用户改过的定义');
      assert.equal(storage.checkpoints.length, 1);
    }
    assert.equal(storage.writes.length, 0);
    assert.ok(runtime.requests.every(r => r.maxTokens === 2400 && r.timeoutMs === 300000));
  });
}

for (const complete of [true, false]) {
  test(`standard pipeline attribution and ${complete ? 'complete' : 'incomplete'} verifier are preserved`, async () => {
    const runtime = createRuntime((_request, index) => index === 1 ? standardResponse() : {
      status: 'supported', issues: [], evidenceStatuses: complete ? ['supported'] : [],
    });
    const storage = memoryStorage();
    const result = await runtime.dispatcher.dispatch(generationRequest('standard'), {
      generationRepository: storage.repository, dao: storage.dao,
    });
    assert.equal(result.generation.status, complete ? 'ready-preview' : 'needs-input', JSON.stringify(result));
    const checkpoint = storage.checkpoints[0];
    const evidence = JSON.parse(checkpoint.evidenceJson);
    const verification = JSON.parse(checkpoint.verificationJson);
    assert.equal(evidence[0].origin, 'pipeline');
    assert.equal(evidence[0].sourceRefs[0].sourceId, 'src-1');
    assert.equal(JSON.parse(checkpoint.outlineJson).sections[0].sourceIds[0], 'src-1');
    assert.equal(storage.writes.length, 0);
    assert.equal(runtime.requests[0].maxTokens, 6000);
    assert.ok(runtime.requests.slice(1).every(r => r.maxTokens === 2600));
    assert.ok(runtime.requests.every(r => r.timeoutMs === 300000 && r.enableThinking === false));
    if (complete) {
      assert.equal(verification.decisions[0].evidenceId, evidence[0].id);
    } else {
      assert.ok(result.generation.issues.some(issue => issue.code === 'VERIFIER_UNAVAILABLE'));
      assert.equal(runtime.requests.length, 4); // one draft + bounded three verifier attempts
    }
  });
}
