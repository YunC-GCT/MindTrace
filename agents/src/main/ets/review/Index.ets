// agents/review/Index.ets — review 子模块：复习计划服务（证据经 provider 注入）
// 路径: agents/src/main/ets/review/Index.ets
// 职责: 该子模块的对外出口；entry 与其它子模块按此路径导入，避免拉入整个 agents barrel。

export {
  NoteReviewEvidenceProvider, NoteReviewService,
} from './NoteReviewService';
