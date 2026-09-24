import { readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const outputDir = resolve(
  import.meta.dirname,
  '../../../entry/src/main/resources/rawfile/galaxy3d',
);
const assetsDir = resolve(outputDir, 'assets');
const assetNames = await readdir(assetsDir);
const scriptNames = assetNames.filter((name) => name.endsWith('.js'));
const styleNames = assetNames.filter((name) => name.endsWith('.css'));

if (scriptNames.length !== 1 || styleNames.length !== 1) {
  throw new Error(
    `Expected one JS and one CSS asset, found ${scriptNames.length} JS and ${styleNames.length} CSS`,
  );
}

const htmlPath = resolve(outputDir, 'index.html');
const scriptPath = resolve(assetsDir, scriptNames[0]);
const stylePath = resolve(assetsDir, styleNames[0]);
const [html, script, style] = await Promise.all([
  readFile(htmlPath, 'utf8'),
  readFile(scriptPath, 'utf8'),
  readFile(stylePath, 'utf8'),
]);

const scriptTag = `<script type="module" crossorigin src="./assets/${scriptNames[0]}"></script>`;
const styleTag = `<link rel="stylesheet" crossorigin href="./assets/${styleNames[0]}">`;
if (!html.includes(scriptTag) || !html.includes(styleTag)) {
  throw new Error('Vite index.html asset tags did not match the expected rawfile shape');
}

const inlineScript = script.replaceAll('</script', '<\\/script');
const inlineStyle = style.replaceAll('</style', '<\\/style');
const singleFileHtml = html
  .replace(scriptTag, () => `<script type="module">\n${inlineScript}\n</script>`)
  .replace(styleTag, () => `<style>\n${inlineStyle}\n</style>`);

await writeFile(htmlPath, singleFileHtml, 'utf8');
await rm(assetsDir, { recursive: true });
