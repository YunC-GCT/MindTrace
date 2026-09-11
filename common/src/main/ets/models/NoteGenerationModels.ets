/**
 * NoteGenerationModels.ets — Issue 98 typed note-generation contracts
 *
 * 路径: common/src/main/ets/models/NoteGenerationModels.ets
 * 职责: typed sources, draft validation, route budgets, and recoverable artifacts
 * 依赖: ./CommonTypes KnowledgeUnit, ../render/ContentProtocol
 *
 * 数据流:
 *   AI 浮窗 → AiService → Dispatcher → KnowledgeModel → LLM → Repository
 *
 * ArkTS 1.1 strict 适配:
 *   - 所有 schema 字符串用单引号拼接,避免 ArkTS strict nested-object literal 报错
 *   - helper 函数 validateDraftDocument 等对外独立导出,便于 ArkTS Hypium 测试直接 seam 调用
 */
import { KnowledgeUnit } from './CommonTypes';
import { ContentProtocol } from '../render/ContentProtocol';

export type NoteGenerationMode = 'create' | 'regenerate';
export type SourceKind = 'conversation' | 'ocr' | 'summary' | 'existing_note';
export type NoteGenerationRoute = 'light' | 'standard' | 'deep';
export type NoteGenerationStatus = 'running' | 'incomplete' | 'ready-preview' | 'needs-input' | 'failed' | 'cancelled' | 'committed';
export type DraftSectionState = 'generated' | 'locked';

export interface SourceFragment {
  id: string;
  kind: SourceKind;
  originId: string;
  sequence: number;
  fingerprint: string;
  text: string;
}

export interface SourceBundle {
  fragments: SourceFragment[];
}

export interface NoteGenerationRequirement {
  detailLevel: 'brief' | 'normal' | 'detailed';
  mustInclude: string[];
  mustAvoid: string[];
  targetSectionIds: string[];
  preserveUserEdits: boolean;
}

export interface NoteGenerationRequest {
  runId: string;
  instruction: string;
  mode: NoteGenerationMode;
  sources: SourceBundle;
  requirement?: NoteGenerationRequirement;
  targetNoteId?: string;
  baseVersion?: number;
  pendingSourceIds?: string[];
  route?: NoteGenerationRoute;
  tokenBudget?: number;
  incrementalPlan?: IncrementalPlan;
  incrementalSections?: IncrementalSection[];
}

export interface NoteDraftSection {
  id: string;
  label: string;
  content: string;
  sourceIds: string[];
  state: DraftSectionState;
  baseHash: string;
}

export interface NoteDraftDocument {
  schemaVersion: string;
  title: string;
  summary: string;
  subject: string;
  category: string;
  chapter: string;
  difficulty: number;
  tags: string[];
  sections: NoteDraftSection[];
  instruction?: string;
}

export interface ProcessIssue {
  stage: string;
  code: string;
  severity: 'hard' | 'soft';
  message: string;
  repairable: boolean;
  sourceId?: string;
  sectionId?: string;
}

export type NoteGenerationIssue = ProcessIssue;

export interface NoteGenerationOutlineSection {
  id: string;
  label: string;
  order: number;
  mustInclude: string[];
  sourceIds: string[];
  depth?: number;
  parentId?: string;
  segmentIds?: string[];
}

export interface NoteGenerationOutline {
  schemaVersion: string;
  sections: NoteGenerationOutlineSection[];
}

export type EvidenceItemType = 'claim' | 'definition' | 'formula' | 'step' | 'example' | 'conclusion';
export type EvidenceVerificationStatus = 'supported' | 'contradicted' | 'ambiguous';

export interface EvidenceSourceRef {
  sourceId: string;
  excerpt: string;
  start: number;
  end: number;
}

export interface NoteGenerationEvidenceItem {
  id: string;
  type: EvidenceItemType;
  claim: string;
  sourceRefs: EvidenceSourceRef[];
  targetSectionId: string;
  verification: EvidenceVerificationStatus;
}

export interface NoteGenerationVerification {
  status: EvidenceVerificationStatus;
  issues: NoteGenerationIssue[];
  checkedEvidenceIds: string[];
  decisions: NoteGenerationEvidenceDecision[];
}

export interface NoteGenerationEvidenceDecision {
  evidenceId: string;
  status: EvidenceVerificationStatus;
}

export interface NoteGenerationStandardResult {
  outline: NoteGenerationOutline;
  evidence: NoteGenerationEvidenceItem[];
  draft: NoteDraftDocument;
  verification: NoteGenerationVerification;
  reextractionCount?: number;
}

export interface NoteGenerationLedgerEntry {
  key: string;
  value: string;
  sourceIds: string[];
  sectionId: string;
}

export interface NoteGenerationLedger {
  formulas: NoteGenerationLedgerEntry[];
  terminology: NoteGenerationLedgerEntry[];
  conclusions: NoteGenerationLedgerEntry[];
}

export interface NoteGenerationSegment {
  id: string;
  sourceId: string;
  sequence: number;
  boundary: 'message' | 'ocr_page' | 'heading' | 'formula_block' | 'problem' | 'derivation' | 'paragraph';
  text: string;
}

export interface NoteGenerationDeepResult extends NoteGenerationStandardResult {
  ledger: NoteGenerationLedger;
  segments?: NoteGenerationSegment[];
}

export interface NoteGenerationBudget {
  maxTokens: number;
  maxNodeRuns: number;
  maxRepairRounds: number;
  maxSourceChars?: number;
}

export interface NoteGenerationCoverage {
  mustInclude: number;
  evidence: number;
  lockedPreservation: number;
}

export type NoteGenerationCheckpointDecision = 'best' | 'rejected' | 'initial';

export interface NoteGenerationProgress {
  round: number;
  stopReason?: string;
  rollback: boolean;
}

export interface NoteGenerationRun {
  id: string;
  route: NoteGenerationRoute;
  status: NoteGenerationStatus;
  instruction: string;
  sourceCount: number;
  tokenBudget: number;
  bestCheckpointId?: string;
  stopReason?: string;
  issueCount?: number;
  sourceIds?: string[];
  pendingSourceIds?: string[];
  sourceSummary?: string;
  createdAt?: number;
  updatedAt?: number;
}

export interface NoteGenerationCheckpoint {
  id: string;
  runId: string;
  iteration: number;
  stage: 'draft' | 'truth_check';
  parentId?: string;
  candidateHash: string;
  documentJson: string;
  accepted: boolean;
  issueCodes?: string[];
  outlineJson?: string;
  evidenceJson?: string;
  verificationJson?: string;
  issueFingerprint?: string;
  coverage?: NoteGenerationCoverage;
  tokenCost?: number;
  changeScope?: number;
  decision?: NoteGenerationCheckpointDecision;
  createdAt?: number;
}

export interface NoteDraftReadyEvent {
  runId: string;
  checkpointId: string;
  candidateHash: string;
  candidate: KnowledgeUnit;
  result: NoteGenerationResult;
  sourceCount: number;
  softIssueCount: number;
  sourceIds?: string[];
  pendingSourceIds?: string[];
  incrementalManifest?: IncrementalManifest;
  incrementalDiff?: IncrementalDiffItem[];
  expectedVersion?: number;
  incrementalInstruction?: string;
}

export interface PreparedCandidate {
  runId: string;
  checkpointId: string;
  candidateHash: string;
  candidate: KnowledgeUnit;
  sourceIds?: string[];
  commitKey?: string;
  pendingSourceIds?: string[];
  expectedVersion?: number;
  updateExisting?: boolean;
  incrementalManifest?: IncrementalManifest;
  incrementalDiff?: IncrementalDiffItem[];
}

