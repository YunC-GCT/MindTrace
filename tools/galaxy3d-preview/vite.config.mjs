import { resolve } from 'node:path';
import { defineConfig } from 'vite';

export default defineConfig({
  base: './',
  build: {
    outDir: resolve(import.meta.dirname, '../../entry/src/main/resources/rawfile/galaxy3d'),
    emptyOutDir: true,
    assetsDir: 'assets',
  },
});
