import assert from 'node:assert/strict';
import test from 'node:test';
import { BackgroundStarfield } from './background-starfield.ts';

function randomSource() {
  let seed = 117;
  return () => {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
    return seed / 4294967296;
  };
}

test('a star fades smoothly at display frame rate even with a one-second lifecycle', () => {
  const stars = new BackgroundStarfield(1, () => 0);
  let previous = stars.opacities[0];
  let darkSamples = 0;
  let brightSamples = 0;
  for (let frame = 0; frame < 1200; frame += 1) {
    stars.advance(1 / 120);
    const opacity = stars.opacities[0];
    assert.ok(opacity >= 0 && opacity <= 1);
    assert.ok(Math.abs(opacity - previous) < 0.04, 'no abrupt brightness jump between frames');
    if (opacity === 0) darkSamples += 1;
    if (opacity > 0.4) brightSamples += 1;
    previous = opacity;
  }
  assert.ok(darkSamples > 40, 'star has a real hidden interval');
  assert.ok(brightSamples > 100, 'star stays visible rather than flashing briefly');
});

test('complete fade-hold-fade-hidden cycles span the requested 1–10 seconds', () => {
  for (const [randomValue, expectedSeconds] of [[0, 1], [0.5, 5.5], [0.999, 9.991]]) {
    const stars = new BackgroundStarfield(1, () => randomValue);
    const starts = [];
    let previous = stars.opacities[0];
    for (let frame = 1; frame <= 4200; frame += 1) {
      stars.advance(1 / 120);
      const opacity = stars.opacities[0];
      if (previous === 0 && opacity > 0) starts.push(frame / 120);
      previous = opacity;
    }
    assert.ok(starts.length >= 3);
    for (let index = 1; index < starts.length; index += 1) {
      assert.ok(Math.abs(starts[index] - starts[index - 1] - expectedSeconds) < 0.02,
        `expected complete period ${expectedSeconds}s`);
    }
  }
});

test('drift is exactly twice the previous midpoint speed', () => {
  const stars = new BackgroundStarfield(1, () => 0.5);
  const before = stars.positions.slice();
  stars.advance(0.1);
  assert.ok(Math.abs(stars.positions[0] - before[0] - 0.11) < 0.00002);
  assert.ok(Math.abs(stars.positions[1] - before[1] - 0.05) < 0.00002);
  assert.equal(stars.positions[2], before[2]);
});

test('pause freezes life and positions; resuming advances only foreground time', () => {
  const stars = new BackgroundStarfield(64, randomSource());
  const positions = stars.positions.slice();
  const opacities = stars.opacities.slice();
  stars.advance(300, true);
  assert.deepEqual(stars.positions, positions);
  assert.deepEqual(stars.opacities, opacities);
  stars.advance(0.1, false);
  assert.notDeepEqual(stars.opacities, opacities);
});

test('visible stars drift slowly without camera gestures', () => {
  const stars = new BackgroundStarfield(64, randomSource());
  const positions = stars.positions.slice();
  const opacities = stars.opacities.slice();
  stars.advance(0.1);
  let drifting = 0;
  for (let index = 0; index < 64; index += 1) {
    if (opacities[index] < 0.1 || stars.opacities[index] < 0.1) continue;
    const offset = index * 3;
    const distance = Math.hypot(...[0, 1, 2].map(axis => stars.positions[offset + axis] - positions[offset + axis]));
    assert.ok(distance > 0.01 && distance < 0.2, `slow visible drift, got ${distance}`);
    drifting += 1;
  }
  assert.ok(drifting > 30);
});

test('stars only teleport while invisible; visible movement stays continuous', () => {
  const stars = new BackgroundStarfield(64, randomSource());
  let moved = 0;
  for (let frame = 0; frame < 900; frame += 1) {
    const previous = stars.positions.slice();
    stars.advance(0.1);
    for (let index = 0; index < 64; index += 1) {
      const offset = index * 3;
      const distance = Math.hypot(...[0, 1, 2].map(axis => stars.positions[offset + axis] - previous[offset + axis]));
      if (distance > 1) {
        moved += 1;
        assert.equal(stars.opacities[index], 0, 'rebirth must not teleport a visible star');
      }
    }
  }
  assert.ok(moved >= 64, 'all stars get a new life within 90 seconds');
});

test('reduced motion stops drift, not the slow fade lifecycle', () => {
  const stars = new BackgroundStarfield(64, randomSource());
  const positions = stars.positions.slice();
  const opacities = stars.opacities.slice();
  stars.advance(0.1, false, 0);
  for (let index = 0; index < 64; index += 1) {
    // A completed lifecycle may relocate an invisible star, but not a visible one.
    if (stars.opacities[index] === 0) continue;
    assert.deepEqual(stars.positions.slice(index * 3, index * 3 + 3),
      positions.slice(index * 3, index * 3 + 3));
  }
  assert.notDeepEqual(stars.opacities, opacities);
});

test('a bounded pool starts staggered and maintains a quiet, steady density', () => {
  const stars = new BackgroundStarfield(4000, randomSource());
  for (let second = 0; second < 180; second += 1) {
    const visible = stars.opacities.filter(value => value > 0.05).length;
    assert.ok(visible > 2200 && visible < 3600, `no all-on/all-off waves: ${visible}`);
    // Match the renderer's maximum 50ms step: a 1s step skips an entire short life.
    for (let frame = 0; frame < 20; frame += 1) stars.advance(0.05);
  }
});
