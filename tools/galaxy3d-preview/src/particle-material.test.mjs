import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createStarMaterial, createGlowMaterial, createKnowledgeMaterial } from './particle-material.ts';

test('Web uses one lifecycle starfield and no duplicate DOM stars or spheres', () => {
  const main = readFileSync(new URL('./main.ts', import.meta.url), 'utf8');
  const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
  assert.match(main, /const particleMaterial = createStarMaterial\(\)/);
  assert.match(main, /view\.orb\.style\.opacity = '0'/);
  assert.doesNotMatch(main, /renderer\.domElement\.style\.opacity = '0'/);
  assert.match(main, /if \(degraded\) \{[\s\S]*?renderer\.render\(scene, camera\)/);
  assert.match(main, /HIGH_PARTICLE_BUDGET = 4000/);
  assert.doesNotMatch(html, /id="star-layer"/);
  assert.doesNotMatch(main, /createDomStarfield/);
  assert.match(main, /new BackgroundStarfield\(HIGH_PARTICLE_BUDGET\)/);
  assert.match(main, /new THREE\.BufferAttribute\(backgroundStars\.opacities, 1\)/);
  assert.doesNotMatch(main, /vertexColors: true/);
});

test('knowledge spheres keep physical lighting, depth and category color without clay texture', () => {
  const material = createKnowledgeMaterial(0x5be3b0);
  assert.equal(material.isMeshPhysicalMaterial, true);
  assert.equal(material.fog, false);
  assert.equal(material.transparent, false);
  assert.equal(material.color.getHex(), 0x5be3b0);
  assert.equal(material.map, null);
  assert.equal(material.normalMap, null);
  assert.equal(material.depthWrite, true);
  const shader = { vertexShader: '#include <common>\n#include <begin_vertex>',
    fragmentShader: '#include <common>\n#include <color_fragment>' };
  material.onBeforeCompile(shader, null);
  assert.doesNotMatch(shader.fragmentShader, /planetSurface/);
  assert.doesNotMatch(shader.fragmentShader, /uniform float time/);
  material.dispose();
});

test('stars use white color and an analytic circular mask without canvas textures', () => {
  const material = createStarMaterial();
  assert.equal(material.color.getHex(), 0xffffff);
  assert.equal(material.vertexColors, false);
  assert.equal(material.map, null);
  assert.ok(material.opacity >= 0.6 && material.opacity <= 0.7);
  assert.ok(material.size >= 2);
  assert.equal(material.sizeAttenuation, false);
  const shader = { vertexShader: '#include <common>\n#include <begin_vertex>',
    fragmentShader: '#include <common>\n#include <color_fragment>' };
  material.onBeforeCompile(shader, null);
  assert.match(shader.fragmentShader, /gl_PointCoord/);
  assert.match(shader.fragmentShader, /discard/);
  assert.match(shader.fragmentShader, /smoothstep/);
  assert.match(shader.vertexShader, /vStarOpacity = starOpacity/);
  assert.match(shader.fragmentShader, /diffuseColor\.a \*= vStarOpacity/);
  material.dispose();
});

test('selection illuminates the sphere without scaling or using an old DOM radius for edges', () => {
  const main = readFileSync(new URL('./main.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(main, /1\.42|selectedScale|9 \* perspectiveScale/);
  assert.match(main, /view\.core\.scale\.setScalar\(base\)/);
  assert.match(main, /surface\.emissiveIntensity = THREE\.MathUtils\.lerp/);
  assert.match(main, /camera\.projectionMatrix\.elements\[5\]/);
});

test('glow fades towards the silhouette instead of drawing a constant-opacity shell', () => {
  const material = createGlowMaterial(0x5be3b0);
  assert.equal(material.depthWrite, false);
  assert.match(material.fragmentShader, /pow\(facing, 3\.0\)/);
  assert.ok(material.uniforms.strength.value <= 0.04);
  material.dispose();
});

test('background updates after the host pause guard and respects reduced motion', () => {
  const main = readFileSync(new URL('./main.ts', import.meta.url), 'utf8');
  const css = readFileSync(new URL('./styles.css', import.meta.url), 'utf8');
  assert.doesNotMatch(main, /particlePoints\.rotation/);
  assert.doesNotMatch(css, /star-drift/);
  assert.doesNotMatch(css, /galaxy-star-plane|star-breathe/);
  assert.match(main, /if \(pausedByHost \|\| document\.hidden[^\n]+return;\s+updateBackground\(delta\)/);
  assert.match(main, /backgroundStars\.advance\(delta, false, reducedMotion\.matches \? 0 : 1\)/);
  assert.match(main, /antialias: true/);
});
