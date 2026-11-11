/**
 * GenerationDraftSupport.ets — 生成路线共享的解析、格式、预算与进度辅助函数
 *
 * 路径: agents/src/main/ets/subagents/GenerationDraftSupport.ets
 * 职责: 生成路线共享的解析、格式、预算与进度辅助函数，保持现有生成行为。
 * 依赖: common（领域类型、LlmConfig 与草稿 schema）
 * 数据流: 生成路线 / verifier → 辅助函数 → 领域值、请求配置或进度回调
 */
import { LlmConfig } from 'common/src/main/ets/Index';
import type {
  LlmJsonSchema,
  LlmResponseFormat,
  NoteDraftDocument,
  NoteDraftSection,
  NoteGenerationRequest,
  NoteGenerationProgressEvent,
  NoteGenerationProgressSink,
  SourceBundle,
} from 'common/src/main/ets/Index';
import { NOTE_DRAFT_JSON_SCHEMA } from 'common/src/main/ets/Index';

export const NOTE_MATH_REASONING_RULES: string =
  'Distinguish source givens, derived conclusions, and unconfirmed conditions. '
  + 'Solve the supplied problem and explain checkable derivation steps; do not merely transcribe it. '
  + 'You may add relevant definitions and standard theorems, stating their applicability and linking derivations to the source givens. '
  + 'Never present a derived result or an invented example as a verbatim source quotation. '
  + 'Do not silently guess unclear symbols, domains, orientations or other key conditions. '
  + 'If a missing condition changes the answer, state the precise question for the user and keep any resulting answer explicitly conditional. '
  + 'Before returning, check algebra, signs and consistent normal/boundary orientation; for extrema compare interior and boundary candidates; '
  + 'verify auxiliary-function derivatives and substitutions. Correct source errors only with an explicit explanation, preserving the original quotation. '
  + 'Classification confidence is model metadata, not OCR accuracy or mathematical truth.\n';

export function readRecordValue(parsed: Record<string, Object>, key: string): Object | undefined {
  return readRecordValueFromEntries(Object.entries(parsed) as Array<[string, Object]>, key);
}

export function readRecordValueFromEntries(entries: Array<[string, Object]>, key: string): Object | undefined {
  for (const entry of entries) {
    if (entry[0] === key) {
      return entry[1];
    }
  }
  return undefined;
}

export function readStringArray(value: Object | undefined): string[] {
  if (value === undefined || !Array.isArray(value)) {
    return [];
  }
  const result: string[] = [];
  const values: Object[] = value as Object[];
  for (const item of values) {
    if (typeof item === 'string') {
      result.push(item);
    }
  }
  return result;
}

/** 模型偶尔把文本字段返回成 {text/value/content: ...}；统一抽成字符串，避免 [object Object]。 */
export function readTextValue(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  if (Array.isArray(value)) {
    const parts: string[] = [];
    const values: Object[] = value as Object[];
    for (const item of values) {
      const text: string = readTextValue(item);
      if (text.length > 0) {
        parts.push(text);
      }
    }
    return parts.join('\n');
  }
  const record: Record<string, Object> = value as Record<string, Object>;
  const keys: string[] = ['text', 'value', 'content', 'markdown', 'body'];
  for (const key of keys) {
    const inner: Object | undefined = readRecordValue(record, key);
    if (inner !== undefined) {
      return readTextValue(inner);
    }
  }
  return '';
}

export function budgetedRequestTokens(request: NoteGenerationRequest, fallback: number): number {
  return budgetedTokens(request.tokenBudget, fallback);
}

export function budgetedTokens(budget: number | undefined, requested: number): number {
  if (budget === undefined || budget <= 0) {
    return requested;
  }
  return Math.min(requested, budget);
}

export function structuredResponseFormat(
  schemaText: string = NOTE_DRAFT_JSON_SCHEMA,
  name: string = 'mindtrace_note_draft',
): LlmResponseFormat {
  const schema: Record<string, Object> = JSON.parse(schemaText) as Record<string, Object>;
  const jsonSchema: LlmJsonSchema = {
    name: name,
    strict: true,
    schema: schema,
  };
  const config = LlmConfig.getInstance();
  if (config.supportsStrictStructuredOutput()) {
    return { type: 'json_schema', json_schema: jsonSchema };
  }
  return { type: 'json_object' };
}

export function parseDraftDocument(parsed: Record<string, Object>): NoteDraftDocument {
  const sectionsValue: Object | undefined = readRecordValue(parsed, 'sections');
  if (sectionsValue === undefined || !Array.isArray(sectionsValue)) {
    throw new Error('light draft sections missing');
  }
  const sections: NoteDraftSection[] = [];
  const rawSections: Object[] = sectionsValue as Object[];
  for (const rawSection of rawSections) {
    const record: Record<string, Object> = rawSection as Record<string, Object>;
    const sourceIds: string[] = readStringArray(readRecordValue(record, 'sourceIds'));
    sections.push({
      id: readTextValue(readRecordValue(record, 'id')),
      label: readTextValue(readRecordValue(record, 'label')),
      content: readTextValue(readRecordValue(record, 'content')),
      sourceIds: sourceIds,
      state: readRecordValue(record, 'state') === 'locked' ? 'locked' : 'generated',
      baseHash: readTextValue(readRecordValue(record, 'baseHash')),
    });
  }
  return {
    schemaVersion: readTextValue(readRecordValue(parsed, 'schemaVersion')),
    title: readTextValue(readRecordValue(parsed, 'title')),
    summary: readTextValue(readRecordValue(parsed, 'summary')),
    subject: readTextValue(readRecordValue(parsed, 'subject')),
    category: readTextValue(readRecordValue(parsed, 'category')),
    chapter: readTextValue(readRecordValue(parsed, 'chapter')),
    difficulty: Number(readRecordValue(parsed, 'difficulty') ?? 0),
    tags: readStringArray(readRecordValue(parsed, 'tags')),
    sections: sections,
  };
}

export function emitProgress(progressSink: NoteGenerationProgressSink | undefined, event: NoteGenerationProgressEvent): void {
  if (progressSink !== undefined) {
    progressSink(event);
  }
}

export function standardSourceText(bundle: SourceBundle): string {
  const lines: string[] = [];
  for (const fragment of bundle.fragments) {
    lines.push('[source:' + fragment.id + '] ' + fragment.text);
  }
  return lines.join('\n');
}
