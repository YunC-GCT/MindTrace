import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

import { GalaxyBridge } from './bridge.ts';

class FakePort {
  onmessage = null;
  messages = [];
  started = false;

  postMessage(message) {
    this.messages.push(message);
  }

  start() {
    this.started = true;
  }
}

class FakeWindow {
  listener = null;
  parentMessages = [];
  parent = {
    postMessage: (message) => {
      this.parentMessages.push(message);
    },
  };

  addEventListener(_type, listener) {
    this.listener = listener;
  }

  attach(port) {
    this.listener?.({
      data: '__GALAXY_PORT__',
      ports: [port],
    });
  }
}

test('renderer messages emitted before WebMessagePort attachment are delivered after attach', () => {
  const fakeWindow = new FakeWindow();
  Object.assign(globalThis, { window: fakeWindow });

  const bridge = new GalaxyBridge();
  bridge.post('scene_ready', { particles: 8000, degraded: false });

  const port = new FakePort();
  fakeWindow.attach(port);

  assert.equal(port.started, true);
  assert.equal(port.messages.length, 1);
  assert.deepEqual(JSON.parse(port.messages[0]), {
    version: 1,
    type: 'scene_ready',
    payload: { particles: 8000, degraded: false },
  });
});

test('packaged rawfile does not depend on subresources rejected by ArkWeb', () => {
  const rawfileDir = resolve(
    import.meta.dirname,
    '../../../entry/src/main/resources/rawfile/galaxy3d',
  );
  const html = readFileSync(resolve(rawfileDir, 'index.html'), 'utf8');

  assert.doesNotMatch(html, /src=["']\.\/assets\//i);
  assert.doesNotMatch(html, /href=["']\.\/assets\//i);
  assert.equal(existsSync(resolve(rawfileDir, 'assets')), false);
});
