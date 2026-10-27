import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

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

test('AgentInputViewModel keeps input and image when the session is busy', () => {
  const { AgentInputViewModel } = loadInputViewModel();
  const vm = new AgentInputViewModel();
  const serviceCalls = [];
  const service = {
    realReplyStream(...args) { serviceCalls.push(['text', ...args]); },
    captureReply(...args) { serviceCalls.push(['image', ...args]); },
  };
  // 现在没有 addUserMessage 回调：能否发送由 canSend()（busy + 内容）决定
  vm.bind(service, () => 'session-1');
  vm.updateText('  解释极限  ');
  vm.setImagePreview('file://limit.png');
  vm.setBusyForSession('session-1', true);

  vm.send();

  assert.deepEqual(serviceCalls, []);
  assert.equal(vm.inputText, '  解释极限  ');
  assert.equal(vm.imagePreview, 'file://limit.png');
});

test('AgentInputViewModel clears accepted text sends and forwards session id', () => {
  const { AgentInputViewModel } = loadInputViewModel();
  const vm = new AgentInputViewModel();
  const serviceCalls = [];
  const service = {
    realReplyStream(...args) { serviceCalls.push(['text', ...args]); },
    captureReply(...args) { serviceCalls.push(['image', ...args]); },
  };
  vm.bind(service, () => 'session-1');
  vm.updateText('  解释极限  ');

  vm.send();

  assert.deepEqual(serviceCalls, [['text', 'session-1', '解释极限']]);
  assert.equal(vm.inputText, '');
  assert.equal(vm.imagePreview, '');
});

test('AgentInputViewModel clears accepted image sends and forwards session id, uri, text', () => {
  const { AgentInputViewModel } = loadInputViewModel();
  const vm = new AgentInputViewModel();
  const serviceCalls = [];
  const service = {
    realReplyStream(...args) { serviceCalls.push(['text', ...args]); },
    captureReply(...args) { serviceCalls.push(['image', ...args]); },
  };
  vm.bind(service, () => 'session-1');
  vm.updateText('  图片里的极限题  ');
  vm.setImagePreview('file://limit.png');

  vm.send();

  assert.deepEqual(serviceCalls, [['image', 'session-1', 'file://limit.png', '图片里的极限题']]);
  assert.equal(vm.inputText, '');
  assert.equal(vm.imagePreview, '');
});

test('AgentFloatWindow uses monotonic feedback tokens and clears failed current tokens', () => {
  // 不能用裸相对路径：从 scripts/arkts-lint 目录跑测试时 cwd 不是仓库根
  const source = readFileSync(
    resolve(import.meta.dirname, '../../../entry/src/main/ets/overlays/AgentFloatWindow/AgentFloatWindow.ets'),
    'utf8',
  );

  assert.match(source, /feedbackRequestCounter \+= 1/);
  assert.match(source, /feedbackRequestTokenByMessage\.set\(messageId, this\.feedbackRequestCounter\)/);
  assert.match(source, /rollbackFeedbackIfCurrent\(messageId, feedback, previous, requestToken\);[\s\S]*?clearFeedbackRequestToken\(messageId, requestToken\);[\s\S]*?showToast\('反馈保存失败，请稍后重试'\)/);
  assert.match(source, /private isCurrentFeedbackRequest[\s\S]*?return current === requestToken/);
  // 停流现在只做三件事：停 VM、同步视图、把会话落库
  assert.match(source, /private stopStreaming = \(\): void => \{[\s\S]*?this\.inputVm\.stop\(\);[\s\S]*?this\.sync\(\);[\s\S]*?this\.sm\.flush\(this\.sessions\)/);
});
