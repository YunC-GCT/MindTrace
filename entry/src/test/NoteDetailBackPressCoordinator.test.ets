/**
 * NoteDetailBackPressCoordinator.test.ets — 笔记详情系统返回行为测试
 *
 * 路径: entry/src/test/NoteDetailBackPressCoordinator.test.ets
 * 职责: 验证详情浮层返回注册、消费顺序与精确注销契约。
 * 依赖: @ohos/hypium; NoteDetailBackPressCoordinator.
 */

import { describe, expect, it } from '@ohos/hypium'
import {
  NoteDetailBackPressCoordinator,
} from '../main/ets/overlays/NoteDetailOverlay/NoteDetailBackPressCoordinator'

export default function noteDetailBackPressCoordinatorTest(): void {
  describe('NoteDetailBackPressCoordinator', (): void => {
    it('should preserve system back when no note detail is open', 0, (): void => {
      const coordinator: NoteDetailBackPressCoordinator = new NoteDetailBackPressCoordinator()

      expect(coordinator.handleBack()).assertFalse()
    })

    it('should consume back and close the active note detail once', 0, (): void => {
      const coordinator: NoteDetailBackPressCoordinator = new NoteDetailBackPressCoordinator()
      let closeCount: number = 0
      coordinator.register((): void => {
        closeCount += 1
      })

      expect(coordinator.handleBack()).assertTrue()
      expect(closeCount).assertEqual(1)
    })

    it('should ignore stale cleanup and keep the newest note detail active', 0, (): void => {
      const coordinator: NoteDetailBackPressCoordinator = new NoteDetailBackPressCoordinator()
      let firstCloseCount: number = 0
      let secondCloseCount: number = 0
      const firstRegistrationId: number = coordinator.register((): void => {
        firstCloseCount += 1
      })
      coordinator.register((): void => {
        secondCloseCount += 1
      })

      coordinator.unregister(firstRegistrationId)

      expect(coordinator.handleBack()).assertTrue()
      expect(firstCloseCount).assertEqual(0)
      expect(secondCloseCount).assertEqual(1)
    })

    it('should restore system back after the note detail disappears', 0, (): void => {
      const coordinator: NoteDetailBackPressCoordinator = new NoteDetailBackPressCoordinator()
      const registrationId: number = coordinator.register((): void => {})

      coordinator.unregister(registrationId)

      expect(coordinator.handleBack()).assertFalse()
    })
  })
}
