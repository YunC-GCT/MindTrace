// ============================================================================
//  services/NoteEditService.ets — 笔记新建/更新服务 (D3 spec 012)
//  ----------------------------------------------------------------------------
//  职责: 手工编辑入口，委托 KnowledgeUnitWriteService 创建或乐观锁更新
//  依赖: KnowledgeUnitWriteServiceFactory
//  ============================================================================
import { KnowledgeUnit } from 'common'
import { common } from '@kit.AbilityKit'
import { KnowledgeUnitWriteResult } from 'common'
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

  /** 用户确认「另存为新笔记」：跳过判重，换一个新 id，再走正常写入/索引链路。 */
  static async saveAsNew(
    context: common.UIAbilityContext,
    unit: KnowledgeUnit,
  ): Promise<KnowledgeUnitWriteResult> {
    const service: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(context)
    const copy: KnowledgeUnit = JSON.parse(JSON.stringify(unit)) as KnowledgeUnit
    const now: number = Date.now()
    copy.id = (unit.id.length > 0 ? unit.id : 'note') + '-copy-' + now.toString()
    copy.version = 1
    copy.createdAt = now
    copy.updatedAt = now
    copy.embedding = []
    return service.create(copy, 'save-as-new', true)
  }
}
