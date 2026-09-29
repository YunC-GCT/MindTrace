import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { loadNoteReviewEtsModule } from './note-review-ets-loader.mjs';

function loadInputViewModel() {
  return loadNoteReviewEtsModule('entry/src/main/ets/viewmodels/AgentInputViewModel.ets', {
    globals: {
      Observed(target) { return target; },
    },
    mocks: {
      common: {},
      'entry/src/main/ets/services/AgentChatService.ets': {
        AgentChatService: class AgentChatService {},
      },
    },
  });
}

test('AgentInputViewModel keeps input and image when addUserMessage rejects send', () => {
  const { AgentInputViewModel } = loadInputViewModel();
  const vm = new AgentInputViewModel();
  const serviceCalls = [];
  const service = {
    realReplyStream(...args) { serviceCalls.push(['text', ...args]); },
    captureReply(...args) { serviceCalls.push(['image', ...args]); },
  };
  const displays = [];
  vm.bind(service, (content) => {
    displays.push(content);
    return false;
  });
  vm.updateText('  解释极限  ');
  vm.setImagePreview('file://limit.png');
  vm.setRoute('standard');

  vm.send();

  assert.deepEqual(displays, ['解释极限']);
  assert.deepEqual(serviceCalls, []);
  assert.equal(vm.inputText, '  解释极限  ');
  assert.equal(vm.imagePreview, 'file://limit.png');
});

test('AgentInputViewModel clears accepted text sends and forwards route', () => {
  const { AgentInputViewModel } = loadInputViewModel();
  const vm = new AgentInputViewModel();
  const serviceCalls = [];
  const service = {
    realReplyStream(...args) { serviceCalls.push(['text', ...args]); },
    captureReply(...args) { serviceCalls.push(['image', ...args]); },
  };
  vm.bind(service, () => true);
  vm.updateText('  解释极限  ');
  vm.setRoute('light');

  vm.send();

  assert.deepEqual(serviceCalls, [['text', '解释极限', 'light']]);
  assert.equal(vm.inputText, '');
  assert.equal(vm.imagePreview, '');
});

test('AgentInputViewModel clears accepted image sends and forwards text and route', () => {
  const { AgentInputViewModel } = loadInputViewModel();
  const vm = new AgentInputViewModel();
  const serviceCalls = [];
  const service = {
    realReplyStream(...args) { serviceCalls.push(['text', ...args]); },
    captureReply(...args) { serviceCalls.push(['image', ...args]); },
  };
  vm.bind(service, () => true);
  vm.updateText('  图片里的极限题  ');
  vm.setImagePreview('file://limit.png');
  vm.setRoute('standard');

  vm.send();

  assert.deepEqual(serviceCalls, [['image', 'file://limit.png', '图片里的极限题', 'standard']]);
  assert.equal(vm.inputText, '');
  assert.equal(vm.imagePreview, '');
});

test('AgentFloatWindow uses monotonic feedback tokens and clears failed current tokens', () => {
  const source = readFileSync('entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets', 'utf8');

  assert.match(source, /feedbackRequestCounter \+= 1/);
  assert.match(source, /feedbackRequestTokenByMessage\.set\(messageId, this\.feedbackRequestCounter\)/);
  assert.match(source, /rollbackFeedbackIfCurrent\(messageId, feedback, previous, requestToken\);[\s\S]*?clearFeedbackRequestToken\(messageId, requestToken\);[\s\S]*?showToast\('反馈保存失败，请稍后重试'\)/);
  assert.match(source, /private isCurrentFeedbackRequest[\s\S]*?return current === requestToken/);
  assert.match(source, /private stopStreaming = \(\): void => \{[\s\S]*?this\.inputVm\.stop\(\);[\s\S]*?if \(this\.serviceRunActive\) \{[\s\S]*?this\.inputVm\.setBusy\(true\);[\s\S]*?this\.finishCurrentStreamingMessage\(\);/);
});
