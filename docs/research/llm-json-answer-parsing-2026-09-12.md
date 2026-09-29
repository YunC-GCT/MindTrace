# LLM JSON Answer Parsing and Escaping — 2026-09-12

> **Date:** 2026-09-12
> **Scope:** JSON text vs embedded string/log representations; `additional input` parse failures; safe backend extraction of an `answer` field; preservation of newlines and LaTeX backslashes in JS/TS/Node-style code
> **Project:** MindTrace
> **Author:** research agent
> **Source policy:** Primary sources only: JSON standards, ECMAScript/Fetch/CommonMark standards, MDN API/error references, and Node.js first-party runtime docs.

---

**TL;DR:** A payload such as `{"answer":"正态分布...\n\n1. 定义与参数...\n\n... \\frac{1}{\\sigma\\sqrt{2\\pi}}..."}` is valid JSON if it is exactly one JSON text with optional surrounding JSON whitespace, because RFC 8259 defines a JSON text as `ws value ws`, JSON object members as string names plus values, and JSON strings as quoted Unicode character sequences with required escaping for quotes, reverse solidus, and control characters. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [RFC 8259 §4](https://www.rfc-editor.org/rfc/rfc8259#section-4), [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7). An `additional input`-style error happens when the parser has already completed one JSON value and then sees extra non-whitespace, for example prose after the closing brace, a duplicated JSON object, a protocol prefix, a code fence wrapper that was not removed, or a log line containing non-JSON decoration; RFC 8259 permits only whitespace before and after the single JSON value in a JSON text, and MDN lists the ECMAScript-family error as `unexpected non-whitespace character after JSON data`. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [MDN JSON bad parse](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Errors/JSON_bad_parse). Backend code should call `JSON.parse` once per actual JSON encoding layer, extract `answer` after type checking, and never strip backslashes before parsing, because JSON escaping is the mechanism that turns `\n` into a line-feed character and `\\` into one literal backslash in the resulting string. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse).

## Question

An AI model returns raw JSON-like data such as:

```json
{"answer":"正态分布...\n\n1. 定义与参数...\n\n... \\frac{1}{\\sigma\\sqrt{2\\pi}}..."}
```

This note explains why an `additional input` parse error can happen, how to distinguish a valid JSON text from JSON embedded inside another representation, when `JSON.parse` should run once or twice, why manual backslash deletion is wrong, and how JS/TS/Node-style backend code should safely extract `answer` while tolerating code fences or extra prose.

## Method

- Verified repository convention before writing: research notes live in `docs/research/` and use `{topic-slug}-{YYYY-MM-DD}.md`. [`docs/style/naming-conventions.md`](../style/naming-conventions.md)
- Used RFC 8259 and ECMA-404 for JSON grammar and syntax boundaries; RFC 8259 states that ECMA-404 is a normative reference and that the two documents align on the definition of JSON text. [RFC 8259 §1.2](https://www.rfc-editor.org/rfc/rfc8259#section-1.2), [ECMA-404 publication page](https://www.ecma-international.org/publications-and-standards/standards/ecma-404/)
- Used ECMAScript and MDN for `JSON.parse`, `JSON.stringify`, string literal, and `String.raw` JS behavior; ECMA-404 says ECMA-262 defines mappings between valid JSON texts and ECMAScript runtime data structures. [ECMA-404 publication page](https://www.ecma-international.org/publications-and-standards/standards/ecma-404/), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse), [MDN `JSON.stringify`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify), [MDN `String.raw`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/raw)
- Used Fetch and Node.js first-party docs for common backend transport/logging behavior; Fetch defines `json()` on the Body mixin, and Node.js documents `console.log`/`console.error` formatting through `util.format` and object inspection. [Fetch Standard Body mixin](https://fetch.spec.whatwg.org/#body-mixin), [Node.js Console](https://nodejs.org/api/console.html#consolelogdata-args), [Node.js `util.format`](https://nodejs.org/api/util.html#utilformatformat-args)
- Used CommonMark for code-fence wrapper handling because many LLMs wrap JSON examples in fenced code blocks; CommonMark defines fenced code blocks with backtick or tilde fences and literal content until the closing fence. [CommonMark §4.5](https://spec.commonmark.org/0.31.2/#fenced-code-blocks)

## Findings

### 1. JSON Text Is Not The Same Thing As A Displayed String

A JSON text is a complete sequence `ws value ws`, so an object like `{"answer":"..."}` is valid as a JSON text only when the non-whitespace input consists of that one object value and nothing else. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2)

JSON can represent strings, numbers, booleans, null, objects, and arrays; a JSON object is braces around zero or more name/value members; a member name is a string and values can be any JSON value. [RFC 8259 §1](https://www.rfc-editor.org/rfc/rfc8259#section-1), [RFC 8259 §3](https://www.rfc-editor.org/rfc/rfc8259#section-3), [RFC 8259 §4](https://www.rfc-editor.org/rfc/rfc8259#section-4)

A JSON string begins and ends with quotation marks; quotation mark, reverse solidus (`\`), and control characters U+0000 through U+001F must be escaped inside JSON strings. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7)

JSON defines `\n` as the escape for line feed U+000A and `\\` as the compact escape representation for one reverse solidus U+005C; the same section also allows `\u005C` for one reverse solidus. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7)

ECMA-404 defines only the syntax of valid JSON texts and intentionally does not define how valid JSON text is internalized into a programming language; its publication page points to ECMA-262 for the mapping between valid JSON texts and ECMAScript runtime data structures. [ECMA-404 publication page](https://www.ecma-international.org/publications-and-standards/standards/ecma-404/)

The displayed sequence `{"answer":"...\n...\\frac..."}` can therefore be either actual JSON text from the wire or a representation of a string that contains JSON text, and backend code must identify which layer it is handling before deciding how many times to parse. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse)

### 2. Why `additional input` Happens

The JSON grammar allows whitespace before and after a single value, not arbitrary text after the value, so parsers reject inputs like `{"answer":"ok"} trailing words`, `{"answer":"ok"}{"answer":"again"}`, or `data: {"answer":"ok"}` when the entire string is passed to a JSON parser. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2)

RFC 8259 says a parser transforms a JSON text into another representation and must accept texts that conform to the JSON grammar; it may accept extensions, but a generator must produce text that strictly conforms to the JSON grammar. [RFC 8259 §9](https://www.rfc-editor.org/rfc/rfc8259#section-9), [RFC 8259 §10](https://www.rfc-editor.org/rfc/rfc8259#section-10)

MDN documents that `JSON.parse()` throws `SyntaxError` if the string is not valid JSON and lists `unexpected non-whitespace character after JSON data` among parse-failure messages, which is the ECMAScript-family counterpart to an `additional input` complaint after one complete JSON value has already been consumed. [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse), [MDN JSON bad parse](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Errors/JSON_bad_parse)

If an LLM wraps JSON in a Markdown fence, the full model text is not a JSON text until the fence delimiters and any surrounding prose are removed; CommonMark defines fenced code blocks as Markdown block constructs, not JSON syntax. [CommonMark §4.5](https://spec.commonmark.org/0.31.2/#fenced-code-blocks), [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2)

If a backend tries to parse a log line, it may be parsing a debugging representation rather than JSON; Node.js documents that `console.log` prints through `util.format`, that additional values can be formatted through `util.inspect`, and that `util.format` is intended as a debugging tool. [Node.js Console](https://nodejs.org/api/console.html#consolelogdata-args), [Node.js `util.format`](https://nodejs.org/api/util.html#utilformatformat-args)

### 3. Parse Once, Parse Twice, Or Do Not Parse

Call `JSON.parse` once when the value is a JSON text string whose top-level value is the object containing `answer`, because `JSON.parse()` parses a JSON string and returns the JavaScript value or object described by that string. [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse)

Do not call `JSON.parse` on data that the transport API has already parsed into an object; Fetch defines `Body.json()` as JSON-consuming behavior on the body, so code using `await response.json()` receives the parsed result rather than raw JSON text. [Fetch Standard Body mixin](https://fetch.spec.whatwg.org/#body-mixin), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

Call `JSON.parse` twice only when there are two JSON encoding layers, such as an outer JSON object whose `content` property is itself a string containing inner JSON text like `"{\"answer\":\"...\"}"`; the first parse decodes the outer object and the second parse decodes the inner JSON text string. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

Do not call `JSON.parse` twice merely because the inner `answer` contains escaped newlines or LaTeX backslashes; those escapes belong to the JSON string value and are resolved by the single parse of the object. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse)

Do not parse a Node `console.log(obj)` or `util.inspect(obj)` rendering as if it were JSON; Node documents those APIs as formatting/inspection utilities, while JSON has its own grammar and double-quoted string requirement. [Node.js Console](https://nodejs.org/api/console.html#consolelogdata-args), [Node.js `util.format`](https://nodejs.org/api/util.html#utilformatformat-args), [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7)

### 4. How Newlines And LaTeX Backslashes Transform

In JSON text, the two source characters `\` and `n` inside a string are the escape `\n`; after `JSON.parse`, the resulting JS string contains one line-feed character U+000A at that position. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

In JSON text, the two source characters `\` and `\` inside a string are the escape `\\`; after `JSON.parse`, the resulting JS string contains one literal reverse solidus/backslash U+005C at that position. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

Therefore valid JSON text must encode a final LaTeX command `\frac` as `\\frac` in the JSON source, and valid JSON text must encode a final LaTeX command `\sigma` as `\\sigma` in the JSON source. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7)

Manual replacement before parsing is unsafe because converting `\\sigma` in JSON source into `\sigma` creates the escape sequence `\s`, and RFC 8259 lists the permitted two-character escapes as `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, and `\t` plus Unicode `\uXXXX`, not `\s`. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7)

Manual replacement after parsing is also usually wrong because the parsed `answer` string already contains the intended line-feed characters and single LaTeX backslashes; further deletion or replacement changes the user-visible mathematical text. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

When a JSON text literal is written directly inside JavaScript or TypeScript source code, there is an additional ECMAScript string-literal layer before `JSON.parse` sees the JSON text; ECMAScript string literals have their own escape processing, and MDN demonstrates that `String.raw` can preserve backslash sequences in template literals instead of processing escapes like `\n`. [ECMAScript string literals](https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-string-literals), [MDN `String.raw`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/raw)

### 5. Backend Modification Recommendations

At the backend boundary, preserve the transport result exactly as bytes/text until the JSON parser runs; do not pre-normalize by deleting `\`, replacing `\n`, or converting `\\` before parse, because those sequences are defined JSON string escapes. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse)

If the HTTP client exposes `response.json()`, use that once for an HTTP body that is JSON; if the HTTP client exposes raw text or if the LLM content field is a string containing JSON, pass that string to one JSON parsing function that validates the shape. [Fetch Standard Body mixin](https://fetch.spec.whatwg.org/#body-mixin), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

Treat the parsed value as `unknown` until runtime checks prove it is an object with a string `answer`, because `JSON.parse()` can return an object, array, string, number, boolean, or null corresponding to the JSON text. [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

Use fallback extraction only to isolate the JSON text layer from LLM wrapping, and then let `JSON.parse` handle JSON escaping; this respects the RFC grammar and CommonMark fence syntax instead of mutating string escapes manually. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [CommonMark §4.5](https://spec.commonmark.org/0.31.2/#fenced-code-blocks)

Recommended JS/TS implementation:

```ts
type ParsedAnswer = {
  answer: string;
  source: 'direct-json' | 'fenced-json' | 'embedded-json';
};

function extractAnswerFromLlmText(raw: string): ParsedAnswer {
  const candidates = buildJsonCandidates(raw);

  for (const candidate of candidates) {
    const parsed = parseJsonObject(candidate.text);
    if (parsed === undefined) {
      continue;
    }

    const answer = getStringProperty(parsed, 'answer');
    if (answer !== undefined) {
      return { answer, source: candidate.source };
    }
  }

  return { answer: raw, source: 'embedded-json' };
}

function buildJsonCandidates(raw: string): Array<{ text: string; source: ParsedAnswer['source'] }> {
  const trimmed = raw.trim();
  const candidates: Array<{ text: string; source: ParsedAnswer['source'] }> = [
    { text: trimmed, source: 'direct-json' },
  ];

  const fenced = trimmed.match(/^```(?:json|JSON)?\s*\r?\n([\s\S]*?)\r?\n```$/);
  if (fenced !== null) {
    candidates.push({ text: fenced[1].trim(), source: 'fenced-json' });
  }

  const embedded = findFirstBalancedJsonObject(trimmed);
  if (embedded !== undefined) {
    candidates.push({ text: embedded, source: 'embedded-json' });
  }

  return candidates;
}

function parseJsonObject(text: string): Record<string, unknown> | undefined {
  try {
    const parsed: unknown = JSON.parse(text);
    if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
  } catch {
    return undefined;
  }

  return undefined;
}

function getStringProperty(obj: Record<string, unknown>, key: string): string | undefined {
  const value = obj[key];
  return typeof value === 'string' ? value : undefined;
}

function findFirstBalancedJsonObject(text: string): string | undefined {
  let start = -1;
  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];

    if (start < 0) {
      if (ch === '{') {
        start = i;
        depth = 1;
      }
      continue;
    }

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }

    if (ch === '"') {
      inString = true;
    } else if (ch === '{') {
      depth += 1;
    } else if (ch === '}') {
      depth -= 1;
      if (depth === 0) {
        return text.slice(start, i + 1);
      }
    }
  }

  return undefined;
}
```

This implementation tries the full trimmed string first, then a full-string Markdown code fence, then the first balanced JSON object embedded in extra prose; after each candidate is isolated, it uses `JSON.parse` rather than manual escape replacement, which matches the RFC JSON grammar and ECMAScript parsing API. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [ECMAScript `JSON.parse`](https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse), [CommonMark §4.5](https://spec.commonmark.org/0.31.2/#fenced-code-blocks)

If the LLM protocol returns an outer object whose content field is a JSON-encoded string, parse the outer JSON layer first, inspect the runtime type of the content field, and parse the content string only when that field is itself a JSON text string. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse)

Example for an outer parsed response:

```ts
function answerFromOuterPayload(payload: unknown): string {
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
    throw new Error('LLM payload is not an object');
  }

  const record = payload as Record<string, unknown>;
  const directAnswer = getStringProperty(record, 'answer');
  if (directAnswer !== undefined) {
    return directAnswer;
  }

  const content = getStringProperty(record, 'content');
  if (content !== undefined) {
    return extractAnswerFromLlmText(content).answer;
  }

  throw new Error('LLM payload has no string answer/content field');
}
```

When logging for diagnostics, log the parsed `answer` directly for human readability and log `JSON.stringify({ answer })` when a machine-readable JSON representation is needed; `JSON.stringify()` converts a JavaScript value to a JSON string, while Node `console.log` uses formatting/inspection. [MDN `JSON.stringify`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify), [Node.js Console](https://nodejs.org/api/console.html#consolelogdata-args), [Node.js `util.format`](https://nodejs.org/api/util.html#utilformatformat-args)

### 6. Practical Decision Table

| Input shape at backend boundary | Correct action | Why |
|---|---|---|
| HTTP body is JSON and client exposes `response.json()` | Use `await response.json()` once; do not `JSON.parse` the result again | Fetch defines `json()` on the Body mixin, and `JSON.parse` parses strings rather than already-parsed objects. [Fetch Standard Body mixin](https://fetch.spec.whatwg.org/#body-mixin), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse) |
| Raw text is exactly `{"answer":"...\n...\\frac..."}` | Call `JSON.parse` once, type-check object, read `answer` | RFC 8259 JSON text is one value plus surrounding whitespace, and `JSON.parse` returns the JS value described by that JSON string. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse) |
| Raw text is ```json fence around the object ``` | Remove the fence wrapper, then call `JSON.parse` once on the fenced content | Code fences are Markdown syntax, not JSON syntax. [CommonMark §4.5](https://spec.commonmark.org/0.31.2/#fenced-code-blocks), [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2) |
| Raw text is prose plus one JSON object | Extract a balanced object candidate, then call `JSON.parse` on that candidate | RFC 8259 permits only whitespace around the JSON value, so prose must not be passed to the JSON parser. [RFC 8259 §2](https://www.rfc-editor.org/rfc/rfc8259#section-2) |
| Outer object field is `content: "{\"answer\":\"...\"}"` | Parse the outer layer, then parse `content` once if it is a string containing JSON text | JSON strings escape inner quotes/backslashes, and `JSON.parse` maps each JSON text layer to a runtime value. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse) |
| Parsed object already has `answer: string` | Do not parse `answer`; render/store it as text | After parsing, `\n` and `\\` have already become line-feed and literal backslash characters in the JS string. [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.parse`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse) |
| Log output shows `{ answer: '...' }` | Do not parse the log; log machine-readable JSON separately with `JSON.stringify` | Node logs can use formatting/inspection, while JSON syntax requires double-quoted strings. [Node.js Console](https://nodejs.org/api/console.html#consolelogdata-args), [Node.js `util.format`](https://nodejs.org/api/util.html#utilformatformat-args), [RFC 8259 §7](https://www.rfc-editor.org/rfc/rfc8259#section-7), [MDN `JSON.stringify`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify) |

## Sources

- RFC 8259, *The JavaScript Object Notation (JSON) Data Interchange Format*: JSON grammar, JSON text boundary, object/value/string rules, parser/generator requirements. <https://www.rfc-editor.org/rfc/rfc8259>
- ECMA-404, *The JSON data interchange syntax*, publication page for syntax-only scope and ECMA-262 mapping note. <https://www.ecma-international.org/publications-and-standards/standards/ecma-404/>
- ECMAScript Language Specification: `JSON.parse`, `JSON.stringify`, JSON syntax, and string literals. <https://tc39.es/ecma262/multipage/structured-data.html#sec-json.parse>, <https://tc39.es/ecma262/multipage/structured-data.html#sec-json.stringify>, <https://tc39.es/ecma262/multipage/ecmascript-language-lexical-grammar.html#sec-string-literals>
- MDN JavaScript reference: `JSON.parse`, `JSON.stringify`, `String.raw`, and `SyntaxError: JSON.parse: bad parsing`. <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/parse>, <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/JSON/stringify>, <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/raw>, <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Errors/JSON_bad_parse>
- Fetch Standard: Body mixin and `json()` body consumption. <https://fetch.spec.whatwg.org/#body-mixin>
- Node.js docs: Console and `util.format`/inspection behavior for logs. <https://nodejs.org/api/console.html#consolelogdata-args>, <https://nodejs.org/api/util.html#utilformatformat-args>, <https://nodejs.org/api/util.html#utilinspectobject-options>
- CommonMark 0.31.2: fenced code block syntax. <https://spec.commonmark.org/0.31.2/#fenced-code-blocks>
