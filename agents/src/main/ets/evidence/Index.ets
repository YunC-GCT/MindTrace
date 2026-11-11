// agents/evidence/Index.ets — evidence 子模块：证据服务（数据经端口注入）
// 路径: agents/src/main/ets/evidence/Index.ets
// 职责: 该子模块的对外出口；entry 与其它子模块按此路径导入，避免拉入整个 agents barrel。

export {
  NoteEvidenceService, NoteEvidenceStreamFilter,
} from './NoteEvidenceService';