export interface NoteGenerationCommitResult {
  commitKey: string;
  runId: string;
  checkpointId: string;
  noteId: string;
  version: number;
  sourceIds: string[];
  candidateJson?: string;
  committedAt?: number;
  generationMetadata?: string;
}

export type NoteGenerationLifecycleEvent = 'resumed' | 'retried' | 'committed'
  | 'duplicate-confirm' | 'cancelled';

export interface NoteGenerationLifecycleLog {
  runId: string;
  event: NoteGenerationLifecycleEvent;
  checkpointId?: string;
  issueCount?: number;
  sourceCount?: number;
  round?: number;
  stopReason?: string;
  rollback?: boolean;
  createdAt?: number;
}

export interface NoteGenerationRecovery {
  run: NoteGenerationRun;
  sources: SourceBundle;
  checkpoints: NoteGenerationCheckpoint[];
  bestCheckpoint?: NoteGenerationCheckpoint;
  softIssueCodes: string[];
}

export interface NoteGenerationResult {
  runId: string;
  route: NoteGenerationRoute;
  status: NoteGenerationStatus;
  candidate?: KnowledgeUnit;
  draft?: NoteDraftDocument;
  bestCheckpointId?: string;
  issues: NoteGenerationIssue[];
  questions: string[];
  stopReason?: string;
  promptTokens: number;
  completionTokens: number;
  sourceIds?: string[];
  outline?: NoteGenerationOutline;
  evidence?: NoteGenerationEvidenceItem[];
  verification?: NoteGenerationVerification;
  ledger?: NoteGenerationLedger;
  segments?: NoteGenerationSegment[];
  progress?: NoteGenerationProgress;
  incrementalPlan?: IncrementalPlan;
  incrementalManifest?: IncrementalManifest;
  incrementalDiff?: IncrementalDiffItem[];
  baseVersion?: number;
  incrementalInstruction?: string;
}

export interface NoteGenerationRepository {
  saveRun(run: NoteGenerationRun, bundle: SourceBundle): Promise<void>;
  saveCheckpoint(checkpoint: NoteGenerationCheckpoint): Promise<void>;
  restore(runId: string): Promise<NoteGenerationRecovery | undefined>;
  saveCommitResult(result: NoteGenerationCommitResult): Promise<void>;
  getCommitResult(commitKey: string): Promise<NoteGenerationCommitResult | undefined>;
  cancelRun(runId: string): Promise<void>;
  appendLifecycleLog(log: NoteGenerationLifecycleLog): Promise<void>;
  listRecoverableRuns(): Promise<NoteGenerationRun[]>;
  getRegenerationBase?(noteId: string): Promise<IncrementalBase | undefined>;
}

export type IncrementalSectionState = 'generated' | 'locked';
export type IncrementalDiffKind = 'added' | 'changed' | 'preserved' | 'locked';

export interface IncrementalSection {
  id: string;
  label: string;
  content: string;
  order: number;
  state: IncrementalSectionState;
  contentHash: string;
  sourceIds: string[];
  rawText?: string;
}

export interface IncrementalManifestSection {
  id: string;
  label: string;
  generatedHash: string;
  sourceIds: string[];
}

export interface IncrementalManifest {
  noteId: string;
  baseVersion: number;
  sections: IncrementalManifestSection[];
  sourceIds: string[];
  createdAt: number;
}

export interface IncrementalRequirement {
  instruction: string;
  targetSectionIds: string[];
  mustInclude: string[];
  preserveUserEdits: boolean;
}

export interface IncrementalPlan {
  noteId: string;
  baseVersion: number;
  targetSectionIds: string[];
  lockedSectionIds: string[];
  existingSourceIds: string[];
  newSourceIds: string[];
  relevantSourceIds: string[];
}

export interface IncrementalPatch {
  sectionId: string;
  operation: 'replace';
  content: string;
  sourceIds: string[];
}

export interface IncrementalDiffItem {
  sectionId: string;
  label: string;
  kind: IncrementalDiffKind;
  before: string;
  after: string;
}

export interface IncrementalMergeResult {
  ok: boolean;
  sections: IncrementalSection[];
  diff: IncrementalDiffItem[];
  issues: string[];
}

export interface IncrementalPatchResponse {
  patches: IncrementalPatch[];
}

export interface IncrementalBase {
  unit: KnowledgeUnit;
  manifest: IncrementalManifest;
  sources: SourceBundle;
  baseVersion: number;
}

export function parseIncrementalSections(content: string): IncrementalSection[] {
  const lines: string[] = content.replace(/\r/g, '').split('\n');
  const sections: IncrementalSection[] = [];
  let currentLabel: string = '正文';
  let currentBody: string[] = [];
  let order: number = 0;
  const usedIds: string[] = [];
  let hasHeading: boolean = false;
  const flush = (): void => {
    const rawBody: string = currentBody.join('\n');
    const body: string = rawBody.trim();
    if (body.length === 0) {
      currentBody = [];
      return;
    }
    let id: string = stableSectionId(order, currentLabel);
    if (usedIds.includes(id)) {
      id = id + '-' + order.toString();
    }
    usedIds.push(id);
    sections.push({
      id: id,
      label: currentLabel,
      content: body,
      order: order,
      state: 'generated',
      contentHash: sourceFingerprint(body),
      sourceIds: [],
      rawText: hasHeading ? '## ' + currentLabel + '\n' + rawBody : rawBody,
    });
    order += 1;
    currentBody = [];
  };
  for (const line of lines) {
    const trimmed: string = line.trim();
    if (trimmed.startsWith('## ')) {
      flush();
      currentLabel = trimmed.substring(3).trim();
      hasHeading = true;
    } else if (trimmed.startsWith('# ') && sections.length === 0 && currentBody.length === 0) {
      currentLabel = trimmed.substring(2).trim();
      hasHeading = true;
    } else {
      currentBody.push(line);
    }
  }
  flush();
  return sections;
}

export function renderIncrementalSections(sections: IncrementalSection[]): string {
  let allRaw: boolean = sections.length > 0;
  for (const section of sections) {
    if (section.rawText === undefined || section.contentHash !== sourceFingerprint(section.content)) {
      allRaw = false;
    }
  }
  if (allRaw) {
    const rawLines: string[] = [];
    for (const section of sections) {
      rawLines.push(section.rawText ?? '');
    }
    return rawLines.join('');
  }
  const lines: string[] = [];
  for (const section of sections) {
    if (section.rawText !== undefined && section.contentHash === sourceFingerprint(section.content)) {
      lines.push(section.rawText);
    } else {
      lines.push('## ' + section.label);
      lines.push(section.content);
    }
  }
  return lines.join('\n');
}

export function buildIncrementalManifest(
  noteId: string,
  baseVersion: number,
  sections: IncrementalSection[],
  sourceIds: string[],
): IncrementalManifest {
  const manifestSections: IncrementalManifestSection[] = [];
  for (const section of sections) {
    manifestSections.push({
      id: section.id,
      label: section.label,
      generatedHash: section.contentHash,
      sourceIds: section.sourceIds.slice(0),
    });
  }
  return {
    noteId: noteId,
    baseVersion: baseVersion,
    sections: manifestSections,
    sourceIds: sourceIds.slice(0),
    createdAt: Date.now(),
  };
}

