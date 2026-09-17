/**
 * parser/index.mjs — Parse a single .ets file via @typescript-eslint/parser
 *
 * Returns:
 *   {
 *     ast:        ESTree-compatible AST node tree,
 *     sourceCode: original source text,
 *     locator:    SourceLocator instance for node → {line, col} conversion,
 *     programNode: the TSESTree Program node (root),
 *   }
 *
 * Notes:
 *   - We use the TS parser (not the JS parser) because ArkTS is TS-superset.
 *   - Decorators like `@Component`, `@State` are emitted as TSDecorator nodes.
 *   - `locRange: true` gives us start/end offsets for source location.
 *   - ArkUI-specific syntax (`struct`, `Builder` keyword, build() body, etc.)
 *     is preprocessed to TS-compatible syntax before parsing. Source location
 *     stays correct (same line counts) for the locator.
 */

import { parse } from '@typescript-eslint/parser';
import { readFileSync } from 'node:fs';

const PARSE_OPTIONS = {
  ecmaVersion: 'latest',
  sourceType: 'module',
  // Decorators (ArkUI uses @Component, @State, @Observed, etc.)
  ecmaFeatures: { decorators: true },
  // ArkUI build() method bodies use JSX-like syntax:
  //   `Stack() { if (x) { Image(...) } }` — function call with brace-block children.
  // JSX mode makes the parser accept this. (Real JSX (`<Component />`) is NOT used
  // in ArkTS — we only need JSX's "call with block" grammar.)
  jsx: true,
  // Get range + loc on every node
  range: true,
  loc: true,
  // Tolerate ArkTS syntax we don't fully understand yet (forward-compat)
  errorOnUnknownASTType: false,
  // Don't throw on type annotations we can't resolve
  loggerFn: false,
  // Recover from errors: try to keep parsing even after syntax error
  errorRecovery: true,
};

/**
 * Preprocess ArkUI-specific syntax to TypeScript-compatible syntax.
 *
 *   `struct X`             → `class X`
 *   `Builder name(...)`    → `function name(...)`
 *   `$r('app.media.x')`    → `__RES_app_media_x__` placeholder
 *   `$rawfile('x.html')`   → `__RAW_x__` placeholder
 *   `build() { ... }` body → `// ... (build body skipped for lint)`
 *
 * The preprocessor preserves line counts so the locator works correctly.
 * Column positions may shift slightly, but we map back to the ORIGINAL
 * source for snippet extraction.
 *
 * @param {string} source original .ets source
 * @returns {string} TS-compatible source
 */
