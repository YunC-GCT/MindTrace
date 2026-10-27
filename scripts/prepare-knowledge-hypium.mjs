// Package existing HSP test sources into the instrument-test HAP, never production HSPs.
// Generated copies are disposable; agents/common src/test remain the only edited sources.
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const destination = resolve(root, 'entry/src/ohosTest/ets/generated-knowledge-tests');
let count = 0;
for (const module of ['agents', 'common']) {
  const source = resolve(root, module, 'src/test');
  function copyDirectory(relative = '') {
    for (const item of readdirSync(resolve(source, relative), { withFileTypes: true })) {
      const child = relative ? `${relative}/${item.name}` : item.name;
      if (item.isDirectory()) {
        copyDirectory(child);
      } else if (item.name.endsWith('.ets')) {
        const original = readFileSync(resolve(source, child), 'utf8');
        const rewritten = original.replace(/from (['"])\.\.\/main\/(.*?)\1/g,
          (_match, quote, path) => `from ${quote}${module}/src/main/${path}${quote}`);
        const target = resolve(destination, module, child);
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, `// Generated from ${module}/src/test/${child}; do not edit.\n${rewritten}`);
        count++;
      }
    }
  }
  copyDirectory();
}
console.log(`Prepared ${count} Hypium source files for entry ohosTest (not production).`);