export function detectIncrementalLocks(
  sections: IncrementalSection[],
  manifest: IncrementalManifest,
): IncrementalSection[] {
  const result: IncrementalSection[] = [];
  for (const section of sections) {
    const entry: IncrementalManifestSection | undefined = manifest.sections.find(
      (item: IncrementalManifestSection): boolean => item.id === section.id,
    );
    const locked: boolean = entry === undefined || entry.generatedHash !== sourceFingerprint(section.content);
    result.push({
      id: section.id,
      label: section.label,
      content: section.content,
      order: section.order,
      state: locked ? 'locked' : 'generated',
      contentHash: sourceFingerprint(section.content),
      sourceIds: entry === undefined ? [] : entry.sourceIds.slice(0),
      rawText: section.rawText,
    });
  }
  return result;
}

export function planIncrementalChange(
  requirement: IncrementalRequirement,
  sections: IncrementalSection[],
  manifest: IncrementalManifest,
  newSources: SourceFragment[],
): IncrementalPlan {
  const targetSectionIds: string[] = [];
  for (const section of sections) {
    if (requirement.targetSectionIds.includes(section.id)
      && (!requirement.preserveUserEdits || section.state !== 'locked')) {
      targetSectionIds.push(section.id);
    }
  }
  if (targetSectionIds.length === 0) {
    const instruction: string = requirement.instruction.toLowerCase();
    for (const section of sections) {
      const matchesLabel: boolean = requirement.mustInclude.some((item: string): boolean => section.label.includes(item));
      const matchesInstruction: boolean = (instruction.includes('例') && section.label.includes('例'))
        || (instruction.includes('推导') && section.label.includes('推导'))
        || (instruction.includes('公式') && section.label.includes('公式'));
      if ((matchesLabel || matchesInstruction) && section.state !== 'locked') {
        targetSectionIds.push(section.id);
      }
    }
    const hasExampleSection: boolean = sections.some((section: IncrementalSection): boolean => section.label.includes('例'));
    if (targetSectionIds.length === 0 && instruction.includes('例') && !hasExampleSection) {
      targetSectionIds.push(stableSectionId(sections.length, '例子'));
    }
  }
  const lockedSectionIds: string[] = [];
  for (const section of sections) {
    if (section.state === 'locked') {
      lockedSectionIds.push(section.id);
    }
  }
  const existingSourceIds: string[] = [];
  for (const section of sections) {
    if (targetSectionIds.includes(section.id)) {
      for (const sourceId of section.sourceIds) {
        if (!existingSourceIds.includes(sourceId)) {
          existingSourceIds.push(sourceId);
        }
      }
    }
  }
  const newSourceIds: string[] = [];
  for (const source of newSources) {
    if (!newSourceIds.includes(source.id)) {
      newSourceIds.push(source.id);
    }
  }
  const relevantSourceIds: string[] = existingSourceIds.concat(newSourceIds);
  return {
    noteId: manifest.noteId,
    baseVersion: manifest.baseVersion,
    targetSectionIds: targetSectionIds,
    lockedSectionIds: lockedSectionIds,
    existingSourceIds: existingSourceIds,
    newSourceIds: newSourceIds,
    relevantSourceIds: relevantSourceIds,
  };
}

export function mergeIncrementalPatches(
  sections: IncrementalSection[],
  plan: IncrementalPlan,
  patches: IncrementalPatch[],
): IncrementalMergeResult {
  const issues: string[] = [];
  const patchById: Map<string, IncrementalPatch> = new Map<string, IncrementalPatch>();
  for (const patch of patches) {
    if (!plan.targetSectionIds.includes(patch.sectionId)) {
      issues.push('PATCH_TARGET_NOT_PLANNED:' + patch.sectionId);
      continue;
    }
    if (patchById.has(patch.sectionId)) {
      issues.push('PATCH_TARGET_DUPLICATE:' + patch.sectionId);
      continue;
    }
    if (patch.content.trim().length === 0) {
      issues.push('PATCH_CONTENT_REQUIRED:' + patch.sectionId);
    }
    for (const sourceId of patch.sourceIds) {
      if (!plan.relevantSourceIds.includes(sourceId)) {
        issues.push('PATCH_SOURCE_NOT_RELEVANT:' + sourceId);
      }
    }
    patchById.set(patch.sectionId, patch);
  }
  for (const targetId of plan.targetSectionIds) {
    if (!patchById.has(targetId)) {
      issues.push('PATCH_TARGET_MISSING:' + targetId);
    }
  }
  const merged: IncrementalSection[] = [];
  const diff: IncrementalDiffItem[] = [];
  for (const section of sections) {
    const patch: IncrementalPatch | undefined = patchById.get(section.id);
    const targeted: boolean = plan.targetSectionIds.includes(section.id);
    if (section.state === 'locked' && patch !== undefined && patch.content !== section.content) {
      issues.push('LOCKED_SECTION_CHANGED:' + section.id);
    }
    const nextContent: string = patch === undefined ? section.content : patch.content;
    const nextSourceIds: string[] = patch === undefined ? section.sourceIds.slice(0) : patch.sourceIds.slice(0);
    const next: IncrementalSection = {
      id: section.id,
      label: section.label,
      content: nextContent,
      order: section.order,
      state: section.state,
      contentHash: sourceFingerprint(nextContent),
      sourceIds: nextSourceIds,
      rawText: patch === undefined ? section.rawText : undefined,
    };
    merged.push(next);
    const kind: IncrementalDiffKind = section.state === 'locked' ? 'locked'
      : !targeted ? 'preserved' : section.content === nextContent ? 'preserved' : 'changed';
    diff.push({ sectionId: section.id, label: section.label, kind: kind, before: section.content, after: nextContent });
  }
  for (const patch of patches) {
    const exists: boolean = sections.some((section: IncrementalSection): boolean => section.id === patch.sectionId);
    if (!exists && plan.targetSectionIds.includes(patch.sectionId)) {
      const added: IncrementalSection = {
        id: patch.sectionId,
        label: '新增章节',
        content: patch.content,
        order: merged.length,
        state: 'generated',
        contentHash: sourceFingerprint(patch.content),
        sourceIds: patch.sourceIds.slice(0),
        rawText: undefined,
      };
      merged.push(added);
      diff.push({ sectionId: added.id, label: added.label, kind: 'added', before: '', after: added.content });
    }
  }
  const globalIssues: string[] = validateIncrementalConsistency(merged);
  for (const issue of globalIssues) {
    issues.push(issue);
  }
  return { ok: issues.length === 0, sections: merged, diff: diff, issues: issues };
}

function validateIncrementalConsistency(sections: IncrementalSection[]): string[] {
  const issues: string[] = [];
  const formulas: Map<string, string> = new Map<string, string>();
  const terms: Map<string, string> = new Map<string, string>();
  for (const section of sections) {
    for (const line of section.content.split('\n')) {
      const equals: number = line.indexOf('=');
      if (equals > 0) {
        const symbol: string = line.substring(0, equals).trim();
        const formula: string = line.trim();
        const previous: string | undefined = formulas.get(symbol);
        if (previous !== undefined && previous !== formula) {
          issues.push('FORMULA_INCONSISTENT:' + section.id);
        }
        formulas.set(symbol, formula);
      }
      if (line.trim().startsWith('术语:')) {
        const termValue: string = line.trim().substring(3).trim();
        const separator: number = termValue.indexOf('=');
        if (separator > 0) {
          const term: string = termValue.substring(0, separator).trim();
          const definition: string = termValue.substring(separator + 1).trim();
          const previousTerm: string | undefined = terms.get(term);
          if (previousTerm !== undefined && previousTerm !== definition) {
            issues.push('TERM_INCONSISTENT:' + section.id);
          }
          terms.set(term, definition);
        }
      }
    }
    if (section.content.includes('参见') || section.content.includes('见第')) {
      const resolved: boolean = sections.some((other: IncrementalSection): boolean => other.id !== section.id
        && (section.content.includes(other.id) || section.content.includes(other.label)));
      if (!resolved) {
        issues.push('REFERENCE_UNRESOLVED:' + section.id);
      }
    }
  }
  return issues;
}

