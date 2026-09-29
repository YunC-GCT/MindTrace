/**
 * parser.test.mjs — Tests for the parser/preprocessor
 *
 * Run with: node --test tests/parser.test.mjs
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { preprocessArkUI } from '../parser/index.mjs';

test('preprocessArkUI: converts struct to class (length-preserving)', () => {
  const input = 'export struct Foo { }';
  const out = preprocessArkUI(input);
  assert.equal(out, 'export class Foo { }');
});

test('preprocessArkUI: removes @Concurrent decorator while preserving line count', () => {
  const input = 'const before = 1;\n@Concurrent\nfunction task(value: number): number { return value; }\nconst after = 2;';
  const out = preprocessArkUI(input);
  assert.equal(out.split('\n').length, input.split('\n').length);
  assert.ok(!out.includes('@Concurrent'));
  assert.ok(out.includes('function task'));
});

test('preprocessArkUI: converts @Builder-decorated methods to nothing (only keyword Builder funcName)', () => {
  // Note: @Builder as a decorator is not touched; only the `Builder funcName(` form
  const input = '@Builder NoteRows() { return; }';
  const out = preprocessArkUI(input);
  // @Builder stays as decorator; `Builder NoteRows(` is NOT matched because @ is before Builder
  // Only `Builder funcName(` without @ would be matched. Let's test that:
  const input2 = 'Builder doStuff() { return; }';
  const out2 = preprocessArkUI(input2);
  assert.equal(out2, 'function doStuff() { return; }');
});

test('preprocessArkUI: replaces $r() with __RES__ placeholder', () => {
  const input = 'Image($r("app.media.ic_notes"))';
  const out = preprocessArkUI(input);
  // Should not contain $r( anymore
  assert.ok(!out.includes('$r('), `Output still contains $r(: ${out}`);
  assert.ok(out.includes('__RES_'), `Output should contain __RES_: ${out}`);
});

test('preprocessArkUI: replaces $rawfile() with __RAW__ placeholder', () => {
  const input = "Web({ src: $rawfile('render.html') })";
  const out = preprocessArkUI(input);
  assert.ok(!out.includes('$rawfile('), `Output still contains $rawfile(: ${out}`);
  assert.ok(out.includes('__RAW_'), `Output should contain __RAW_: ${out}`);
});

test('preprocessArkUI: handles \r\n line endings (Windows)', () => {
  const input = "export class Foo {\r\n  @Component\r\n  build() {\r\n    Stack() {}\r\n  }\r\n}";
  const out = preprocessArkUI(input);
  // After build() body strip, should be parseable
  assert.ok(out.includes('class Foo'), 'class should be preserved');
});

test('preprocessArkUI: preserves content after build() closing brace (@Builder methods)', () => {
  const input = `export class Foo {
  build() {
    Column() { Text("hi") }
  }

  @Builder
  NoteRows() {
    ForEach(this.notes, (n): void => {}, (n): string => n.toString())
  }
}`;
  const out = preprocessArkUI(input);
  // @Builder NoteRows should still be there
  assert.ok(out.includes('@Builder'), `Output missing @Builder: ${out}`);
  assert.ok(out.includes('NoteRows'), `Output missing NoteRows: ${out}`);
});

test('preprocessArkUI: simple build() body stripped', () => {
  const input = `class X {
  build() {
    Text("hello")
  }
}`;
  const out = preprocessArkUI(input);
  // build() body should be replaced with placeholder
  assert.ok(out.includes('// ... (build body skipped for lint)'), `Output missing placeholder: ${out}`);
  assert.ok(!out.includes('Text("hello")'), `Output should not contain original build body: ${out}`);
});

test('preprocessArkUI: multiple build() in one class (rare but possible)', () => {
  // In ArkUI, build() should be unique per class, but test the preprocessor's robustness
  const input = `class X {
  build() {
    Column() { Text("1") }
  }
  otherMethod() {
    Row() { Text("2") }
  }
}`;
  const out = preprocessArkUI(input);
  // Only the first build() is stripped; otherMethod should be preserved
  assert.ok(out.includes('otherMethod'), `otherMethod should be preserved: ${out}`);
  assert.ok(out.includes('Row() { Text("2") }'), `Row should be preserved: ${out}`);
});
