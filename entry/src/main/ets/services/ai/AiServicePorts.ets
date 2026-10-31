/**
 * AiServicePorts.ets — AiService 的上下文 / 端口组合根（从 AiService 抽出）
 *
 * 路径: entry/src/main/ets/services/ai/AiServicePorts.ets
 * 职责: ① 从可选 Context 取 UIAbilityContext；② 装配 NoteDao 适配器；③ 装配 NoteWritePort。
 *       服务层不再各自 new 端口/适配器，装配只在这一处。
 * 依赖: services（KnowledgeUnitWriteService / NoteWritePortFactory）、adapters（NoteDaoAdapter）。
 *
 * 为什么放 services/ai：AiService 的切片重构边界；端口装配属于 composition root，
 * 与业务编排分离后，AiService 只依赖本文件的静态方法。
 */
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DatabaseHelper } from 'common';
import type { NoteWritePort } from 'common';
import type { NoteDaoInterface, RunEventSink } from 'agents';
import { NoteDaoAdapter } from '../../adapters/NoteDaoAdapter';
import { KnowledgeUnitWriteService } from '../KnowledgeUnitWriteService';
import { KnowledgeUnitWriteServiceFactory } from '../KnowledgeUnitWriteServiceFactory';
import { NoteWritePortFactory } from '../NoteWritePortFactory';
import { RunStoreDao } from '../../database/RunStoreDao';
import { RunStoreAdapter } from '../../database/RunStoreAdapter';
import { RunStoreEventSink } from './RunStoreEventSink';

export class AiServicePorts {
  /** 取 UIAbilityContext：未注入时直接抛配置错误，调用方不做空判断。 */
  static requireContext(context: common.Context | undefined): common.UIAbilityContext {
    if (context === undefined) {
      throw new Error('AiService 需要 UIAbilityContext');
    }
    return context as common.UIAbilityContext;
  }

  /** agents 端 NoteDaoInterface 适配器（写服务统一入口，保留 post-commit effects）。 */
  static async buildNoteDao(
    context: common.UIAbilityContext,
    includeUiEffects: boolean,
  ): Promise<NoteDaoInterface> {
    const service: KnowledgeUnitWriteService = await KnowledgeUnitWriteServiceFactory.create(context, includeUiEffects);
    const adapter: NoteDaoAdapter = new NoteDaoAdapter(service);
    return adapter;
  }

  /** A4：run 事件 sink 装配（run_store / run_event）。 */
  static async buildRunEventSink(
    context: common.UIAbilityContext,
  ): Promise<RunEventSink> {
    const existing: relationalStore.RdbStore | null = DatabaseHelper.getStore();
    const store: relationalStore.RdbStore = existing !== null ? existing : await DatabaseHelper.init(context);
    const adapter: RunStoreAdapter = new RunStoreAdapter(new RunStoreDao(store));
    return new RunStoreEventSink(adapter);
  }

  /** NoteWritePort 生产装配（commitKey 幂等 / CAS；装配细节在 NoteWritePortFactory）。 */
  static async buildNoteWritePort(
    context: common.UIAbilityContext,
    includeUiEffects: boolean,
  ): Promise<NoteWritePort> {
    return await NoteWritePortFactory.create(context, includeUiEffects);
  }
}