export const NOTE_DRAFT_SCHEMA_VERSION: string = 'mindtrace.note-draft.v1';
export const NOTE_OUTLINE_SCHEMA_VERSION: string = 'mindtrace.note-outline.v1';
export const NOTE_EVIDENCE_SCHEMA_VERSION: string = 'mindtrace.note-evidence.v1';
export const NOTE_VERIFICATION_SCHEMA_VERSION: string = 'mindtrace.note-verification.v1';

export function buildJsonSchema(id: string, requiredKeys: string[], propertyMap: Record<string, string>): string {
  const properties: string[] = [];
  for (const key of Object.keys(propertyMap)) {
    properties.push('"' + key + '":' + propertyMap[key]);
  }
  const required: string = requiredKeys.map((key) => { return '"' + key + '"'; }).join(',');
  return '{'
    + '"$id":"' + id + '",'
    + '"type":"object",'
    + '"additionalProperties":false,'
    + '"required":[' + required + '],'
    + '"properties":{' + properties.join(',') + '}}';
}

const NOTE_OUTLINE_SCHEMA_PROPERTIES: Record<string, string> = {};
NOTE_OUTLINE_SCHEMA_PROPERTIES['schemaVersion'] = '{"const":"' + NOTE_OUTLINE_SCHEMA_VERSION + '"}';
NOTE_OUTLINE_SCHEMA_PROPERTIES['sections'] = '{"type":"array","minItems":1,"maxItems":12}';

export const NOTE_OUTLINE_JSON_SCHEMA: string = buildJsonSchema(
  NOTE_OUTLINE_SCHEMA_VERSION,
  ['schemaVersion', 'sections'],
  NOTE_OUTLINE_SCHEMA_PROPERTIES,
);

const NOTE_EVIDENCE_SCHEMA_PROPERTIES: Record<string, string> = {};
NOTE_EVIDENCE_SCHEMA_PROPERTIES['evidence'] = '{"type":"array"}';

export const NOTE_EVIDENCE_JSON_SCHEMA: string = buildJsonSchema(
  'mindtrace.note-evidence.v1',
  ['evidence'],
  NOTE_EVIDENCE_SCHEMA_PROPERTIES,
);

export const NOTE_VERIFICATION_JSON_SCHEMA: string = '{'
  + '"$id":"mindtrace.note-verification.v1",'
  + '"type":"object",'
  + '"additionalProperties":false,'
  + '"required":["status","issues","checkedEvidenceIds","decisions"],'
  + '"properties":{'
  + '"status":{"enum":["supported","contradicted","ambiguous"]},'
  + '"issues":{"type":"array"},'
  + '"checkedEvidenceIds":{"type":"array","items":{"type":"string"}},'
  + '"decisions":{"type":"array","items":{"type":"object"}}}}';

const NOTE_STANDARD_SCHEMA_PROPERTIES: Record<string, string> = {};
NOTE_STANDARD_SCHEMA_PROPERTIES['outline'] = '{"type":"object","required":["schemaVersion","sections"]}';
NOTE_STANDARD_SCHEMA_PROPERTIES['evidence'] = '{"type":"array","items":{"type":"object"}}';
NOTE_STANDARD_SCHEMA_PROPERTIES['draft'] = '{"type":"object","required":["schemaVersion","title","sections"]}';

export const NOTE_STANDARD_JSON_SCHEMA: string = buildJsonSchema(
  'mindtrace.note-standard.v1',
  ['outline', 'evidence', 'draft'],
  NOTE_STANDARD_SCHEMA_PROPERTIES,
);

// Versioned JSON Schema contract. Providers may enforce this remotely, while
// local validation remains mandatory for every provider.
export const NOTE_DRAFT_JSON_SCHEMA: string = '{'
  + '"$schema":"https://json-schema.org/draft/2020-12/schema",'
  + '"$id":"mindtrace.note-draft.v1",'
  + '"type":"object",'
  + '"additionalProperties":false,'
  + '"required":["schemaVersion","title","summary","subject","category","chapter","difficulty","tags","sections"],'
  + '"properties":{'
  + '"schemaVersion":{"const":"mindtrace.note-draft.v1"},'
  + '"title":{"type":"string","minLength":1,"maxLength":120},'
  + '"summary":{"type":"string","maxLength":500},'
  + '"subject":{"type":"string","minLength":1,"maxLength":80},'
  + '"category":{"enum":["概念","定理","公式","证明题","计算题"]},'
  + '"chapter":{"type":"string","maxLength":120},'
  + '"difficulty":{"type":"integer","minimum":1,"maximum":4},'
  + '"tags":{"type":"array","maxItems":12,"items":{"type":"string","minLength":1}},'
  + '"sections":{"type":"array","minItems":1,"maxItems":12,"items":{"type":"object"}}'
  + '}}';

export function defaultRequirement(instruction: string): NoteGenerationRequirement {
  const detailed: boolean = instruction.indexOf('详细') >= 0 || instruction.toLowerCase().indexOf('detailed') >= 0;
  const mustInclude: string[] = [];
  const keywords: string[] = ['定义', '公式', '步骤', '例子', '结论', '推导'];
  for (const keyword of keywords) {
    if (instruction.includes(keyword)) {
      mustInclude.push(keyword);
    }
  }
  const result: NoteGenerationRequirement = {
    detailLevel: detailed ? 'detailed' : 'normal',
    mustInclude: mustInclude,
    mustAvoid: [],
    targetSectionIds: [],
    preserveUserEdits: true,
  };
  return result;
}

export function selectLightRoute(bundle: SourceBundle, instruction: string): NoteGenerationRoute {
  let totalLength: number = 0;
  for (const fragment of bundle.fragments) {
    totalLength += fragment.text.length;
  }
  const detailed: boolean = instruction.indexOf('详细') >= 0 || instruction.toLowerCase().indexOf('detailed') >= 0;
  if (bundle.fragments.length <= 1 && totalLength <= 4000 && !detailed) {
    return 'light';
  }
  return 'standard';
}

export function selectGenerationRoute(bundle: SourceBundle, instruction: string): NoteGenerationRoute {
  const normalized: string = instruction.toLowerCase();
  let totalLength: number = 0;
  let formulaSource: boolean = false;
  let ocrCount: number = 0;
  for (const fragment of bundle.fragments) {
    totalLength += fragment.text.length;
    if (fragment.kind === 'ocr') {
      ocrCount += 1;
    }
    if (fragment.text.indexOf('=') >= 0 || fragment.text.indexOf('\\(') >= 0 || fragment.text.indexOf('\\[') >= 0) {
      formulaSource = true;
    }
  }
  const standardInstruction: boolean = instruction.indexOf('公式') >= 0
    || instruction.indexOf('例子') >= 0
    || instruction.indexOf('完整') >= 0
    || instruction.indexOf('详细') >= 0
    || instruction.indexOf('多轮') >= 0
    || normalized.indexOf('formula') >= 0
    || normalized.indexOf('example') >= 0
    || normalized.indexOf('detailed') >= 0
    || normalized.indexOf('complete') >= 0;
  const deepInstruction: boolean = instruction.indexOf('证明') >= 0
    || instruction.indexOf('推导') >= 0
    || instruction.indexOf('长文') >= 0
    || instruction.indexOf('多主题') >= 0
    || instruction.indexOf('完整详细') >= 0
    || normalized.indexOf('derivation') >= 0
    || normalized.indexOf('proof') >= 0
    || normalized.indexOf('thorough') >= 0;
  if (totalLength > 12000 || bundle.fragments.length >= 3 || ocrCount >= 2 || deepInstruction) {
    return 'deep';
  }
  if (bundle.fragments.length > 1 || totalLength > 4000 || formulaSource || standardInstruction) {
    return 'standard';
  }
  return 'light';
}

