/**
 * IncrementalPatchComposer.ets — 计划约束下的增量 replace patch 生成
 *
 * 路径: agents/src/main/ets/agents/IncrementalPatchComposer.ets
 * 职责: 计划约束下的增量 replace patch 生成，保持现有生成行为。
 * 依赖: common、GenerationJsonCaller
 * 数据流: KnowledgeModel → compose（计划筛选 / JSON 校验）→ IncrementalPatchResponse
 */
import { LlmClient } from 'common/src/main/ets/Index';
import type {
  ChatMessage,
  LlmGuardValidationResult,
  LlmCaller,
  NoteGenerationRequest,
  IncrementalPlan,
  IncrementalSection,
  IncrementalPatch,
  IncrementalPatchResponse,
  SourceFragment,
  CancellationToken,
} from 'common/src/main/ets/Index';
import { GenerationJsonCaller } from './GenerationJsonCaller';
import { KNOWLEDGE_TIMEOUT_MS } from './PromptBuilder';
import { readRecordValue, readStringArray, budgetedRequestTokens } from './GenerationDraftSupport';

export class IncrementalPatchComposer {
  private readonly jsonCaller: GenerationJsonCaller;

  constructor(llm?: LlmCaller, cancellationToken?: CancellationToken) {
    const client: LlmCaller = llm ?? new LlmClient();
    this.jsonCaller = new GenerationJsonCaller(client, undefined, cancellationToken);
  }

  async compose(
    request: NoteGenerationRequest,
    plan: IncrementalPlan,
    sections: IncrementalSection[],
    sources: SourceFragment[],
  ): Promise<IncrementalPatchResponse> {
    const targetSections: IncrementalSection[] = [];
    for (const section of sections) {
      if (plan.targetSectionIds.includes(section.id)) {
        targetSections.push(section);
      }
    }
    const relevantSources: string[] = [];
    for (const source of sources) {
      if (plan.relevantSourceIds.includes(source.id)) {
        relevantSources.push('[source:' + source.id + '] ' + source.text);
      }
    }
    const systemMessage: ChatMessage = {
      role: 'system',
      content: 'Return JSON only with patches. Repair only the requested target sections. '
        + 'Each patch must have sectionId, operation=replace, content and sourceIds. '
        + 'never return a full document, metadata, or an unplanned section. '
        + 'instruction=' + request.instruction + '\n'
        + 'targetSectionIds=' + plan.targetSectionIds.join(',') + '\n'
        + 'targets=' + JSON.stringify(targetSections) + '\n'
        + 'relevant sources=\n' + relevantSources.join('\n'),
    };
    const parsed: Record<string, Object> = await this.jsonCaller.callJson(
      [systemMessage, { role: 'user', content: 'Return section RepairPatch objects only.' }],
      {
        label: 'incremental repair',
        maxTokens: budgetedRequestTokens(request, 2400),
        timeoutMs: KNOWLEDGE_TIMEOUT_MS,
        responseFormat: { type: 'json_object' },
      },
      (json: Record<string, Object>): LlmGuardValidationResult => {
        const value: Object | undefined = readRecordValue(json, 'patches');
        if (value === undefined || !Array.isArray(value)) {
          return { ok: false, issues: ['patches must be an array'] };
        }
        return { ok: true, issues: [] };
      },
      (json: Record<string, Object>): string[] => {
        const value: Object | undefined = readRecordValue(json, 'patches');
        if (value === undefined || !Array.isArray(value)) {
          return ['patches must be an array'];
        }
        const issues: string[] = [];
        for (const item of value as Object[]) {
          const record: Record<string, Object> = item as Record<string, Object>;
          const sectionId: string = String(readRecordValue(record, 'sectionId') ?? '');
          if (!plan.targetSectionIds.includes(sectionId)
            || readRecordValue(record, 'operation') !== 'replace') {
            issues.push('incremental repair contains an unplanned patch: ' + sectionId);
          }
        }
        return issues;
      },
    );
    const patches: IncrementalPatch[] = [];
    const patchValue: Object | undefined = readRecordValue(parsed, 'patches');
    if (patchValue !== undefined && Array.isArray(patchValue)) {
      for (const item of patchValue as Object[]) {
        const record: Record<string, Object> = item as Record<string, Object>;
        patches.push({
          sectionId: String(readRecordValue(record, 'sectionId') ?? ''),
          operation: 'replace',
          content: String(readRecordValue(record, 'content') ?? ''),
          sourceIds: readStringArray(readRecordValue(record, 'sourceIds')),
        });
      }
    }
    return { patches: patches };
  }
}
