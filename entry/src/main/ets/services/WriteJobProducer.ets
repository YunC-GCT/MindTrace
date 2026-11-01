/**
 * WriteJobProducer.ets — 跨进程 producer：只入队、不执行（spec 040 P2）
 *
 * 路径: entry/src/main/ets/services/WriteJobProducer.ets
 * 职责: 供 A2A `:agent` 扩展进程 / inbox 迁移等 producer 使用：flag 开启且 DB 就绪时，
 *       把待整理文本写入 agent_job（幂等指纹）并返回 jobId；返回 null 表示走旧路径。
 * 依赖: common DatabaseHelper、./WriteJobConfig、./WriteJobPersistence、../database/AgentJobDao。
 * 数据流: AgentExtAbility/inbox → tryEnqueue() → AgentJobPersistence → agent_job
 *
 * 边界: 不执行 LLM/OCR/写笔记；执行在 UI 进程调度器。
 */
import { DatabaseHelper } from 'common';
import type { common } from '@kit.AbilityKit';
import { WRITE_JOB_PERSIST_ENABLED } from './WriteJobConfig';
import { AgentJobPersistence } from './WriteJobPersistence';
import { AgentJobDao } from '../database/AgentJobDao';

export class WriteJobProducer {
  /** 入队一条待整理文本；flag 关闭/DB 不可用/入队失败返回 null（调用方回退旧路径）。 */
  static async tryEnqueue(context: common.Context, text: string,
    priority: string, source: string): Promise<string | null> {
    if (!WRITE_JOB_PERSIST_ENABLED) {
      return null;
    }
    try {
      await DatabaseHelper.init(context);
      const store = DatabaseHelper.getStore();
      if (store === null) {
        return null;
      }
      const persistence: AgentJobPersistence = new AgentJobPersistence(new AgentJobDao(store));
      return await persistence.enqueueForSource(priority, text, source);
    } catch (e) {
      return null;
    }
  }
}