export function lightBudget(): NoteGenerationBudget {
  return { maxTokens: 1200, maxNodeRuns: 8, maxRepairRounds: 0 };
}

export function standardBudget(): NoteGenerationBudget {
  return { maxTokens: 6000, maxNodeRuns: 12, maxRepairRounds: 2 };
}

export function deepBudget(): NoteGenerationBudget {
  return { maxTokens: 14000, maxNodeRuns: 20, maxRepairRounds: 4, maxSourceChars: 20000 };
}

function segmentBoundary(line: string): 'heading' | 'formula_block' | 'problem' | 'derivation' | 'paragraph' | undefined {
  const trimmed: string = line.trim();
  if (trimmed.startsWith('#')) {
    return 'heading';
  }
  if (trimmed.indexOf('\\[') >= 0 || trimmed.indexOf('$$') >= 0 || trimmed.indexOf('\\]') >= 0) {
    return 'formula_block';
  }
  if (trimmed.indexOf('=') >= 0 && trimmed.length <= 240) {
    return 'formula_block';
  }
  if (trimmed.indexOf('题目') >= 0 || trimmed.indexOf('问题') >= 0 || trimmed.indexOf('例题') >= 0
    || trimmed.indexOf('例子') >= 0 || trimmed.toLowerCase().indexOf('problem') >= 0) {
    return 'problem';
  }
  if (trimmed.indexOf('证明') >= 0 || trimmed.indexOf('推导') >= 0 || trimmed.indexOf('步骤') >= 0
    || trimmed.indexOf('因此') >= 0 || trimmed.indexOf('所以') >= 0) {
    return 'derivation';
  }
  return undefined;
}

export function segmentSourceBundle(bundle: SourceBundle): NoteGenerationSegment[] {
  const segments: NoteGenerationSegment[] = [];
  let sequence: number = 0;
  for (const fragment of bundle.fragments) {
    const lines: string[] = fragment.text.split('\n');
    let current: string[] = [];
    let currentBoundary: 'message' | 'ocr_page' | 'heading' | 'formula_block' | 'problem' | 'derivation' | 'paragraph' = fragment.kind === 'ocr' ? 'ocr_page' : 'message';
    const flush = (): void => {
      const text: string = current.join('\n').trim();
      if (text.length > 0) {
        segments.push({
          id: fragment.id + '#' + segments.filter((item: NoteGenerationSegment): boolean => item.sourceId === fragment.id).length.toString(),
          sourceId: fragment.id,
          sequence: sequence,
          boundary: currentBoundary,
          text: text,
        });
        sequence += 1;
      }
      current = [];
    };
    for (const line of lines) {
      const boundary: 'heading' | 'formula_block' | 'problem' | 'derivation' | 'paragraph' | undefined = segmentBoundary(line);
      if (boundary !== undefined && current.length > 0) {
        flush();
      }
      if (boundary !== undefined) {
        currentBoundary = boundary;
      }
      current.push(line);
      if (line.trim().length === 0 && current.length > 1) {
        flush();
        currentBoundary = fragment.kind === 'ocr' ? 'ocr_page' : 'message';
      }
    }
    flush();
  }
  return segments;
}

export function buildDeepOutline(
  segments: NoteGenerationSegment[],
  requirement: NoteGenerationRequirement,
): NoteGenerationOutline {
  const sections: NoteGenerationOutlineSection[] = [];
  let order: number = 0;
  for (const segment of segments) {
    let label: string = '材料 ' + (order + 1).toString();
    if (segment.boundary === 'heading') {
      const firstLine: string = segment.text.split('\n')[0].trim();
      let markerLength: number = 0;
      while (markerLength < firstLine.length && firstLine.charAt(markerLength) === '#') {
        markerLength += 1;
      }
      label = firstLine.substring(markerLength).trim();
    } else if (segment.boundary === 'formula_block') {
      label = '公式与定义';
    } else if (segment.boundary === 'problem') {
      label = '题目与例子';
    } else if (segment.boundary === 'derivation') {
      label = '证明与推导';
    }
    const mustInclude: string[] = [];
    for (const item of requirement.mustInclude) {
      if (segment.text.includes(item) || label.includes(item)) {
        mustInclude.push(item);
      }
    }
    const parentId: string | undefined = sections.length === 0 ? undefined : sections[sections.length - 1].id;
    sections.push({
      id: stableSectionId(order, label) + '-' + segment.sequence.toString(),
      label: label,
      order: order,
      mustInclude: mustInclude,
      sourceIds: [segment.sourceId],
      depth: segment.boundary === 'derivation' ? 0 : 1,
      parentId: parentId,
      segmentIds: [segment.id],
    });
    order += 1;
  }
  return { schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION, sections: sections };
}

export function validateDeepOutline(
  outline: NoteGenerationOutline,
  segments: NoteGenerationSegment[],
  bundle: SourceBundle,
  requirement: NoteGenerationRequirement,
): NoteGenerationIssue[] {
  const issues: NoteGenerationIssue[] = [];
  const mappedSourceIds: string[] = [];
  const sectionIds: string[] = [];
  for (const section of outline.sections) {
    if (sectionIds.includes(section.id)) {
      issues.push({ stage: 'outline', code: 'DEEP_SECTION_ID_DUPLICATE', severity: 'hard', message: 'deep outline section ids must be unique', repairable: false, sectionId: section.id });
    }
    sectionIds.push(section.id);
    if (section.sourceIds.length === 0 || section.segmentIds === undefined || section.segmentIds.length === 0) {
      issues.push({ stage: 'outline', code: 'DEEP_ORPHAN_SECTION', severity: 'hard', message: 'deep section must map semantic source segments', repairable: false, sectionId: section.id });
    }
    for (const sourceId of section.sourceIds) {
      const sourceExists: boolean = bundle.fragments.some((fragment): boolean => fragment.id === sourceId);
      if (!sourceExists) {
        issues.push({ stage: 'outline', code: 'DEEP_SOURCE_INVALID', severity: 'hard', message: 'deep outline references an unknown source', repairable: false, sourceId: sourceId, sectionId: section.id });
      }
      if (!mappedSourceIds.includes(sourceId)) {
        mappedSourceIds.push(sourceId);
      }
    }
    for (const segmentId of section.segmentIds ?? []) {
      const segment: NoteGenerationSegment | undefined = segments.find((item): boolean => item.id === segmentId);
      if (segment === undefined || !section.sourceIds.includes(segment.sourceId)) {
        issues.push({ stage: 'outline', code: 'DEEP_SEGMENT_MAPPING_INVALID', severity: 'hard', message: 'deep outline segment mapping is invalid', repairable: false, sectionId: section.id });
      }
    }
  }
  for (const fragment of bundle.fragments) {
    if (fragment.kind !== 'summary' && !mappedSourceIds.includes(fragment.id)) {
      issues.push({ stage: 'outline', code: 'DEEP_SOURCE_ORPHANED', severity: 'hard', message: 'deep source has no section destination: ' + fragment.id, repairable: false, sourceId: fragment.id });
    }
  }
  for (const item of requirement.mustInclude) {
    let mapped: boolean = false;
    for (const section of outline.sections) {
      if (section.mustInclude.includes(item)) {
        mapped = true;
        break;
      }
    }
    if (!mapped) {
      issues.push({ stage: 'outline', code: 'DEEP_MUST_INCLUDE_UNMAPPED', severity: 'hard', message: 'must-include item has no deep section destination: ' + item, repairable: false });
    }
  }
  return issues;
}

