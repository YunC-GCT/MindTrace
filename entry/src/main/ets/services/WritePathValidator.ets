/**
 * WritePathValidator.ets — 写入路径校验
 *
 * 路径: entry/src/main/ets/services/WritePathValidator.ets
 * 职责: 唯一负责校验进入 RDB 的 KnowledgeUnit / StudyPlanItem / ChatMessageRecord / AgentMemoryRecord
 * 依赖: common KnowledgeUnit, StudyPlanItem; ../models/AgentMemoryModels
 *
 * 数据流:
 *   NoteDaoAdapter / AgentMemoryService / StudyPlanService → validateXxx → 入库
 *
 * ArkTS 1.1 strict 适配:
 *   - 全部抛 throw new Error(...), 保持 catch(e) 时 (e as Error).message 可读
 *   - 静态方法不持有状态,方便 ArkTS Hypium seam 测试注入
 */
import { KnowledgeUnit, StudyPlanItem } from 'common';
import { AgentMemoryRecord, ChatMessageRecord } from '../models/AgentMemoryModels';

export class WritePathValidator {
  static validateKnowledgeUnit(unit: KnowledgeUnit): void {
    WritePathValidator.requireText(unit.id, 'KnowledgeUnit.id');
    WritePathValidator.requireText(unit.title, 'KnowledgeUnit.title');
    WritePathValidator.requireText(unit.content, 'KnowledgeUnit.content');
    WritePathValidator.requireText(unit.subject, 'KnowledgeUnit.subject');
    WritePathValidator.requireText(unit.category, 'KnowledgeUnit.category');
  }

  static validateStudyPlanItem(item: StudyPlanItem): void {
    WritePathValidator.requireText(item.id, 'StudyPlanItem.id');
    WritePathValidator.requireText(item.title, 'StudyPlanItem.title');
    if (item.priority < 1 || item.priority > 3) {
      throw new Error('StudyPlanItem.priority must be between 1 and 3');
    }
  }

  static validateChatMessage(record: ChatMessageRecord): void {
    WritePathValidator.requireText(record.id, 'ChatMessageRecord.id');
    WritePathValidator.requireText(record.sessionId, 'ChatMessageRecord.sessionId');
    WritePathValidator.requireText(record.content, 'ChatMessageRecord.content');
  }

  static validateAgentMemory(record: AgentMemoryRecord): void {
    WritePathValidator.requireText(record.id, 'AgentMemoryRecord.id');
    WritePathValidator.requireText(record.sessionId, 'AgentMemoryRecord.sessionId');
    WritePathValidator.requireText(record.content, 'AgentMemoryRecord.content');
  }

  private static requireText(value: string, field: string): void {
    if (value.trim().length === 0) {
      throw new Error(field + ' must not be empty');
    }
  }
}
