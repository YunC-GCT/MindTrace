/**
 * scripts/link-check/sync-links.mjs
 *
 * Pure helpers for sync-renames.mjs (no git/filesystem access; no process exit).
 * Extracts inline markdown links with byte-precise href offsets so the CLI can
 * rewrite only the href portion of a link while leaving labels, code spans and
 * unrelated text untouched.
 *
 * Deliberately stricter than link-parser.mjs: it skips fenced code blocks and
 * inline code spans, but still matches links whose *label* contains backticks
 * (`` [`code` label](url) `` must NOT be mistaken for a code span).
 */

/**
 * Split a href into { path, fragment } on the FIRST '#' only.
 * Keeps the full fragment (including '#' and any later '#') intact.
 */
export function splitFragment(href) {
  const i = href.indexOf('#');
  if (i === -1) return { path: href, fragment: '' };
  return { path: href.slice(0, i), fragment: href.slice(i) };
}

/**
 * Classify a href into external / anchor / file.
 * Mirrors classifyLink() in link-parser.mjs but preserves the full fragment.
 */
export function classifyHref(href) {
  if (/^(https?|ftp):\/\//i.test(href) || /^[a-z][a-z0-9+.-]*:/i.test(href)) {
    return { kind: 'external', href };
  }
  if (href.startsWith('//')) {
    return { kind: 'external', href };
  }
  if (href.startsWith('#')) {
    return { kind: 'anchor', fragment: href.slice(1) };
  }
  const { path, fragment } = splitFragment(href);
  return { kind: 'file', path, fragment };
}

/**
 * Resolve a relative href against a source directory (forward slashes).
 * Returns the normalized repo-relative path, or null if it escapes the repo
 * root (more leading ".." segments than the source directory has, or an
 * absolute "/"-prefixed path).
 */
export function resolveRel(sourceDir, href) {
  const path = href.split('#')[0];
  if (path.startsWith('/')) return null;
  const base = sourceDir ? sourceDir.split('/') : [];
  const out = base.slice();
  for (const part of path.split('/')) {
    if (part === '' || part === '.') continue;
    if (part === '..') {
      if (out.length === 0) return null; // escapes repo root
      out.pop();
    } else {
      out.push(part);
    }
  }
  return out.join('/');
}

/**
 * Compute a forward-slash relative href from a source directory to a target
 * file path (both repo-relative, forward slashes).
 */
export function relativeHref(fromDir, target) {
  const from = fromDir ? fromDir.split('/') : [];
  const to = target.split('/');
  let common = 0;
  while (common < from.length && common < to.length && from[common] === to[common]) {
    common++;
  }
  const ups = from.length - common;
  const downs = to.slice(common);
  const segs = [];
  for (let i = 0; i < ups; i++) segs.push('..');
  for (const d of downs) segs.push(d);
  return segs.join('/');
}

/**
 * Try to parse an inline markdown link starting at `start` (line[start] === '[').
 * Returns { text, href, hrefStart, hrefEnd, end } where hrefStart/hrefEnd are
 * column offsets within `line`, or null if there is no valid link here.
 */
function tryParseLink(line, start) {
  const n = line.length;
  let i = start + 1;
  let depth = 1;
  let labelEnd = -1;
  while (i < n) {
    const c = line[i];
    if (c === '\\') {
      i += 2;
      continue;
    }
    if (c === '[') {
      depth++;
    } else if (c === ']') {
      depth--;
      if (depth === 0) {
        labelEnd = i;
        break;
      }
    }
    i++;
  }
  if (labelEnd === -1) return null;

  let j = labelEnd + 1;
  if (j >= n || line[j] !== '(') return null;

  let k = j + 1;
  while (k < n && (line[k] === ' ' || line[k] === '\t')) k++;

  let hrefStart;
  let hrefEnd;
  let closeParen;
  if (k < n && line[k] === '<') {
    const gt = line.indexOf('>', k + 1);
    if (gt === -1) return null;
    hrefStart = k + 1;
    hrefEnd = gt;
    let t = gt + 1;
    while (t < n && line[t] !== ')') t++;
    if (t >= n) return null;
    closeParen = t;
  } else {
    hrefStart = k;
    let t = k;
    while (t < n && line[t] !== ')' && !/\s/.test(line[t])) t++;
    hrefEnd = t;
    let u = t;
    while (u < n && line[u] !== ')') u++;
    if (u >= n) return null;
    closeParen = u;
  }

  const href = line.slice(hrefStart, hrefEnd);
  const text = line.slice(start + 1, labelEnd);
  return { text, href, hrefStart, hrefEnd, end: closeParen + 1 };
}

/**
 * Scan a single line for inline links, skipping inline code spans (backtick
 * runs). Backticks inside a link *label* are fine because the whole
 * `[...](...)` construct is consumed in one go.
 */
function scanInlineLinks(line, lineIndex, out) {
  const n = line.length;
  let i = 0;
  while (i < n) {
    const c = line[i];
    if (c === '`') {
      let j = i;
      let run = 0;
      while (j < n && line[j] === '`') {
        run++;
        j++;
      }
      const fence = '`'.repeat(run);
      const close = line.indexOf(fence, j);
      if (close === -1) {
        i = j; // unterminated code span: treat rest as code
        continue;
      }
      i = close + run;
      continue;
    }
    if (c === '[') {
      const r = tryParseLink(line, i);
      if (r) {
        out.push({ line: lineIndex, text: r.text, href: r.href, hrefStart: r.hrefStart, hrefEnd: r.hrefEnd });
        i = r.end;
        continue;
      }
    }
    i++;
  }
}

/**
 * Extract all inline markdown links from `content`, skipping fenced code
 * blocks (``` / ~~~) and inline code spans.
 *
 * Returns { links, eol } where eol is '\n' or '\r\n' (the detected line
 * separator) and links is an array of
 *   { line, text, href, hrefStart, hrefEnd }  (line and columns are 0-based).
 */
export function extractInlineLinks(content) {
  const links = [];
  const crlf = content.includes('\r\n');
  const eol = crlf ? '\r\n' : '\n';
  const lines = content.split(eol);

  let inFence = false;
  let fenceChar = '';
  let fenceLen = 0;

  for (let li = 0; li < lines.length; li++) {
    const line = lines[li];
    const trimmed = line.trimStart();
    const fenceMatch = trimmed.match(/^(```+|~~~+)/);
    if (fenceMatch) {
      const marker = fenceMatch[1];
      if (!inFence) {
        inFence = true;
        fenceChar = marker[0];
        fenceLen = marker.length;
      } else if (marker[0] === fenceChar && marker.length >= fenceLen && /^(```+|~~~+)\s*$/.test(trimmed)) {
        inFence = false;
      }
      continue;
    }
    if (inFence) continue;
    scanInlineLinks(line, li, links);
  }

  return { links, eol };
}