export function sourceFingerprint(text: string): string {
  let hash: number = 2166136261;
  for (let index: number = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16);
}

export function buildSourceId(kind: SourceKind, originId: string, sequence: number): string {
  return kind + ':' + originId + ':' + sequence.toString();
}

export function stableSectionId(index: number, label: string): string {
  const lowerLabel: string = label.trim().toLowerCase();
  let safeLabel: string = '';
  for (const character of lowerLabel) {
    const code: number = character.charCodeAt(0);
    if ((code >= 97 && code <= 122) || (code >= 48 && code <= 57)) {
      safeLabel += character;
    } else if (safeLabel.length > 0 && !safeLabel.endsWith('-')) {
      safeLabel += '-';
    }
  }
  while (safeLabel.endsWith('-')) {
    safeLabel = safeLabel.substring(0, safeLabel.length - 1);
  }
  const suffix: string = safeLabel.length > 0 ? safeLabel : 'item-' + sourceFingerprint(label).substring(0, 8);
  return 'section-' + suffix;
}

export function validateSourceBundle(bundle: SourceBundle): NoteGenerationIssue[] {
  const issues: NoteGenerationIssue[] = [];
  const seen: string[] = [];
  let previousSequence: number = -1;
  for (const fragment of bundle.fragments) {
    if (fragment.id.trim().length === 0) {
      issues.push({ stage: 'source', code: 'SOURCE_ID_REQUIRED', severity: 'hard', message: 'source id is required', repairable: false });
    }
    if (seen.includes(fragment.id)) {
      issues.push({ stage: 'source', code: 'SOURCE_ID_DUPLICATE', severity: 'hard', message: 'source ids must be unique', repairable: false, sourceId: fragment.id });
    }
    seen.push(fragment.id);
    if (fragment.text.trim().length === 0) {
      issues.push({ stage: 'source', code: 'SOURCE_TEXT_REQUIRED', severity: 'hard', message: 'source text is required', repairable: false, sourceId: fragment.id });
    }
    if (fragment.sequence <= previousSequence) {
      issues.push({ stage: 'source', code: 'SOURCE_ORDER_INVALID', severity: 'hard', message: 'source order must be strictly increasing', repairable: false, sourceId: fragment.id });
    }
    previousSequence = fragment.sequence;
  }
  return issues;
}

export function normalizeOutline(outline: NoteGenerationOutline, sourceIds: string[]): NoteGenerationOutline {
  const sections: NoteGenerationOutlineSection[] = [];
  const usedIds: string[] = [];
  let index: number = 0;
  for (const section of outline.sections) {
    const mappedSourceIds: string[] = [];
    for (const sourceId of section.sourceIds) {
      if (sourceIds.includes(sourceId) && !mappedSourceIds.includes(sourceId)) {
        mappedSourceIds.push(sourceId);
      }
    }
    let stableId: string = stableSectionId(index, section.label);
    if (usedIds.includes(stableId)) {
      stableId = stableId + '-' + index.toString();
    }
    usedIds.push(stableId);
    sections.push({
      id: stableId,
      label: section.label.trim(),
      order: index,
      mustInclude: section.mustInclude.slice(0),
      sourceIds: mappedSourceIds,
    });
    index += 1;
  }
  return { schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION, sections: sections };
}

