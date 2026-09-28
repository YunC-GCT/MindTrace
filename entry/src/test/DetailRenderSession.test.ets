/**
 * DetailRenderSession.test.ets — #186/#187 实例会话与公式预算测试
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
  DETAIL_RENDER_PRIORITY_META,
  DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
  DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
  DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
  DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
  DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
  buildDetailRenderSessionKey,
} from '../main/ets/overlays/NoteDetailOverlay/components/DetailRenderSession'
import { NoteItem, KnowledgeUnit, DifficultyLevel, ReviewStatus } from 'common'
import {
  MathRenderPreparationMemo,
  PreparedMathRender,
  buildMathRenderPreparationKey,
  buildNormalizedMathRenderScript,
} from '../main/ets/services/MathRenderBudget'
import type { MathRenderWorkComplete } from '../main/ets/services/MathRenderBudget'

class FakeDetailRenderTimer implements DetailRenderTimer {
  callbacks: Array<() => void> = []
  delays: number[] = []

  schedule(run: () => void, _delayMs: number): void {
    this.callbacks.push(run)
    this.delays.push(_delayMs)
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

  firstDelay(): number {
    return this.delays.length > 0 ? this.delays[0] : -1
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

    it('releases_named_visible_first_priorities_in_contract_order', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      const order: string[] = []
      session.activate('note-a|priority-order')
      session.enqueue('meta', DETAIL_RENDER_PRIORITY_META, (): void => { order.push('meta') })
      session.enqueue('offscreen-formula', DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
        (): void => { order.push('offscreen-formula') })
      session.enqueue('offscreen-text', DETAIL_RENDER_PRIORITY_OFFSCREEN_TEXT,
        (): void => { order.push('offscreen-text') })
      session.enqueue('near', DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT, (): void => { order.push('near') })
      session.enqueue('visible-formula', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (): void => { order.push('visible-formula') })
      session.enqueue('visible-text', DETAIL_RENDER_PRIORITY_VISIBLE_TEXT,
        (): void => { order.push('visible-text') })
      timer.flushOne()
      timer.flushOne()
      timer.flushOne()
      timer.flushOne()
      timer.flushOne()
      timer.flushOne()
      expect(order.join('|')).assertEqual(
        'visible-text|visible-formula|near|offscreen-text|offscreen-formula|meta')
    })

    it('visible_work_avoids_an_artificial_frame_delay', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      session.activate('note-a|visible-delay')
      session.enqueue('visible-text', DETAIL_RENDER_PRIORITY_VISIBLE_TEXT, (): void => {})
      expect(timer.firstDelay()).assertEqual(0)
    })

    it('same_content_block_key_changes_with_session_identity', 0, () => {
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', new FakeDetailRenderTimer())
      session.activate('note-a|same-content')
      const firstKey: string = session.scopeKey('concept|same-content|supplement')
      session.activate('note-b|same-content')
      const secondKey: string = session.scopeKey('concept|same-content|supplement')
      expect(firstKey === secondKey).assertFalse()
    })

    it('same_identity_block_key_changes_after_session_reactivation', 0, () => {
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', new FakeDetailRenderTimer())
      session.activate('note-a|same-content')
      const firstKey: string = session.scopeKey('concept|same-content|supplement')
      session.cancel()
      session.activate('note-a|same-content')
      const reopenedKey: string = session.scopeKey('concept|same-content|supplement')
      expect(firstKey === reopenedKey).assertFalse()
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

    it('admits_at_most_one_web_create_per_frame', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      const order: string[] = []
      session.activate('note-a|web-create-budget')
      session.enqueueWebCreate('first', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (): void => { order.push('first') })
      session.enqueueWebCreate('second', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (): void => { order.push('second') })
      session.enqueueWebCreate('third', DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
        (): void => { order.push('third') })
      timer.flushOne()
      expect(order.join('|')).assertEqual('first')
      expect(session.pendingWebCount()).assertEqual(2)
      expect(timer.delays[0]).assertEqual(16)
      expect(timer.delays[1]).assertEqual(16)
      timer.flushOne()
      expect(order.join('|')).assertEqual('first|second')
      timer.flushOne()
      expect(order.join('|')).assertEqual('first|second|third')
    })

    it('measures_formula_work_and_waits_for_async_completion', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      let workRuns: number = 0
      let firstComplete: MathRenderWorkComplete | null = null
      session.activate('note-a|web-work-budget')
      session.enqueueWebWork('first', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (complete: MathRenderWorkComplete): void => {
          workRuns += 1
          firstComplete = complete
        })
      session.enqueueWebWork('second', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (complete: MathRenderWorkComplete): void => {
          workRuns += 1
          complete(16)
        })
      timer.flushOne()
      expect(workRuns).assertEqual(1)
      expect(session.pendingWebCount()).assertEqual(1)
      expect(timer.pendingCount()).assertEqual(0)
      if (firstComplete !== null) {
        firstComplete(16)
      }
      expect(workRuns).assertEqual(1)
      expect(timer.pendingCount()).assertEqual(1)
      timer.flushOne()
      expect(workRuns).assertEqual(2)
    })

    it('uses_remaining_measured_budget_before_waiting_for_next_frame', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      const order: string[] = []
      session.activate('note-a|measured-work-budget')
      session.enqueueWebWork('first', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (complete: MathRenderWorkComplete): void => {
          order.push('first')
          complete(5)
        })
      session.enqueueWebWork('second', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (complete: MathRenderWorkComplete): void => {
          order.push('second')
          complete(11)
        })
      session.enqueueWebWork('third', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (complete: MathRenderWorkComplete): void => {
          order.push('third')
          complete(1)
        })
      timer.flushOne()
      expect(order.join('|')).assertEqual('first|second')
      expect(session.pendingWebCount()).assertEqual(1)
      expect(timer.pendingCount()).assertEqual(1)
      timer.flushOne()
      expect(order.join('|')).assertEqual('first|second|third')
    })

    it('does_not_deduplicate_identical_formula_instance_keys', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      let creates: number = 0
      session.activate('note-a|identical-formulas')
      session.enqueueWebCreate('same-cache-key|1', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (): void => { creates += 1 })
      session.enqueueWebCreate('same-cache-key|1', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (): void => { creates += 1 })
      timer.flushOne()
      timer.flushOne()
      expect(creates).assertEqual(2)
    })

    it('prioritizes_visible_formula_admission_and_cancels_stale_web_work', 0, () => {
      const timer: FakeDetailRenderTimer = new FakeDetailRenderTimer()
      const session: DetailRenderSession = new DetailRenderSession('noteDetail', timer)
      const order: string[] = []
      session.activate('note-a|web-priority')
      session.enqueueWebCreate('offscreen', DETAIL_RENDER_PRIORITY_OFFSCREEN_FORMULA,
        (): void => { order.push('offscreen') })
      session.enqueueWebCreate('visible', DETAIL_RENDER_PRIORITY_VISIBLE_FORMULA,
        (): void => { order.push('visible') })
      timer.flushOne()
      expect(order.join('|')).assertEqual('visible')
      session.activate('note-b|web-priority')
      timer.flushOne()
      expect(order.join('|')).assertEqual('visible')
      expect(session.pendingWebCount()).assertEqual(0)
    })

    it('memoizes_unchanged_preparation_and_invalidates_each_contract_dimension', 0, () => {
      const memo: MathRenderPreparationMemo = new MathRenderPreparationMemo()
      let factoryRuns: number = 0
      const resolvePrepared = (key: string): PreparedMathRender => memo.resolve(key, (): PreparedMathRender => {
        factoryRuns += 1
        const prepared: PreparedMathRender = new PreparedMathRender()
        prepared.markdown = key
        return prepared
      })
      const baseKey: string = buildMathRenderPreparationKey('  $x$  ', 'note', false, 'MM-MD-v1', 'v2')
      const first: PreparedMathRender = resolvePrepared(baseKey)
      const unchanged: PreparedMathRender = resolvePrepared(baseKey)
      expect(first === unchanged).assertTrue()
      expect(factoryRuns).assertEqual(1)

      resolvePrepared(buildMathRenderPreparationKey('$y$', 'note', false, 'MM-MD-v1', 'v2'))
      resolvePrepared(buildMathRenderPreparationKey('$y$', 'preview', false, 'MM-MD-v1', 'v2'))
      resolvePrepared(buildMathRenderPreparationKey('$y$', 'preview', true, 'MM-MD-v1', 'v2'))
      resolvePrepared(buildMathRenderPreparationKey('$y$', 'preview', true, 'MM-MD-v2', 'v2'))
      resolvePrepared(buildMathRenderPreparationKey('$y$', 'preview', true, 'MM-MD-v2', 'v3'))
      expect(factoryRuns).assertEqual(6)
    })

    it('cold_and_retry_scripts_share_the_normalized_prepared_value', 0, () => {
      const prepared: PreparedMathRender = new PreparedMathRender()
      prepared.markdown = '$normalized$'
      const coldScript: string = buildNormalizedMathRenderScript(prepared, 'note', false)
      const retryScript: string = buildNormalizedMathRenderScript(prepared, 'note', false)
      const displayScript: string = buildNormalizedMathRenderScript(prepared, 'note', true)
      expect(coldScript).assertEqual('renderForCache("$normalized$","note")')
      expect(retryScript).assertEqual(coldScript)
      expect(displayScript).assertEqual('renderFormulaForCache("$normalized$","note")')
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
