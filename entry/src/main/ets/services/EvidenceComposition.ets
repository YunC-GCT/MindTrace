/**
 * EvidenceComposition.ets — 证据链的组合根
 *
 * 路径: entry/src/main/ets/services/EvidenceComposition.ets
 * 职责: 持有注入的 NoteReadPort，并把检索 / 图谱两个 entry 实现装配成
 *       agents 的 NoteEvidenceService
 * 依赖: agents（NoteEvidenceService）、common（NoteReadPort）、
 *       ./RagNoteEvidenceSearch、./RdbNoteGraph
 *
 * 数据流:
 *   EntryAbility.configureEvidenceReadPort → createNoteEvidenceService → 证据端口
 */
import type { NoteReadPort } from 'common';

import { RagNoteEvidenceSearch } from './RagNoteEvidenceSearch';
import { RdbNoteGraph } from './RdbNoteGraph';
import { LlmEvidenceJudgeAdapter } from './LlmEvidenceJudgeAdapter';
import { NoteEvidenceService } from 'agents/src/main/ets/evidence/Index';

// ADR-0021 Step 3：组合根在 DB 初始化后注入只读端口；未注入时证据扩展只返回检索命中。
let configuredReadPort: NoteReadPort | undefined = undefined;

export function configureEvidenceReadPort(port: NoteReadPort | undefined): void {
  configuredReadPort = port;
}

/** 组合根工厂：按当前注入的只读端口装配证据服务。判定端口在这里注入。 */
export function createNoteEvidenceService(): NoteEvidenceService {
  return new NoteEvidenceService(
    new RagNoteEvidenceSearch(configuredReadPort),
    new RdbNoteGraph(),
    configuredReadPort,
    new LlmEvidenceJudgeAdapter(),
  );
}