export function validateStandardArtifacts(
  outline: NoteGenerationOutline,
  evidence: NoteGenerationEvidenceItem[],
  draft: NoteDraftDocument,
  bundle: SourceBundle,
  requirement: NoteGenerationRequirement,
): NoteGenerationIssue[] {
  const issues: NoteGenerationIssue[] = [];
  const sourceIds: string[] = [];
  for (const fragment of bundle.fragments) {
    sourceIds.push(fragment.id);
  }
  const sourceById: Map<string, SourceFragment> = new Map<string, SourceFragment>();
  for (const fragment of bundle.fragments) {
    sourceById.set(fragment.id, fragment);
  }
  const sectionIds: string[] = [];
  for (const section of outline.sections) {
    if (sectionIds.includes(section.id)) {
      issues.push({ stage: 'outline', code: 'OUTLINE_SECTION_ID_DUPLICATE', severity: 'hard', message: 'outline section ids must be unique', repairable: true, sectionId: section.id });
    }
    if (section.order !== sectionIds.length) {
      issues.push({ stage: 'outline', code: 'OUTLINE_ORDER_INVALID', severity: 'hard', message: 'outline section order is not stable', repairable: true, sectionId: section.id });
    }
    sectionIds.push(section.id);
    if (section.sourceIds.length === 0) {
      issues.push({ stage: 'outline', code: 'OUTLINE_SOURCE_MAPPING_REQUIRED', severity: 'hard', message: 'outline section must map a source', repairable: true, sectionId: section.id });
    }
    for (const sourceId of section.sourceIds) {
      if (!sourceIds.includes(sourceId)) {
        issues.push({ stage: 'outline', code: 'OUTLINE_SOURCE_INVALID', severity: 'hard', message: 'outline references an unknown source', repairable: true, sectionId: section.id, sourceId: sourceId });
      }
    }
  }
  for (const mustInclude of requirement.mustInclude) {
    let mapped: boolean = false;
    for (const section of outline.sections) {
      if (section.mustInclude.includes(mustInclude)) {
        mapped = true;
        break;
      }
    }
    if (!mapped) {
      issues.push({ stage: 'outline', code: 'MUST_INCLUDE_UNMAPPED', severity: 'hard', message: 'must-include item has no outline destination', repairable: true });
    }
  }
  for (const sourceId of sourceIds) {
    const source: SourceFragment | undefined = sourceById.get(sourceId);
    if (source !== undefined && source.kind === 'summary') {
      continue;
    }
    let mapped: boolean = false;
    for (const section of outline.sections) {
      if (section.sourceIds.includes(sourceId)) {
        mapped = true;
        break;
      }
    }
    if (!mapped) {
      issues.push({ stage: 'outline', code: 'OUTLINE_SOURCE_ORPHANED', severity: 'hard', message: 'important source has no outline destination', repairable: true, sourceId: sourceId });
    }
  }
  if (evidence.length === 0 && outline.sections.length > 0) {
    issues.push({ stage: 'evidence', code: 'EVIDENCE_REQUIRED', severity: 'hard', message: 'standard route requires an evidence ledger', repairable: true });
  }
  for (const item of evidence) {
    if (!sectionIds.includes(item.targetSectionId)) {
      issues.push({ stage: 'evidence', code: 'EVIDENCE_SECTION_INVALID', severity: 'hard', message: 'evidence target section is unknown', repairable: true, sectionId: item.targetSectionId });
    }
    if (item.sourceRefs.length === 0) {
      issues.push({ stage: 'evidence', code: 'EVIDENCE_SOURCE_REQUIRED', severity: 'hard', message: 'evidence must cite a source', repairable: true });
    }
    let previousSourceSequence: number = -1;
    for (const ref of item.sourceRefs) {
      const source: SourceFragment | undefined = sourceById.get(ref.sourceId);
      if (source === undefined) {
        issues.push({ stage: 'evidence', code: 'EVIDENCE_SOURCE_INVALID', severity: 'hard', message: 'evidence references an unknown source', repairable: true, sourceId: ref.sourceId });
        continue;
      }
      const located: number = source.text.indexOf(ref.excerpt);
      if (ref.excerpt.trim().length === 0 || located < 0 || ref.start !== located
        || ref.end < ref.start || ref.end - ref.start < ref.excerpt.length) {
        issues.push({ stage: 'evidence', code: 'EVIDENCE_EXCERPT_NOT_LOCATABLE', severity: 'hard', message: 'evidence excerpt cannot be located in source', repairable: true, sourceId: ref.sourceId });
      }
      if (source.sequence < previousSourceSequence) {
        issues.push({ stage: 'evidence', code: 'EVIDENCE_SOURCE_ORDER_INVALID', severity: 'hard', message: 'evidence source references are out of order', repairable: true, sourceId: ref.sourceId });
      }
      previousSourceSequence = source.sequence;
      if (item.type === 'formula' && !source.text.includes(ref.excerpt)) {
        issues.push({ stage: 'evidence', code: 'FORMULA_NOT_PRESERVED', severity: 'hard', message: 'formula evidence is not preserved', repairable: true, sourceId: ref.sourceId });
      }
    }
    if (item.verification === 'contradicted') {
      issues.push({ stage: 'evidence', code: 'EVIDENCE_CONTRADICTED', severity: 'hard', message: 'verifier found contradicted evidence', repairable: true });
    }
    if (item.verification === 'ambiguous') {
      issues.push({ stage: 'evidence', code: 'EVIDENCE_AMBIGUOUS', severity: 'hard', message: 'verifier found ambiguous evidence', repairable: true });
    }
  }
  if (requirement.mustInclude.includes('公式')) {
    let formulaEvidence: boolean = false;
    for (const item of evidence) {
      if (item.type === 'formula') {
        formulaEvidence = true;
        break;
      }
    }
    if (!formulaEvidence) {
      issues.push({ stage: 'evidence', code: 'FORMULA_EVIDENCE_REQUIRED', severity: 'hard', message: 'requested formulas require formula evidence', repairable: true });
    }
  }
  const draftIssues: NoteGenerationIssue[] = validateDraftDocument(draft, sourceIds);
  for (const issue of draftIssues) {
    issues.push(issue);
  }
  for (const section of draft.sections) {
    if (!sectionIds.includes(section.id)) {
      issues.push({ stage: 'draft', code: 'DRAFT_SECTION_INVALID', severity: 'hard', message: 'draft section is not in outline', repairable: true, sectionId: section.id });
    }
  }
  if (draft.instruction === undefined || draft.instruction.trim().length === 0) {
    issues.push({ stage: 'draft', code: 'INSTRUCTION_NOT_PRESERVED', severity: 'hard', message: 'draft must preserve the user instruction', repairable: true });
  }
  for (const item of evidence) {
    let target: NoteDraftSection | undefined = undefined;
    for (const section of draft.sections) {
      if (section.id === item.targetSectionId) {
        target = section;
        break;
      }
    }
    if (target !== undefined) {
      for (const ref of item.sourceRefs) {
        if (!target.sourceIds.includes(ref.sourceId)) {
          issues.push({ stage: 'draft', code: 'DRAFT_SOURCE_MAPPING_MISSING', severity: 'hard', message: 'draft section lost an evidence source mapping', repairable: true, sectionId: target.id, sourceId: ref.sourceId });
        }
        if (!target.content.includes(ref.excerpt)) {
          const code: string = item.type === 'formula' ? 'FORMULA_NOT_PRESERVED' : 'EVIDENCE_NOT_PRESERVED';
          issues.push({ stage: 'draft', code: code, severity: 'hard', message: 'draft section does not preserve evidence content', repairable: true, sectionId: target.id, sourceId: ref.sourceId });
        }
      }
    }
  }
  return issues;
}

export class NoteGenerationEvidenceVerifier {
  verify(
    outline: NoteGenerationOutline,
    evidence: NoteGenerationEvidenceItem[],
    draft: NoteDraftDocument,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
  ): NoteGenerationVerification {
    const issues: NoteGenerationIssue[] = validateStandardArtifacts(outline, evidence, draft, bundle, requirement);
    let status: EvidenceVerificationStatus = 'supported';
    for (const item of evidence) {
      if (item.verification === 'contradicted') {
        status = 'contradicted';
        break;
      }
      if (item.verification === 'ambiguous' && status === 'supported') {
        status = 'ambiguous';
      }
    }
    if (issues.length > 0 && status === 'supported') {
      status = 'ambiguous';
    }
    const checkedEvidenceIds: string[] = [];
    for (const item of evidence) {
      checkedEvidenceIds.push(item.id);
    }
    const decisions: NoteGenerationEvidenceDecision[] = [];
    for (const item of evidence) {
      decisions.push({ evidenceId: item.id, status: item.verification });
    }
    return { status: status, issues: issues, checkedEvidenceIds: checkedEvidenceIds, decisions: decisions };
  }
}

export function validateDraftDocument(document: NoteDraftDocument, sourceIds: string[] = []): NoteGenerationIssue[] {
  const issues: NoteGenerationIssue[] = [];
  const contentProtocol: ContentProtocol = new ContentProtocol();
  if (document.schemaVersion !== NOTE_DRAFT_SCHEMA_VERSION) {
    issues.push({ stage: 'schema', code: 'SCHEMA_VERSION', severity: 'hard', message: 'unsupported draft schema', repairable: false });
  }
  if (document.title.trim().length === 0) {
    issues.push({ stage: 'domain', code: 'TITLE_REQUIRED', severity: 'hard', message: 'title is required', repairable: true });
  }
  const protocolTitle: ContentProtocol = new ContentProtocol();
  if (protocolTitle.hasFormulaSyntax(document.title) || protocolTitle.hasFormulaSyntax(document.summary)) {
    issues.push({ stage: 'content', code: 'FORMULA_IN_METADATA', severity: 'hard', message: 'title and summary must not contain formulas', repairable: true });
  }
  if (document.subject.trim().length === 0) {
    issues.push({ stage: 'domain', code: 'SUBJECT_REQUIRED', severity: 'hard', message: 'subject is required', repairable: true });
  }
  if (document.category !== '概念' && document.category !== '定理' && document.category !== '公式'
    && document.category !== '证明题' && document.category !== '计算题') {
    issues.push({ stage: 'domain', code: 'CATEGORY_INVALID', severity: 'hard', message: 'category is invalid', repairable: true });
  }
  if (document.sections.length === 0) {
    issues.push({ stage: 'domain', code: 'SECTIONS_REQUIRED', severity: 'hard', message: 'at least one section is required', repairable: true });
  }
  const allowedKeys: string[] = ['schemaVersion', 'title', 'summary', 'subject', 'category', 'chapter', 'difficulty', 'tags', 'sections'];
  if (allowedKeys.length !== 9) {
    issues.push({ stage: 'schema', code: 'SCHEMA_CONTRACT', severity: 'hard', message: 'draft schema contract is unavailable', repairable: false });
  }
  for (const section of document.sections) {
    if (section.id.trim().length === 0 || section.content.trim().length === 0) {
      issues.push({ stage: 'domain', code: 'SECTION_EMPTY', severity: 'hard', message: 'section id and content are required', repairable: true, sectionId: section.id });
    }
    if (sourceIds.length > 0) {
      if (section.sourceIds.length === 0) {
        issues.push({ stage: 'evidence', code: 'SOURCE_REFERENCE_REQUIRED', severity: 'hard', message: 'section must reference an original source', repairable: true, sectionId: section.id });
      }
      for (const sourceId of section.sourceIds) {
        if (sourceIds.indexOf(sourceId) < 0) {
          issues.push({ stage: 'evidence', code: 'SOURCE_REFERENCE_INVALID', severity: 'hard', message: 'section references an unknown source', repairable: true, sectionId: section.id, sourceId: sourceId });
        }
      }
    }
    const contentValidation = contentProtocol.validateNoteMarkdown(section.content);
    if (!contentValidation.ok) {
      issues.push({ stage: 'content', code: 'MM_MD_INVALID', severity: 'hard', message: 'section content violates MM-MD-v1', repairable: true, sectionId: section.id });
    }
  }
  return issues;
}

