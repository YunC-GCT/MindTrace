/**
 * NoteDraftVerifier.ets — standard/deep 共用的只读笔记验证
 *
 * 路径: agents/src/main/ets/agents/NoteDraftVerifier.ets
 * 职责: standard/deep 共用的只读笔记验证，保持现有生成行为。
 * 依赖: common、GenerationJsonCaller
 * 数据流: DraftComposer / DeepDraftComposer → verify → 只读验证结果
 */
import {
  LlmClient,
  sourceFingerprint,
  NoteGenerationArtifactValidator,
  buildNoteVerificationJsonSchema,
} from 'common/src/main/ets/Index';
import type {
  ChatMessage,
  LlmGuardValidationResult,
  LlmCaller,
  LlmResponseFormat,
  NoteGenerationIssue,
  NoteGenerationEvidenceItem,
  EvidenceVerificationStatus,
  NoteGenerationEvidenceDecision,
  NoteGenerationStandardResult,
  NoteGenerationVerification,
  SourceBundle,
  NoteGenerationRequirement,
  CancellationToken,
} from 'common/src/main/ets/Index';
import { GenerationJsonCaller } from './GenerationJsonCaller';
import { KNOWLEDGE_TIMEOUT_MS } from './PromptBuilder';
import {
  readRecordValue,
  budgetedTokens,
  structuredResponseFormat,
  standardSourceText,
} from './GenerationDraftSupport';

