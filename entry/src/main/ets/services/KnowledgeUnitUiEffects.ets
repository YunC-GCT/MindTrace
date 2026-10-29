/**
 * KnowledgeUnitUiEffects.ets — 写后副作用里的「UI 部分」注册表
 *
 * 路径: entry/src/main/ets/services/KnowledgeUnitUiEffects.ets
 * 职责: 让只能在主进程加载的 UI 副作用（卡片快照刷新，背后是 @kit.FormKit）
 *      由主进程注册进来，共享工厂自己不 import 任何受限 Kit。
 * 依赖: models/KnowledgeUnitWriteModels, @kit.AbilityKit
 *
 * 为什么要有这层：小艺端A2A 的扩展进程（:agent）也要走正规写路径落库，
 *   而 process-boundary 会把「静态 + 动态 import」都算进可达链；只要工厂里出现
 *   卡片副作用模块，:agent 就会被判定可达 @kit.FormKit。
 *   于是改成「主进程注册、工厂按注册表取」，扩展进程拿到空数组，天然没有 UI 副作用。
 */

import { common } from '@kit.AbilityKit';
import { KnowledgeUnitPostCommitEffect } from '../models/KnowledgeUnitWriteModels';

/** 主进程侧的 UI 副作用提供者（应用启动时注册一次）。 */
export interface KnowledgeUnitUiEffectProvider {
  build(context: common.Context): KnowledgeUnitPostCommitEffect;
}

export class KnowledgeUnitUiEffects {
  private static provider: KnowledgeUnitUiEffectProvider | null = null;

  /** 只在主进程（EntryAbility.onCreate）调用；扩展进程不注册，拿到空列表。 */
  static register(provider: KnowledgeUnitUiEffectProvider): void {
    KnowledgeUnitUiEffects.provider = provider;
  }

  static build(context: common.Context): KnowledgeUnitPostCommitEffect[] {
    const provider: KnowledgeUnitUiEffectProvider | null = KnowledgeUnitUiEffects.provider;
    if (provider === null) {
      return [];
    }
    return [provider.build(context)];
  }
}