export function validateDraftShape(parsed: Record<string, Object>): string[] {
  const issues: string[] = [];
  const required: string[] = ['schemaVersion', 'title', 'summary', 'subject', 'category', 'chapter', 'difficulty', 'tags', 'sections'];
  for (const key of required) {
    if (!Object.keys(parsed).includes(key)) {
      issues.push('missing_' + key);
    }
  }
  for (const key of Object.keys(parsed)) {
    if (!required.includes(key)) {
      issues.push('additional_property_' + key);
    }
  }
  const sections: Object | undefined = parsed['sections'];
  if (sections !== undefined && !Array.isArray(sections)) {
    issues.push('sections_not_array');
  }
  const tags: Object | undefined = parsed['tags'];
  if (tags !== undefined && !Array.isArray(tags)) {
    issues.push('tags_not_array');
  }
  return issues;
}

export type EvidenceItemTypeString = 'claim' | 'definition' | 'formula' | 'step' | 'example' | 'conclusion';

function classifyEvidenceType(label: string): EvidenceItemTypeString {
  if (label.includes('公式')) {
    return 'formula';
  }
  if (label.includes('步骤') || label.includes('推导') || label.includes('证明')) {
    return 'step';
  }
  if (label.includes('例')) {
    return 'example';
  }
  if (label.includes('定义')) {
    return 'definition';
  }
  if (label.includes('结论')) {
    return 'conclusion';
  }
  return 'claim';
}

function findDirectDraftSource(section: NoteDraftSection, sources: SourceBundle): SourceFragment | undefined {
  for (const sourceId of section.sourceIds) {
    const mapped: SourceFragment | undefined = sources.fragments.find(
      (item: SourceFragment): boolean => item.id === sourceId,
    );
    if (mapped !== undefined) {
      return mapped;
    }
  }
  for (const source of sources.fragments) {
    if (findDirectDraftExcerpt(source.text, section.content).length > 0) {
      return source;
    }
  }
  return undefined;
}

function findDirectDraftExcerpt(sourceText: string, sectionText: string): string {
  const source: string = sourceText.trim();
  const section: string = sectionText.trim();
  const maxLength: number = Math.min(120, source.length);
  for (let length: number = maxLength; length >= 8; length -= 1) {
    const prefix: string = source.substring(0, length);
    if (section.includes(prefix)) {
      return prefix;
    }
  }
  const sectionPrefix: string = section.substring(0, Math.min(120, section.length));
  if (sectionPrefix.length >= 8 && source.includes(sectionPrefix)) {
    return sectionPrefix;
  }
  return '';
}

function parseDirectDraftDocument(parsed: Record<string, Object>): NoteDraftDocument {
  const sectionValue: Object | undefined = parsed['sections'];
  if (sectionValue === undefined || !Array.isArray(sectionValue)) {
    throw new Error('direct draft sections missing');
  }
  const sections: NoteDraftSection[] = [];
  for (const item of sectionValue as Object[]) {
    const record: Record<string, Object> = item as Record<string, Object>;
    const sourceValue: Object | undefined = record['sourceIds'];
    const sourceIds: string[] = [];
    if (sourceValue !== undefined && Array.isArray(sourceValue)) {
      for (const sourceItem of sourceValue as Object[]) {
        if (typeof sourceItem === 'string') {
          sourceIds.push(sourceItem);
        }
      }
    }
    const section: NoteDraftSection = {
      id: String(record['id'] ?? ''),
      label: String(record['label'] ?? ''),
      content: String(record['content'] ?? ''),
      sourceIds: sourceIds,
      state: record['state'] === 'locked' ? 'locked' : 'generated',
      baseHash: String(record['baseHash'] ?? ''),
    };
    sections.push(section);
  }
  return {
    schemaVersion: String(parsed['schemaVersion'] ?? ''),
    title: String(parsed['title'] ?? ''),
    summary: String(parsed['summary'] ?? ''),
    subject: String(parsed['subject'] ?? ''),
    category: String(parsed['category'] ?? ''),
    chapter: String(parsed['chapter'] ?? ''),
    difficulty: Number(parsed['difficulty'] ?? 0),
    tags: [],
    sections: sections,
    instruction: parsed['instruction'] === undefined ? undefined : String(parsed['instruction']),
  };
}

export function parseDirectStandardArtifacts(
  parsed: Record<string, Object>,
  sources: SourceBundle,
): NoteGenerationStandardResult {
  const draft: NoteDraftDocument = parseDirectDraftDocument(parsed);
  if (draft.sections.length === 0) {
    throw new Error('direct draft response contains no sections');
  }
  const outlineSections: NoteGenerationOutlineSection[] = [];
  const evidence: NoteGenerationEvidenceItem[] = [];
  for (let index: number = 0; index < draft.sections.length; index += 1) {
    const section: NoteDraftSection = draft.sections[index];
    const source: SourceFragment | undefined = findDirectDraftSource(section, sources);
    const sourceIds: string[] = source === undefined ? section.sourceIds.slice(0) : [source.id];
    const mustInclude: string[] = [];
    if (draft.instruction !== undefined) {
      const requirementWords: string[] = ['定义', '公式', '步骤', '例子', '结论', '推导'];
      for (const word of requirementWords) {
        if (draft.instruction.includes(word) && (section.label.includes(word) || section.content.includes(word))) {
          mustInclude.push(word);
        }
      }
    }
    outlineSections.push({
      id: section.id,
      label: section.label,
      order: index,
      mustInclude: mustInclude,
      sourceIds: sourceIds,
    });
    if (source !== undefined) {
      const excerpt: string = findDirectDraftExcerpt(source.text, section.content);
      if (excerpt.length > 0) {
        const start: number = source.text.indexOf(excerpt);
        evidence.push({
          id: 'direct-evidence-' + section.id,
          type: classifyEvidenceType(section.label),
          claim: excerpt,
          sourceRefs: [{ sourceId: source.id, excerpt: excerpt, start: start, end: start + excerpt.length }],
          targetSectionId: section.id,
          verification: 'supported',
        });
      }
    }
  }
  const outline: NoteGenerationOutline = {
    schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION,
    sections: outlineSections,
  };
  return {
    outline: outline,
    evidence: evidence,
    draft: draft,
    verification: { status: 'supported', issues: [], checkedEvidenceIds: [], decisions: [] },
  };
}
