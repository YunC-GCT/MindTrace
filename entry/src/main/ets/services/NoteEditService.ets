// ============================================================================
//  services/NoteEditService.ets — 笔记新建/更新服务 (D3 spec 012)
//  ----------------------------------------------------------------------------
//  职责: 封装 NoteDao.insert / update, UI 层禁止直连 database/dao 实现
//  依赖: common.DatabaseHelper · database/NoteDao (服务层唯一入口)
//  ============================================================================
import { KnowledgeUnit, DatabaseHelper } from 'common'
import { common } from '@kit.AbilityKit'
import { relationalStore } from '@kit.ArkData'
import { NoteDao } from '../database/NoteDao'

export class NoteEditService {
  // isCreating=true 走 insert, 否则 update
  static async upsert(context: common.UIAbilityContext, unit: KnowledgeUnit, isCreating: boolean): Promise<void> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore()
    const rdb: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context)
    const dao: NoteDao = new NoteDao(rdb)
    if (isCreating) {
      await dao.insert(unit)
    } else {
      await dao.update(unit)
    }
  }
}
