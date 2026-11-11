// agents/note/Index.ets — note 子模块：生成上下文预处理、校验与判重规则
// 路径: agents/src/main/ets/note/Index.ets
// 职责: 该子模块的对外出口；entry 与其它子模块按此路径导入，避免拉入整个 agents barrel。

export {
  NoteGenerationContextBuilder,
} from './NoteGenerationContextBuilder';
export {
  NoteContextValidityReviewer,
} from './NoteContextValidityReviewer';
export {
  WritePathValidator,
} from './WritePathValidator';
export {
  groupExactDuplicates, groupNearDuplicates, normalizeKey, normalizeLegacySubject,
} from './LegacyNoteNormalizer';
export type {
  LegacyDedupeEntry, LegacyDuplicateGroup, LegacySubjectInput,
} from './LegacyNoteNormalizer';
export {
  SIMILARITY_GRAY_MIN, SIMILARITY_HARD_DUPLICATE,
  bigramSimilarity, findDuplicate, isDuplicateOf, normalizeForDedupe, similarityScore,
} from './NoteDedupe';
export type {
  DedupeCandidate,
} from './NoteDedupe';
