// ============================================================================
//  services/NoteEditService.ets — 笔记新建/更新服务 (D3 spec 012)
//  ----------------------------------------------------------------------------
//  职责: 手工编辑入口，委托 KnowledgeUnitWriteService 创建或乐观锁更新
//  依赖: KnowledgeUnitWriteServiceFactory
//  ============================================================================
import { KnowledgeUnit } from 'common'
import { common } from '@kit.AbilityKit'
import { KnowledgeUnitWriteResult } from '../models/KnowledgeUnitWriteModels'
import { KnowledgeUnitWriteService } from './KnowledgeUnitWriteService'
import { KnowledgeUnitWriteServiceFactory } from './KnowledgeUnitWriteServiceFactory'

export class NoteEditService {
  static async upsert(
    context: common.UIAbilityContext,
    unit: KnowledgeUnit,
    isCreating: boolean,
    expectedVersion: number,
  ): Promise<KnowledgeUnitWriteResult> {
    const service: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(context)
    if (isCreating) {
      return service.create(unit)
    }
    return service.update(unit, expectedVersion)
  }
}