export class NoteDraftVerifier {
  private readonly jsonCaller: GenerationJsonCaller;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    const client: LlmCaller = llm ?? new LlmClient();
    this.jsonCaller = new GenerationJsonCaller(client, undefined, cancellationToken);
  }

  async verify(
    result: NoteGenerationStandardResult,
    bundle: SourceBundle,
    requirement: NoteGenerationRequirement,
    tokenBudget?: number,
  ): Promise<NoteGenerationVerification> {
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Act as a read-only independent note verifier. Return JSON only. Verify the outline, draft, '
        + 'evidence, source grounding, and requirement coverage. Never rewrite, replace, repair, or generate '
        + 'outline, draft, or evidence. Use exact top-level keys: status, issues, evidenceStatuses. '
        + 'Do not use overallStatus or any other alias. Return evidenceStatuses in the same order as the supplied '
        + 'evidence array; '
        + 'each value must be supported, contradicted, or ambiguous. Never copy or invent evidence IDs. When '
        + 'evidence is empty, evidenceStatuses must be empty, but you must still verify the outline, draft, '
        + 'sources, and requirements. For evidenceStatuses, judge only whether each cited excerpt supports the '
        + 'assertion. If a source faithfully contains an implausible or factually wrong statement, keep that '
        + 'evidence status supported and report the factual problem separately in issues and the top-level status.\n'
        + 'Distinguish literal source quotations from mathematical derivations and explicitly labeled supplementary knowledge. '
        + 'Do not reject a valid derivation merely because its conclusion is not verbatim in the source. '
        + 'Check its premises, theorem applicability and intermediate steps instead. Evidence excerpts must still be verbatim and support their assertions. '
        + 'Classification confidence (including legacy fields labeled 置信度) is model metadata, not OCR accuracy or mathematical truth; '
        + 'confidence metadata alone is not grounds for a hard issue or an ambiguous evidence status. '
        + 'Hard issues include demonstrated mathematical errors, unsupported critical assumptions, misleading quotations, '
        + 'and missing conditions that prevent establishing a required answer. An explicitly conditional answer or request for clarification '
        + 'is not itself a false claim; verify that it does not hide an unconditional conclusion. '
        + 'Check normal/boundary orientation and signs, boundary versus interior extrema, and auxiliary-function calculations. '
        + 'Treat wording, optional elaboration and presentation preferences as soft issues. '
        + 'Use top-level supported when only soft issues remain; contradicted for established errors; ambiguous for unresolved critical conditions. '
        + 'Give each issue a Chinese message identifying the exact formula or claim, why it fails, and what needs correction or user confirmation; '
        + 'include sectionId and sourceId when identifiable. Do not emit generic LOGIC_GAP or GROUNDING_GAP without a concrete missing step or premise.\n'
        + 'outline=' + JSON.stringify(result.outline) + '\n'
        + 'draft=' + JSON.stringify(result.draft) + '\n'
        + 'evidenceByPosition=' + this.verifierEvidenceText(result.evidence) + '\n'
        + 'sources=' + standardSourceText(bundle) + '\n'
        + 'mustInclude=' + requirement.mustInclude.join(',') + '\n'
        + 'mustAvoid=' + requirement.mustAvoid.join(','),
    };
    const userMessage: ChatMessage = {
      role: 'user',
      content: 'Verify the complete note and classify each evidence assertion by array position.',
    };
    const messages: ChatMessage[] = [systemMessage, userMessage];
    let modelVerification: NoteGenerationVerification;
    try {
      const parsed: Record<string, Object> = await this.jsonCaller.callJson(
        messages,
        {
          label: 'independent verifier',
          maxTokens: budgetedTokens(tokenBudget, 2600),
          timeoutMs: KNOWLEDGE_TIMEOUT_MS,
          responseFormat: this.verificationResponseFormat(result.evidence),
        },
        (json: Record<string, Object>): LlmGuardValidationResult => {
          const issues: string[] = [];
          const statusesValue: Object | undefined = readRecordValue(json, 'evidenceStatuses');
          if (statusesValue !== undefined && !Array.isArray(statusesValue)) {
            issues.push('evidenceStatuses must be an array');
          }
          const issuesValue: Object | undefined = readRecordValue(json, 'issues');
          if (issuesValue !== undefined && !Array.isArray(issuesValue)) {
            issues.push('issues must be an array');
          }
          return { ok: issues.length === 0, issues: issues };
        },
        (json: Record<string, Object>): string[] =>
          this.validateIndependentVerifierJson(json, result.evidence),
      );
      modelVerification = this.parseVerification(parsed, result.evidence);
    } catch (e) {
      modelVerification = { status: 'ambiguous', issues: [{
        stage: 'verifier', code: 'VERIFIER_UNAVAILABLE', severity: 'hard',
        message: 'independent verifier did not return a complete result', repairable: false,
      }], checkedEvidenceIds: [], decisions: [] };
    }
    const local: NoteGenerationVerification = new NoteGenerationArtifactValidator().verify(
      result.outline,
      result.evidence,
      result.draft,
      bundle,
      requirement,
    );
    return this.combineVerification(modelVerification, local);
  }

  private combineVerification(
    model: NoteGenerationVerification,
    local: NoteGenerationVerification,
  ): NoteGenerationVerification {
    let status: EvidenceVerificationStatus = model.status;
    if (local.status === 'contradicted') {
      status = 'contradicted';
    } else if (local.status === 'ambiguous' && status === 'supported') {
      status = 'ambiguous';
    }
    const issues: NoteGenerationIssue[] = [];
    for (const issue of model.issues) {
      issues.push(issue);
    }
    for (const issue of local.issues) {
      issues.push(issue);
    }
    const decisions: NoteGenerationEvidenceDecision[] = [];
    for (const decision of model.decisions) {
      decisions.push(decision);
    }
    for (const decision of local.decisions) {
      let exists: boolean = false;
      for (const existing of decisions) {
        if (existing.evidenceId === decision.evidenceId) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        decisions.push(decision);
      }
    }
    return { status: status, issues: issues, checkedEvidenceIds: model.checkedEvidenceIds, decisions: decisions };
  }

  private verifierEvidenceText(evidence: NoteGenerationEvidenceItem[]): string {
    const lines: string[] = [];
    let index: number = 0;
    for (const item of evidence) {
      lines.push('[' + index.toString() + '] origin=' + item.origin
        + '; assertionType=' + item.assertion.type
        + '; targetSectionId=' + item.assertion.targetSectionId
        + '; assertionText=' + JSON.stringify(item.assertion.text));
      for (const ref of item.sourceRefs) {
        lines.push('  sourceRef sourceId=' + ref.sourceId
          + '; sourceFingerprint=' + ref.sourceFingerprint
          + '; start=' + ref.start.toString()
          + '; end=' + ref.end.toString()
          + '; excerpt=' + JSON.stringify(ref.excerpt));
      }
      index += 1;
    }
    return lines.length === 0 ? '[]' : lines.join('\n');
  }

  private readVerifierStatusValue(json: Record<string, Object>): Object | undefined {
    const statusValue: Object | undefined = readRecordValue(json, 'status');
    if (statusValue !== undefined) {
      return statusValue;
    }
    return readRecordValue(json, 'overallStatus');
  }

  private readOptionalString(parsed: Record<string, Object>, key: string): string | undefined {
    const value: Object | undefined = readRecordValue(parsed, key);
    return value === undefined ? undefined : String(value);
  }

  // 入参由 seam 预解析并保证顶层对象, 空文分支不再存在 (2026-09-19 统一 JSON 生命周期)
  private parseVerification(
    parsed: Record<string, Object>,
    evidence: NoteGenerationEvidenceItem[],
  ): NoteGenerationVerification {
    const statusValue: string = String(this.readVerifierStatusValue(parsed) ?? 'ambiguous');
    let status: EvidenceVerificationStatus = statusValue === 'supported'
      ? 'supported' : statusValue === 'contradicted' ? 'contradicted' : 'ambiguous';
    const decisions: NoteGenerationEvidenceDecision[] = [];
    const checkedEvidenceIds: string[] = [];
    const statusesValue: Object | undefined = readRecordValue(parsed, 'evidenceStatuses');
    if (statusesValue !== undefined && Array.isArray(statusesValue)) {
      const statuses: Object[] = statusesValue as Object[];
      for (let index: number = 0; index < evidence.length; index += 1) {
        const itemStatus: string = String(statuses[index] ?? 'ambiguous');
        const decisionStatus: EvidenceVerificationStatus = itemStatus === 'supported'
          ? 'supported' : itemStatus === 'contradicted' ? 'contradicted' : 'ambiguous';
        decisions.push({
          evidenceId: evidence[index].id,
          status: decisionStatus,
        });
        checkedEvidenceIds.push(evidence[index].id);
      }
    }
    const issues: NoteGenerationIssue[] = [];
    const issueValue: Object | undefined = readRecordValue(parsed, 'issues');
    if (issueValue !== undefined && Array.isArray(issueValue)) {
      for (const item of issueValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        const severityValue: string = String(readRecordValue(record, 'severity') ?? 'hard');
        const severity: 'hard' | 'soft' = severityValue === 'soft' ? 'soft' : 'hard';
        issues.push({
          stage: 'verifier',
          code: String(readRecordValue(record, 'code') ?? 'VERIFIER_PROCESS_ISSUE'),
          severity: severity,
          message: String(readRecordValue(record, 'message') ?? 'verifier reported a process issue'),
          repairable: false,
          sourceId: this.readOptionalString(record, 'sourceId'),
          sectionId: this.readOptionalString(record, 'sectionId'),
        });
      }
    }
    for (let index: number = 0; index < decisions.length; index += 1) {
      const decision: NoteGenerationEvidenceDecision = decisions[index];
      const sectionId: string = evidence[index].assertion.targetSectionId;
      if (decision.status === 'contradicted') {
        status = 'contradicted';
        issues.push({
          stage: 'verifier', code: 'EVIDENCE_CONTRADICTED', severity: 'hard',
          message: 'the assertion is contradicted by its cited source', repairable: false, sectionId: sectionId,
        });
      } else if (decision.status === 'ambiguous') {
        if (status === 'supported') {
          status = 'ambiguous';
        }
        issues.push({
          stage: 'verifier', code: 'EVIDENCE_AMBIGUOUS', severity: 'hard',
          message: 'the cited source does not unambiguously support the assertion', repairable: false,
          sectionId: sectionId,
        });
      }
    }
    let hasHardIssue: boolean = false;
    for (const issue of issues) {
      if (issue.severity === 'hard') {
        hasHardIssue = true;
        break;
      }
    }
    if (!hasHardIssue && status === 'contradicted') {
      issues.push({
        stage: 'verifier', code: 'NOTE_CONTRADICTED', severity: 'hard',
        message: 'the verifier found the note contradicted by the supplied sources or requirements',
        repairable: false,
      });
    } else if (!hasHardIssue && status === 'ambiguous') {
      issues.push({
        stage: 'verifier', code: 'NOTE_AMBIGUOUS', severity: 'hard',
        message: 'the verifier could not establish that the complete note is supported', repairable: false,
      });
    }
    return {
      status: status,
      issues: issues,
      checkedEvidenceIds: checkedEvidenceIds,
      decisions: decisions,
    };
  }

  private validateIndependentVerifierJson(
    json: Record<string, Object>,
    evidence: NoteGenerationEvidenceItem[],
  ): string[] {
    const issues: string[] = [];
    const statusValue: Object | undefined = this.readVerifierStatusValue(json);
    if (statusValue !== 'supported' && statusValue !== 'contradicted' && statusValue !== 'ambiguous') {
      issues.push('status must be supported, contradicted, or ambiguous');
    }
    const verifierIssuesValue: Object | undefined = readRecordValue(json, 'issues');
    if (verifierIssuesValue === undefined || !Array.isArray(verifierIssuesValue)) {
      issues.push('issues must be an array');
    } else {
      for (const issueValue of verifierIssuesValue as Object[]) {
        if (issueValue === null || typeof issueValue !== 'object' || Array.isArray(issueValue)) {
          issues.push('each verifier issue must be an object');
          continue;
        }
        const issue: Record<string, Object> = issueValue as Record<string, Object>;
        const codeValue: Object | undefined = readRecordValue(issue, 'code');
        const severityValue: Object | undefined = readRecordValue(issue, 'severity');
        const messageValue: Object | undefined = readRecordValue(issue, 'message');
        if (typeof codeValue !== 'string' || codeValue.trim().length === 0) {
          issues.push('each verifier issue must include a non-empty code');
        }
        if (severityValue !== 'hard' && severityValue !== 'soft') {
          issues.push('each verifier issue severity must be hard or soft');
        }
        if (typeof messageValue !== 'string' || messageValue.trim().length === 0) {
          issues.push('each verifier issue must include a non-empty message');
        }
      }
    }
    const statusesValue: Object | undefined = readRecordValue(json, 'evidenceStatuses');
    if (statusesValue === undefined || !Array.isArray(statusesValue)) {
      return ['evidenceStatuses must be an array'];
    }
    const statuses: Object[] = statusesValue as Object[];
    if (statuses.length !== evidence.length) {
      issues.push('evidenceStatuses must contain one status for every evidence item');
    }
    for (const statusValue of statuses) {
      if (statusValue !== 'supported' && statusValue !== 'contradicted' && statusValue !== 'ambiguous') {
        issues.push('evidence status must be supported, contradicted, or ambiguous');
      }
    }
    return issues;
  }

  private verificationResponseFormat(evidence: NoteGenerationEvidenceItem[]): LlmResponseFormat {
    const schemaText: string = buildNoteVerificationJsonSchema(evidence.length);
    return structuredResponseFormat(schemaText, 'mindtrace_note_verification');
  }
}
