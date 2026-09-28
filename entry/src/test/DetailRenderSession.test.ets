/**
 * DetailRenderSession.test.ets — #186 实例级详情渲染会话测试
 *
 * 路径: entry/src/test/DetailRenderSession.test.ets
 * 职责: 验证 session 身份、generation、优先级、取消和实例隔离。
 * 依赖: Hypium, DetailRenderSession
 *
 * 数据流:
 *   合成 session/任务/timer → DetailRenderSession → 执行与取消断言
 *
 * ArkTS 1.1 strict 适配:
 *   - fake timer 与回调数组均使用显式类型。
 */

import { describe, it, expect } from '@ohos/hypium'
import {
  DetailRenderSession,
  DetailRenderTimer,
  buildDetailRenderSessionKey,
} from '../main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession'
import { NoteItem, KnowledgeUnit, DifficultyLevel, ReviewStatus } from 'common'

class FakeDetailRenderTimer implements DetailRenderTimer {
  callbacks: Array<() => void> = []

  schedule(run: () => void, _delayMs: number): void {
    this.callbacks.push(run)
  }

  flushOne(): void {
    if (this.callbacks.length === 0) {
      return
    }
    const run: () => void = this.callbacks[0]
    this.callbacks.splice(0, 1)
    run()
  }

  pendingCount(): number {
    return this.callbacks.length
  }
}

function testUnit(id: string, version: number, updatedAt: number, content: string): KnowledgeUnit {
  return {
    id: id,
    title: '标题',
    content: content,
    summary: '摘要',
    tags: ['测试'],
    subject: '数学',
    category: '概念',
    chapter: '',
    difficulty: DifficultyLevel.MEDIUM,
    source: 'manual',
    createdAt: 1,
    updatedAt: updatedAt,
    reviewStatus: ReviewStatus.NEW,
    nextReviewAt: 1,
    intervalDays: 1,
    easeFactor: 2.5,
    repetitions: 0,
    prerequisites: [],
    related: [],
    embedding: [],
    userId: 'test',
    version: version,
  }
}

export default function detailRenderSessionTest(): void {
  describe('DetailRenderSession.issue186_instance_scope', () => {
    it('cancelling_one_session_does_not_clear_another_instance', 0, () => {
      const firstTimer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const secondTimer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const first: DetailRenderSession = new DetailRenderSession('noteDetail', firstTimer)
      const second: DetailRenderSession = new DetailRenderSession('noteDetail', secondTimer)
      let firstRuns: number = 0
      let secondRuns: number = 0
      first.activate('note-a|1')
      second.activate('note-b|1')
      first.enqueue('body', 10, (): void => { firstRuns += 1 })
      second.enqueue('body', 10, (): void => { secondRuns += 1 })
      first.cancel()
      firstTimer.flushOne()
      secondTimer.flushOne()
      expect(firstRuns).assertEqual(0)
      expect(secondRuns).assertEqual(1)
    })

    it('note_revision_invalidates_stale_callbacks_before_UI_write', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      let staleRuns: number = 0
      let currentRuns: number = 0
      session.activate('note-a|1')
      session.enqueue('old', 10, (): void => { staleRuns += 1 })
      session.activate('note-a|2')
      session.enqueue('new', 10, (): void => { currentRuns += 1 })
      timer.flushOne()
      timer.flushOne()
      expect(staleRuns).assertEqual(0)
      expect(currentRuns).assertEqual(1)
    })

    it('runs_lower_priority_value_before_meta_work', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      const order: string[] = []
      session.activate('note-a|1')
      session.enqueue('meta', 30, (): void => { order.push('meta') })
      session.enqueue('body', 10, (): void => { order.push('body') })
      timer.flushOne()
      timer.flushOne()
      expect(order[0]).assertEqual('body')
      expect(order[1]).assertEqual('meta')
    })

    it('same_completed_task_is_released_without_scheduling_another_timer', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      let runs: number = 0
      session.activate('note-a|1')
      session.enqueue('body', 10, (): void => { runs += 1 })
      timer.flushOne()
      expect(runs).assertEqual(1)
      session.enqueue('body', 10, (): void => { runs += 1 })
      expect(runs).assertEqual(2)
      expect(timer.pendingCount()).assertEqual(0)
    })

    it('same_identity_local_interaction_keeps_generation_and_completed_work', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      let runs: number = 0
      const firstGeneration: number = session.activate('note-a|1')
      session.enqueue('body', 10, (): void => { runs += 1 })
      timer.flushOne()
      const interactionGeneration: number = session.activate('note-a|1')
      session.enqueue('body', 10, (): void => { runs += 1 })
      expect(interactionGeneration).assertEqual(firstGeneration)
      expect(runs).assertEqual(2)
      expect(timer.pendingCount()).assertEqual(0)
      expect(session.metricSurface()).assertEqual('noteDetail')
    })

    it('session_key_changes_with_identity_revision_and_content', 0, () => {
      const note: NoteItem = new NoteItem(1, '标题', '概念', '数学', '', 0.9, '正文', ['测试'], '2026-09-28', 'note-a')
      const anotherNote: NoteItem = new NoteItem(2, '标题', '概念', '数学', '', 0.9, '正文', ['测试'], '2026-09-28', 'note-b')
      const first: KnowledgeUnit = testUnit('note-a', 1, 100, '正文')
      const revised: KnowledgeUnit = testUnit('note-a', 2, 200, '正文更新')
      const firstKey: string = buildDetailRenderSessionKey(note, first)
      const anotherNoteKey: string = buildDetailRenderSessionKey(anotherNote, first)
      const revisedKey: string = buildDetailRenderSessionKey(note, revised)
      expect(firstKey === anotherNoteKey).assertFalse()
      expect(firstKey === revisedKey).assertFalse()
      expect(firstKey.indexOf('note-a') >= 0).assertTrue()
      expect(anotherNoteKey.indexOf('note-b') >= 0).assertTrue()
    })
  })
}