export function preprocessArkUI(source) {
  let result = source.replace(/\bstruct\b/g, 'class');
  result = result.replace(/(?<![@])\bBuilder\s+([A-Za-z_$][\w$]*)\s*\(/g, 'function $1(');
  result = result.replace(/^(\s*)@Concurrent[ \t]*$/gm, (match, indent) => {
    return indent + ' '.repeat(match.length - indent.length);
  });

  // $r('...') → placeholder identifier (preserves column by padding)
  result = result.replace(/\$\s*r\s*\(\s*['"]([^'"]+)['"]\s*\)/g, (m, p1) => {
    const placeholder = `__RES_${p1.replace(/[^A-Za-z0-9_]/g, '_')}__`;
    return placeholder + ' '.repeat(Math.max(0, m.length - placeholder.length));
  });

  // $rawfile('...') → placeholder
  result = result.replace(/\$\s*rawfile\s*\(\s*['"]([^'"]+)['"]\s*\)/g, (m, p1) => {
    const placeholder = `__RAW_${p1.replace(/[^A-Za-z0-9_]/g, '_').replace(/\.html$/, '')}__`;
    return placeholder + ' '.repeat(Math.max(0, m.length - placeholder.length));
  });

  // build() { ... } body → empty
  result = stripBuildBodies(result);

  return result;
}

/**
 * Find each `build() {` and replace its body (up to matching `}`) with a comment.
 * Uses a line-by-line brace counter, character-by-character within each line,
 * so the line that closes the brace is preserved (and any content after `}` on
 * that line is re-emitted as a separate line so following @Builder methods or
 * other declarations are not lost).
 */
function stripBuildBodies(source) {
  // Use /\r?\n/ to handle Windows line endings (otherwise regex `$` doesn't match
  // before `\r`).
  const lines = source.split(/\r?\n/);
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    // Match: optional access modifier, "build", "()", "{"
    // Use [ \t]*$ to allow trailing whitespace.
    const m = line.match(/^(\s*(?:public\s+|private\s+|protected\s+)?build\s*\(\s*\)\s*\{)[ \t]*(.*)$/);
    if (!m) {
      out.push(line);
      i++;
      continue;
    }
    const head = m[1];   // "  build() {"
    const tail = m[2];   // anything after the opening "{" on the same line
    let depth = 1;        // we're inside the `{` we just matched
    for (const ch of tail) {
      if (ch === '{') depth++;
      else if (ch === '}') depth--;
    }
    if (depth === 0) {
      // Single-line body — just emit "build() {}"
      out.push(head + '}');
      i++;
      continue;
    }
    // Multi-line body — emit opening line + placeholder, then skip body lines.
    // The line that closes the brace is preserved (its `}` stays).
    // Any content AFTER `}` on that line is re-emitted as a separate line.
    out.push(head);
    out.push('  // ... (build body skipped for lint)');
    i++;
    let closed = false;
    while (i < lines.length && !closed) {
      const currentLine = lines[i];
      let j = 0;
      while (j < currentLine.length && depth > 0) {
        const ch = currentLine[j];
        if (ch === '{') depth++;
        else if (ch === '}') depth--;
        j++;
      }
      if (depth === 0) {
        // `}` is at column j-1. If anything is after on this line, keep it.
        const after = currentLine.slice(j).trim();
        if (after.length > 0) out.push(after);
        i++;
        closed = true;
        break;
      }
      // Line fully inside the body — skip it.
      i++;
    }
    // If we never closed (malformed file), continue to avoid infinite loop.
    if (!closed) {
      // No-op: parser will fail with brace mismatch.
    }
    continue;
  }
  return out.join('\n');
}

/**
 * Parse a .ets file.
 * @param {string} filePath absolute path
 * @returns {{ ast: object, sourceCode: string, locator: SourceLocator, programNode: object }}
 */
export function parseFile(filePath) {
  const sourceCode = readFileSync(filePath, 'utf8');
  // Preprocess ArkUI-specific syntax (struct, Builder keyword, build() body) → TS-compatible.
  // The preprocessed source is what we feed to the parser.
  // The locator uses the ORIGINAL source for accurate snippet extraction.
  const parserSource = preprocessArkUI(sourceCode);
  const ast = parse(parserSource, {
    ...PARSE_OPTIONS,
    filePath,
  });
  return {
    ast,
    sourceCode,                  // ORIGINAL .ets source (for snippets)
    parserSource,                // preprocessed (for debugging)
    locator: new SourceLocator(sourceCode),
    programNode: ast,
  };
}

/**
 * Convert an ESTree node's `loc` (start) to 1-indexed line + column.
 * Falls back to node.range if loc missing.
 */
function locToLineCol(sourceCode, node) {
  if (node.loc?.start) {
    return { line: node.loc.start.line + 1, col: node.loc.start.column + 1 };
  }
  if (typeof node.range?.[0] === 'number') {
    return offsetToLineCol(sourceCode, node.range[0]);
  }
  return { line: 0, col: 0 };
}

function offsetToLineCol(sourceCode, offset) {
  let line = 1;
  let col = 1;
  for (let i = 0; i < offset && i < sourceCode.length; i++) {
    if (sourceCode[i] === '\n') {
      line += 1;
      col = 1;
    } else {
      col += 1;
    }
  }
  return { line, col };
}

export class SourceLocator {
  constructor(sourceCode) {
    this.sourceCode = sourceCode;
    this.lines = sourceCode.split(/\r?\n/);
  }

  /**
   * Get {line, col} (1-indexed) for a node.
   */
  loc(node) {
    return locToLineCol(this.sourceCode, node);
  }

  /**
   * Get source snippet around the violation, with `context` lines of context.
   * Returns { before, line, after, marker }.
   */
  snippet(node, context = 2) {
    const { line, col } = this.loc(node);
    const startLine = Math.max(0, line - 1 - context);
    const endLine = Math.min(this.lines.length - 1, line - 1 + context);
    const before = this.lines.slice(startLine, line - 1).join('\n');
    const center = this.lines[line - 1] ?? '';
    const after = this.lines.slice(line, endLine + 1).join('\n');
    const marker = ' '.repeat(Math.max(0, col - 1)) + '^';
    return { before, line: center, after, marker };
  }
}
