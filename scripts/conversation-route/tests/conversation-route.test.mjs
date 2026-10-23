import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '../../..');
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const portsPath = 'entry/src/main/ets/workflows/conversation/ConversationWorkflowPorts.ets';

test('IConversationReplyPort exposes completeRouted returning RoutedReply', () => {
  const source = read(portsPath);
  const interfaceStart = source.indexOf('export interface IConversationReplyPort');
  const interfaceEnd = source.indexOf('\n}', interfaceStart);
  assert.ok(interfaceStart >= 0 && interfaceEnd > interfaceStart);
  const interfaceBody = source.slice(interfaceStart, interfaceEnd);
  assert.match(
    interfaceBody,
    /completeRouted\(context: ReplyContext, token\?: CancellationToken\): Promise<RoutedReply>/,
  );
});

test('ConversationReplyAdapter.complete() delegates to completeRouted and marks degradation', () => {
  const source = read(portsPath);
  const completeStart = source.indexOf('async complete(');
  const completeEnd = source.indexOf('async stream(', completeStart);
  assert.ok(completeStart >= 0 && completeEnd > completeStart);
  const completeBody = source.slice(completeStart, completeEnd);
  assert.match(completeBody, /completeRouted\(context, token\)/);
  assert.match(completeBody, /已降级：/);
});

test('completeRouted routes through ModelRouter.answer and logs routing facts', () => {
  const source = read(portsPath);
  const routedStart = source.indexOf('async completeRouted(');
  const routedEnd = source.indexOf('async complete(', routedStart);
  assert.ok(routedStart >= 0 && routedEnd > routedStart);
  const routedBody = source.slice(routedStart, routedEnd);
  assert.match(routedBody, /router\.answer\(/);
  assert.match(routedBody, /source=/);
  assert.match(routedBody, /degraded=/);
  assert.match(routedBody, /reason=/);
  assert.match(routedBody, /chars=/);
});

test('stream() stays unrouted', () => {
  const source = read(portsPath);
  const streamStart = source.indexOf('async stream(');
  const streamEnd = source.indexOf('normalize(content: string)', streamStart);
  assert.ok(streamStart >= 0 && streamEnd > streamStart);
  const streamBody = source.slice(streamStart, streamEnd);
  assert.match(streamBody, /this\.reply\.stream\(context, sink, token\)/);
  assert.doesNotMatch(streamBody, /router\./);
});

test('production() wires one ReplyService into both ModelRouter and the reply adapter', () => {
  const source = read(portsPath);
  const productionStart = source.indexOf('static production(');
  assert.ok(productionStart >= 0);
  const productionBody = source.slice(productionStart);
  assert.match(productionBody, /new ModelRouter\(context\.filesDir, replyService\)/);
  assert.match(productionBody, /new ConversationReplyAdapter\(replyService, router\)/);
});
