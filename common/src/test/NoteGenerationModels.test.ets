/**
 * NoteGenerationModels.test.ets — standard 路线契约归一化行为测试
 *
 * 路径: common/src/test/NoteGenerationModels.test.ets
 * 职责: ① parseDirectStandardArtifacts 直解析路径保留模型返回的 tags
 *   (存在则保留 / 缺省为空 / 非字符串项过滤 / 全链路 draft 携带)
 *   ② standard 契约归一化 (2026-09-19 P0-3): normalizeDraftCategory
 *   学科级标签回退、normalizeOutline 空 sourceIds 回填
 *   ③ deep section 契约归一化 (2026-09-19 P0-4): normalizeDeepSectionDraft
 *   sourceIds 管线代算、category 映射、MM-MD auto-fix 采用
 * 依赖: @ohos/hypium, common Index 导出的解析函数与类型
 *
 * 数据流:
 *   JSON 文本 → JSON.parse → parseDirectStandardArtifacts → result.draft.tags 断言
 *
 * 背景: P1-B 修复 — parseDirectDraftDocument 原先硬编码 tags: [], 模型返回的
 * tags 被静默丢弃; 修复后镜像 sourceIds 的内联字符串收集模式读取 parsed['tags']。
 *
 * ArkTS 1.1 strict 适配:
 *   - Record 构造沿用生产同款 JSON.parse(...) as Record<string, Object> 模式
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  parseDirectStandardArtifacts,
  normalizeDraftCategory,
  normalizeDraftSummary,
  normalizeLightDraft,
  normalizeDeepSectionDraft,
  normalizeDraftSectionLabel,
  normalizeDraftDifficulty,
  buildPipelineEvidence,
  normalizeEvidenceItems,
  normalizeOutline,
  validateDraftDocument,
  buildDeepOutline,
  segmentSourceBundle,
  validateDeepOutline,
  NOTE_DRAFT_SCHEMA_VERSION,
  NOTE_OUTLINE_SCHEMA_VERSION,
  SourceBundle,
  SourceFragment,
} from '../main/ets/Index';
import { validateStandardArtifacts } from '../main/ets/models/NoteGenerationModels';
import type {
  NoteGenerationStandardResult,
  NoteGenerationOutline,
  NoteGenerationSegment,
  NoteGenerationOutlineSection,
  NoteGenerationRequirement,
  NoteGenerationEvidenceItem,
  NoteGenerationIssue,
  NoteDraftDocument,
} from '../main/ets/Index';

const DIRECT_DRAFT_WITH_TAGS: string = '{'
  + '"schemaVersion":"mm-note-draft-v1",'
  + '"title":"微分中值定理",'
  + '"summary":"连续+可导 ⇒ 存在 ξ",'
  + '"subject":"高等数学",'
  + '"category":"定理",'
  + '"chapter":"微分中值定理",'
  + '"difficulty":2,'
  + '"tags":["微分学","中值定理"],'
  + '"sections":[{"id":"s1","label":"定义","content":"若 f 在 [a,b] 连续...","sourceIds":["src-1"],"state":"generated","baseHash":""}]'
  + '}';

const DIRECT_DRAFT_MIXED_TAGS: string = '{'
  + '"schemaVersion":"mm-note-draft-v1",'
  + '"title":"洛必达法则",'
  + '"summary":"0/0 型极限",'
  + '"subject":"高等数学",'
  + '"category":"公式",'
  + '"chapter":"洛必达法则",'
  + '"difficulty":1,'
  + '"tags":["极限",123,"导数"],'
  + '"sections":[{"id":"s1","label":"公式","content":"lim f/g = lim f\'/g\'","sourceIds":["src-1"],"state":"generated","baseHash":""}]'
  + '}';

function sources(): SourceBundle {
  const fragment: SourceFragment = {
    id: 'src-1',
    kind: 'summary',
    originId: 'origin-1',
    sequence: 0,
    fingerprint: 'fp-1',
    text: '若 f 在 [a,b] 连续且在 (a,b) 可导, 则存在 ξ ∈ (a,b) 使 f\'(ξ) = (f(b)-f(a))/(b-a)',
  };
  const bundle: SourceBundle = { fragments: [fragment] };
  return bundle;
}

function parseDirect(jsonText: string): NoteGenerationStandardResult {
  const parsed: Record<string, Object> = JSON.parse(jsonText) as Record<string, Object>;
  return parseDirectStandardArtifacts(parsed, sources());
}

export default function noteGenerationModelsTest(): void {
  describe('NoteGenerationModels.direct_draft_tags', () => {
    it('direct_draft_preserves_model_tags', 0, () => {
      const result: NoteGenerationStandardResult = parseDirect(DIRECT_DRAFT_WITH_TAGS);
      expect(result.draft.tags.length).assertEqual(2);
      expect(result.draft.tags[0]).assertEqual('微分学');
      expect(result.draft.tags[1]).assertEqual('中值定理');
    });

    it('direct_draft_without_tags_defaults_to_empty', 0, () => {
      const jsonWithoutTags: string = DIRECT_DRAFT_WITH_TAGS.replace('"tags":["微分学","中值定理"],', '');
      const result: NoteGenerationStandardResult = parseDirect(jsonWithoutTags);
      expect(result.draft.tags.length).assertEqual(0);
    });

    it('direct_draft_filters_non_string_tag_entries', 0, () => {
      const result: NoteGenerationStandardResult = parseDirect(DIRECT_DRAFT_MIXED_TAGS);
      expect(result.draft.tags.length).assertEqual(2);
      expect(result.draft.tags[0]).assertEqual('极限');
      expect(result.draft.tags[1]).assertEqual('导数');
    });

    it('direct_standard_result_draft_carries_tags_end_to_end', 0, () => {
      const result: NoteGenerationStandardResult = parseDirect(DIRECT_DRAFT_WITH_TAGS);
      expect(result.draft.title).assertEqual('微分中值定理');
      expect(result.draft.tags.includes('中值定理')).assertTrue();
      expect(result.draft.sections.length).assertEqual(1);
    });
  });

  describe('NoteGenerationModels.standard_contract_normalization', () => {
    it('section_labels_hide_internal_ids', 0, () => {
      expect(normalizeDraftSectionLabel('', 0)).assertEqual('核心内容');
      expect(normalizeDraftSectionLabel('section-item-811c9dc5', 0)).assertEqual('核心内容');
      expect(normalizeDraftSectionLabel('section-item-811c9dc5-1', 1)).assertEqual('补充内容2');
      expect(normalizeDraftSectionLabel('定义', 0)).assertEqual('定义');
    });

    it('draft_difficulty_stays_within_four_levels', 0, () => {
      expect(normalizeDraftDifficulty(0)).assertEqual(1);
      expect(normalizeDraftDifficulty(1)).assertEqual(1);
      expect(normalizeDraftDifficulty(4)).assertEqual(4);
      expect(normalizeDraftDifficulty(5)).assertEqual(2);
    });

    it('draft_summary_is_limited_and_keeps_short_inline_formula', 0, () => {
      const summary: string = normalizeDraftSummary(
        '结论是 $a>0$ 时函数递增，且该结论适用于连续可导函数的常见判断场景。',
      );
      expect(summary.length <= 60).assertTrue();
      expect(summary).assertContain('$a>0$');
      expect(validateDraftDocument({
        schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
        title: '单调性',
        summary: summary,
        subject: '数学分析',
        category: '概念',
        chapter: '',
        difficulty: 2,
        tags: [],
        sections: [{
          id: 'section-1',
          label: '定义',
          content: '函数在区间上递增。',
          sourceIds: [],
          state: 'generated',
          baseHash: '',
        }],
      }).length).assertEqual(0);
    });

    it('light_draft_backfills_empty_section_from_source', 0, () => {
      const draft: NoteDraftDocument = {
        schemaVersion: '1.0',
        title: '单调性',
        summary: '',
        subject: '',
        category: '数学分析',
        chapter: '',
        difficulty: 0,
        tags: [],
        sections: [{
          id: '',
          label: '',
          content: '',
          sourceIds: [],
          state: 'generated',
          baseHash: '',
        }],
      };
      const bundle: SourceBundle = {
        fragments: [{
          id: 'src-light',
          kind: 'conversation',
          originId: 'origin-light',
          sequence: 0,
          fingerprint: 'fp-light',
          text: '单调性描述的是函数值随着自变量变化而变化的趋势。',
        }],
      };
      const normalized: NoteDraftDocument = normalizeLightDraft(draft, bundle);
      expect(normalized.schemaVersion).assertEqual(NOTE_DRAFT_SCHEMA_VERSION);
      expect(normalized.subject).assertEqual('其它');
      expect(normalized.category).assertEqual('概念');
      expect(normalized.difficulty).assertEqual(1);
      expect(normalized.sections[0].id).assertEqual('section-1');
      expect(normalized.sections[0].label).assertEqual('核心内容');
      expect(normalized.sections[0].content).assertContain('单调性描述的是函数值');
      expect(normalized.sections[0].sourceIds[0]).assertEqual('src-light');
      const issues: NoteGenerationIssue[] = validateDraftDocument(normalized, ['src-light']);
      expect(issues.length).assertEqual(0);
    });

    it('light_draft_replaces_internal_section_label', 0, () => {
      const draft: NoteDraftDocument = {
        schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
        title: '单调性',
        summary: '',
        subject: '数学分析',
        category: '概念',
        chapter: '',
        difficulty: 2,
        tags: [],
        sections: [{
          id: 'section-item-811c9dc5',
          label: 'section-item-811c9dc5',
          content: '函数单调性定义。',
          sourceIds: ['src-light'],
          state: 'generated',
          baseHash: '',
        }],
      };
      const normalized: NoteDraftDocument = normalizeLightDraft(draft, bundle);
      expect(normalized.sections[0].id).assertEqual('section-item-811c9dc5');
      expect(normalized.sections[0].label).assertEqual('核心内容');
    });

    it('pipeline_evidence_builds_source_anchor_for_empty_model_evidence', 0, () => {
      const outline: NoteGenerationOutline = {
        schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION,
        sections: [{
          id: 'sec-definition',
          label: '定义',
          order: 0,
          mustInclude: [],
          sourceIds: ['src-evidence'],
        }],
      };
      const bundle: SourceBundle = {
        fragments: [{
          id: 'src-evidence',
          kind: 'conversation',
          originId: 'origin-evidence',
          sequence: 0,
          fingerprint: 'fp-evidence',
          text: '连续函数是指自变量发生很小变化时，函数值也只发生很小变化。',
        }],
      };
      const evidence: NoteGenerationEvidenceItem[] = buildPipelineEvidence(outline, bundle);
      expect(evidence.length).assertEqual(1);
      expect(evidence[0].origin).assertEqual('pipeline');
      expect(evidence[0].targetSectionId).assertEqual('sec-definition');
      expect(evidence[0].sourceRefs[0].sourceId).assertEqual('src-evidence');
      expect(evidence[0].sourceRefs[0].excerpt).assertContain('连续函数');
    });

    it('category_subject_level_label_falls_back_to_concept', 0, () => {
      // 2026-09-19: 模型返回学科级标签 ("概率论与统计学") 原判 CATEGORY_INVALID (hard) 判死
      expect(normalizeDraftCategory('概率论与统计学')).assertEqual('概念');
      expect(normalizeDraftCategory('高中数学')).assertEqual('概念');
    });

    it('category_prefix_matches_map_to_enum', 0, () => {
      expect(normalizeDraftCategory('证明')).assertEqual('证明题');
      expect(normalizeDraftCategory('计算题')).assertEqual('计算题');
      expect(normalizeDraftCategory('几何定理')).assertEqual('定理');
    });

    it('category_valid_values_pass_through_unchanged', 0, () => {
      expect(normalizeDraftCategory('概念')).assertEqual('概念');
      expect(normalizeDraftCategory('  公式  ')).assertEqual('公式');
    });

    it('outline_backfills_all_sources_when_section_source_ids_empty', 0, () => {
      // 2026-09-19: 模型常省略 outline section 的 sourceIds → 回填全部源 id
      const outline: NoteGenerationOutline = {
        schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION,
        sections: [{
          id: 'raw-1', label: '定义与记号', order: 0, mustInclude: [], sourceIds: [],
        }],
      };
      const normalized: NoteGenerationOutline = normalizeOutline(outline, ['src-1', 'src-2']);
      expect(normalized.sections[0].sourceIds.length).assertEqual(2);
      expect(normalized.sections[0].sourceIds.includes('src-1')).assertTrue();
      expect(normalized.sections[0].sourceIds.includes('src-2')).assertTrue();
    });

    it('outline_keeps_only_valid_provided_source_ids', 0, () => {
      const outline: NoteGenerationOutline = {
        schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION,
        sections: [{
          id: 'raw-1', label: '定义与记号', order: 3, mustInclude: [],
          sourceIds: ['src-2', 'src-unknown'],
        }],
      };
      const normalized: NoteGenerationOutline = normalizeOutline(outline, ['src-1', 'src-2']);
      expect(normalized.sections[0].sourceIds.length).assertEqual(1);
      expect(normalized.sections[0].sourceIds[0]).assertEqual('src-2');
      expect(normalized.sections[0].order).assertEqual(0);
    });
  });

  describe('NoteGenerationModels.deep_section_normalization', () => {
    function deepOutlineSection(): NoteGenerationOutlineSection {
      return {
        id: 'sec-1', label: '定义与记号', order: 0, mustInclude: [],
        sourceIds: ['src-1', 'src-2'],
      };
    }

    function deepRawDraft(content: string): NoteDraftDocument {
      return {
        schemaVersion: 'stale-version',
        title: '正态分布',
        summary: '连续型随机变量的典型分布',
        subject: '',
        category: '概率论与统计学',
        chapter: '概率',
        difficulty: 2,
        tags: ['概率'],
        sections: [{
          id: '', label: '', content: content, sourceIds: [],
          state: 'generated', baseHash: '',
        }],
      };
    }

    it('deep_section_backfills_pipeline_fields_and_passes_validation', 0, () => {
      // 2026-09-19 P0-4: LLM 原始输出 (空 sourceIds / 学科 category / 空 subject /
      // 旧 schemaVersion) 直接校验 3 次重试全灭; 归一化后 validateDraftDocument 全过
      const normalized: NoteDraftDocument = normalizeDeepSectionDraft(deepRawDraft('密度函数 $f(x)$ 如图'), deepOutlineSection());
      expect(normalized.sections[0].sourceIds.length).assertEqual(2);
      expect(normalized.sections[0].sourceIds[0]).assertEqual('src-1');
      expect(normalized.schemaVersion).assertEqual(NOTE_DRAFT_SCHEMA_VERSION);
      expect(normalized.subject).assertEqual('其它');
      expect(normalized.category).assertEqual('概念');
      expect(normalized.sections[0].id).assertEqual('sec-1');
      expect(normalized.sections[0].label).assertEqual('定义与记号');
      const issues = validateDraftDocument(normalized, deepOutlineSection().sourceIds);
      expect(issues.length).assertEqual(0);
    });

    it('deep_section_adopts_mm_md_autofix_content', 0, () => {
      const normalized: NoteDraftDocument = normalizeDeepSectionDraft(deepRawDraft('密度函数 \\(f(x)\\) 如图'), deepOutlineSection());
      expect(normalized.sections[0].content.includes('$f(x)$')).assertTrue();
      expect(normalized.sections[0].content.includes('\\(')).assertFalse();
    });

    it('draft_validation_accepts_recoverable_mm_md_after_normalization', 0, () => {
      const raw: NoteDraftDocument = deepRawDraft('密度函数 \\(f(x)\\) 如图');
      const issues = validateDraftDocument(raw, deepOutlineSection().sourceIds, true);
      expect(issues.length).assertEqual(0);
    });

    it('draft_validation_reports_unrecoverable_mm_md_reason', 0, () => {
      const raw: NoteDraftDocument = deepRawDraft('密度函数 $f(x) 如图');
      const issues = validateDraftDocument(raw, deepOutlineSection().sourceIds, true);
      expect(issues.length).assertEqual(1);
      expect(issues[0].code).assertEqual('MM_MD_INVALID');
      expect(issues[0].message).assertContain('unclosed_inline_delimiter');
    });

    it('deep_section_adopts_safe_html_autofix_content', 0, () => {
      const raw: string = '强调 <b>bold</b> 文本';
      const normalized: NoteDraftDocument = normalizeDeepSectionDraft(deepRawDraft(raw), deepOutlineSection());
      expect(normalized.sections[0].content.indexOf('<b>')).assertEqual(-1);
      expect(normalized.sections[0].content).assertContain('bold');
      const issues: NoteGenerationIssue[] = validateDraftDocument(normalized, deepOutlineSection().sourceIds, true);
      expect(issues.length).assertEqual(0);
    });

    it('deep_section_replaces_internal_section_label', 0, () => {
      const raw: NoteDraftDocument = deepRawDraft('密度函数定义。');
      raw.sections[0].label = 'section-item-811c9dc5';
      const normalized: NoteDraftDocument = normalizeDeepSectionDraft(raw, deepOutlineSection());
      expect(normalized.sections[0].id).assertEqual('section-item-811c9dc5');
      expect(normalized.sections[0].label).assertEqual('核心内容');
    });

    it('deep_section_normalization_keeps_valid_metadata_unchanged', 0, () => {
      const raw: NoteDraftDocument = {
        schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
        title: '微分中值定理',
        summary: '连续且可导则存在中值点',
        subject: '高等数学',
        category: '定理',
        chapter: '微分学',
        difficulty: 3,
        tags: ['中值定理'],
        sections: [{
          id: 's9', label: '定理内容', content: '若 f 连续且可导, 则存在 ξ。', sourceIds: ['src-2'],
          state: 'generated', baseHash: 'hash-1',
        }],
      };
      const normalized: NoteDraftDocument = normalizeDeepSectionDraft(raw, deepOutlineSection());
      expect(normalized.title).assertEqual('微分中值定理');
      expect(normalized.subject).assertEqual('高等数学');
      expect(normalized.category).assertEqual('定理');
      expect(normalized.sections[0].id).assertEqual('s9');
      expect(normalized.sections[0].label).assertEqual('定理内容');
      expect(normalized.sections[0].baseHash).assertEqual('hash-1');
      expect(normalized.sections[0].sourceIds.length).assertEqual(2);
    });
  });

  describe('NoteGenerationModels.deep_outline_cap', () => {
    function emptyRequirement(): NoteGenerationRequirement {
      return { detailLevel: 'normal', mustInclude: [], mustAvoid: [], targetSectionIds: [], preserveUserEdits: true };
    }

    function multiSegmentBundle(count: number): SourceBundle {
      const lines: string[] = [];
      for (let index: number = 0; index < count; index += 1) {
        lines.push('这是第' + (index + 1).toString() + '段原始材料文字');
        lines.push('');
      }
      const fragment: SourceFragment = {
        id: 'src-multi',
        kind: 'conversation',
        originId: 'origin-multi',
        sequence: 0,
        fingerprint: 'fp-multi',
        text: lines.join('\n'),
      };
      const bundle: SourceBundle = { fragments: [fragment] };
      return bundle;
    }

    it('deep_outline_caps_sections_and_merges_tail_segments', 0, () => {
      // 2026-09-20 P0-5: 17k 字符对话实录被切成 347 节 = 347 次串行 LLM 调用
      // (冒烟实测 5 分钟烧 765 万 prompt tokens); 封顶 8 节, 尾部合并
      const bundle: SourceBundle = multiSegmentBundle(30);
      const segments: NoteGenerationSegment[] = segmentSourceBundle(bundle);
      expect(segments.length).assertEqual(30);
      const outline: NoteGenerationOutline = buildDeepOutline(segments, emptyRequirement());
      expect(outline.sections.length).assertEqual(8);
      const lastSegmentIds: string[] = outline.sections[7].segmentIds ?? [];
      expect(lastSegmentIds.length).assertEqual(23);
      const issues = validateDeepOutline(outline, segments, bundle, emptyRequirement());
      expect(issues.length).assertEqual(0);
    });

    it('deep_outline_keeps_small_segment_counts_unchanged', 0, () => {
      const bundle: SourceBundle = multiSegmentBundle(3);
      const segments: NoteGenerationSegment[] = segmentSourceBundle(bundle);
      const outline: NoteGenerationOutline = buildDeepOutline(segments, emptyRequirement());
      expect(outline.sections.length).assertEqual(3);
      expect((outline.sections[0].segmentIds ?? []).length).assertEqual(1);
    });
  });

  // 2026-09-20 P0-6: standard 证据契约归一化 — round 0 空壳 / round 1 空 ref +
  // 重复 id 实测后, evidence 修复职责从"重试要求 LLM"转为"管线代算"
  describe('NoteGenerationModels.standard_evidence_normalization', () => {
    function stdBundle(): SourceBundle {
      const fragment: SourceFragment = {
        id: 'src-std',
        kind: 'conversation',
        originId: 'origin-std',
        sequence: 0,
        fingerprint: 'fp-std',
        text: '若 X 服从正态分布, 则其概率密度函数关于均值对称。',
      };
      const bundle: SourceBundle = { fragments: [fragment] };
      return bundle;
    }

    function stdOutline(): NoteGenerationOutline {
      return {
        schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION,
        sections: [{ id: 'sec-1', label: '定义', order: 0, mustInclude: [], sourceIds: ['src-std'] }],
      };
    }

    function stdEvidence(
      id: string,
      claim: string,
      sourceId: string,
      excerpt: string,
    ): NoteGenerationEvidenceItem {
      return {
        id: id,
        type: 'definition',
        claim: claim,
        sourceRefs: [{ sourceId: sourceId, excerpt: excerpt, start: 0, end: excerpt.length }],
        targetSectionId: 'sec-1',
        verification: 'supported',
      };
    }

    function stdDraft(): NoteDraftDocument {
      return {
        schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
        title: '正态分布',
        summary: '概率密度关于均值对称',
        subject: '高等数学',
        category: '概念',
        chapter: '概率论',
        difficulty: 2,
        tags: ['正态分布'],
        sections: [{
          id: 'sec-1', label: '定义', content: '概率密度函数关于均值对称。',
          sourceIds: ['src-std'], state: 'generated', baseHash: '',
        }],
        instruction: '保存这条笔记',
      };
    }

    function stdRequirement(): NoteGenerationRequirement {
      return { detailLevel: 'normal', mustInclude: [], mustAvoid: [], targetSectionIds: [], preserveUserEdits: true };
    }

    function sectionMap(): Map<string, string[]> {
      const map: Map<string, string[]> = new Map<string, string[]>();
      map.set('sec-1', ['src-std']);
      return map;
    }

    it('normalize_evidence_drops_blank_stubs_and_dedupes_ids', 0, () => {
      const blankStub: NoteGenerationEvidenceItem = {
        id: '', type: 'claim', claim: '',
        sourceRefs: [{ sourceId: '', excerpt: '', start: 0, end: 0 }],
        targetSectionId: 'sec-1', verification: 'supported',
      };
      const backfilled: NoteGenerationEvidenceItem = stdEvidence('', '密度函数对称', 'src-std', '');
      const duplicate: NoteGenerationEvidenceItem = stdEvidence('evidence-1', '均值为 μ', 'conversation:run-1', '');
      const normalized: NoteGenerationEvidenceItem[] =
        normalizeEvidenceItems([blankStub, backfilled, duplicate], ['src-std'], sectionMap());
      expect(normalized.length).assertEqual(2);
      expect(normalized[0].id).assertEqual('evidence-1');
      expect(normalized[1].id).assertEqual('evidence-1-2');
      expect(normalized[1].sourceRefs[0].sourceId).assertEqual('src-std');
    });

    it('normalize_evidence_repairs_invalid_ref_to_section_source', 0, () => {
      const invalidRef: NoteGenerationEvidenceItem = {
        id: 'ev-keep', type: 'claim', claim: '正态分布是连续分布',
        sourceRefs: [{ sourceId: 'conversation:run-9', excerpt: '', start: 0, end: 0 }],
        targetSectionId: 'sec-1', verification: 'supported',
      };
      const normalized: NoteGenerationEvidenceItem[] =
        normalizeEvidenceItems([invalidRef], ['src-std'], sectionMap());
      expect(normalized.length).assertEqual(1);
      expect(normalized[0].sourceRefs.length).assertEqual(1);
      expect(normalized[0].sourceRefs[0].sourceId).assertEqual('src-std');
      expect(normalized[0].sourceRefs[0].excerpt).assertEqual('');
    });

    it('validate_allows_empty_excerpt_but_keeps_fake_excerpt_hard', 0, () => {
      const emptyExcerpt: NoteGenerationEvidenceItem = stdEvidence('ev-empty', '密度函数对称', 'src-std', '');
      const issuesEmpty: NoteGenerationIssue[] = validateStandardArtifacts(
        stdOutline(), [emptyExcerpt], stdDraft(), stdBundle(), stdRequirement());
      let emptyLocatableCount: number = 0;
      for (const issue of issuesEmpty) {
        if (issue.code === 'EVIDENCE_EXCERPT_NOT_LOCATABLE') {
          emptyLocatableCount += 1;
        }
      }
      expect(emptyLocatableCount).assertEqual(0);

      const fakeExcerpt: NoteGenerationEvidenceItem =
        stdEvidence('ev-fake', '密度函数对称', 'src-std', '源材料里不存在的引文');
      const issuesFake: NoteGenerationIssue[] = validateStandardArtifacts(
        stdOutline(), [fakeExcerpt], stdDraft(), stdBundle(), stdRequirement());
      let fakeLocatableCount: number = 0;
      for (const issue of issuesFake) {
        if (issue.code === 'EVIDENCE_EXCERPT_NOT_LOCATABLE') {
          fakeLocatableCount += 1;
        }
      }
      expect(fakeLocatableCount).assertEqual(1);
    });
  });

  // 2026-09-20 P0-7: deep 管线自建证据 (origin='pipeline') 是溯源元数据 —
  // 章节由该 segment 生成是结构性事实, 不适用「草稿逐字保留 excerpt」契约;
  // LLM 声明证据 (origin 缺省) 行为不变
  describe('NoteGenerationModels.pipeline_evidence_origin', () => {
    function deepBundle(): SourceBundle {
      const fragment: SourceFragment = {
        id: 'src-deep',
        kind: 'conversation',
        originId: 'origin-deep',
        sequence: 0,
        fingerprint: 'fp-deep',
        text: '定义与记号\n$$f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}$$\n其中 mu 为均值。',
      };
      const bundle: SourceBundle = { fragments: [fragment] };
      return bundle;
    }

    function deepOutline(): NoteGenerationOutline {
      return {
        schemaVersion: NOTE_OUTLINE_SCHEMA_VERSION,
        sections: [{ id: 'sec-f', label: '公式', order: 0, mustInclude: [], sourceIds: ['src-deep'] }],
      };
    }

    function formulaEvidence(pipeline: boolean): NoteGenerationEvidenceItem {
      const excerpt: string = '$$f(x)=\\frac{1}{\\sigma\\sqrt{2\\pi}}$$';
      const start: number = deepBundle().fragments[0].text.indexOf(excerpt);
      const item: NoteGenerationEvidenceItem = {
        id: 'ev-formula',
        type: 'formula',
        claim: excerpt,
        sourceRefs: [{ sourceId: 'src-deep', excerpt: excerpt, start: start, end: start + excerpt.length }],
        targetSectionId: 'sec-f',
        verification: 'supported',
      };
      if (pipeline) {
        item.origin = 'pipeline';
      }
      return item;
    }

    function deepDraft(): NoteDraftDocument {
      return {
        schemaVersion: NOTE_DRAFT_SCHEMA_VERSION,
        title: '正态分布',
        summary: '密度函数关于均值对称',
        subject: '高等数学',
        category: '公式',
        chapter: '概率论',
        difficulty: 2,
        tags: ['正态分布'],
        sections: [{
          id: 'sec-f', label: '公式',
          content: '密度函数 $f(x)$ 关于 $x=\\mu$ 对称, 在均值处取得最大值。',
          sourceIds: ['src-deep'], state: 'generated', baseHash: '',
        }],
        instruction: '保存这条笔记',
      };
    }

    function deepRequirement(): NoteGenerationRequirement {
      return { detailLevel: 'normal', mustInclude: [], mustAvoid: [], targetSectionIds: [], preserveUserEdits: true };
    }

    function deepSectionMap(): Map<string, string[]> {
      const map: Map<string, string[]> = new Map<string, string[]>();
      map.set('sec-f', ['src-deep']);
      return map;
    }

    function countCode(issues: NoteGenerationIssue[], code: string): number {
      let count: number = 0;
      for (const issue of issues) {
        if (issue.code === code) {
          count += 1;
        }
      }
      return count;
    }

    it('pipeline_formula_evidence_skips_verbatim_preservation_check', 0, () => {
      const issues: NoteGenerationIssue[] = validateStandardArtifacts(
        deepOutline(), [formulaEvidence(true)], deepDraft(), deepBundle(), deepRequirement());
      expect(countCode(issues, 'FORMULA_NOT_PRESERVED')).assertEqual(0);
      expect(countCode(issues, 'EVIDENCE_NOT_PRESERVED')).assertEqual(0);
    });

    it('model_formula_evidence_still_requires_verbatim_preservation', 0, () => {
      const issues: NoteGenerationIssue[] = validateStandardArtifacts(
        deepOutline(), [formulaEvidence(false)], deepDraft(), deepBundle(), deepRequirement());
      expect(countCode(issues, 'FORMULA_NOT_PRESERVED')).assertEqual(1);
    });

    it('normalize_evidence_preserves_pipeline_origin', 0, () => {
      const normalized: NoteGenerationEvidenceItem[] =
        normalizeEvidenceItems([formulaEvidence(true)], ['src-deep'], deepSectionMap());
      expect(normalized.length).assertEqual(1);
      expect(normalized[0].origin).assertEqual('pipeline');
    });
  });
}
