/**
 * NoteDetailBackPressCoordinator.ets — 笔记详情系统返回协调器
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailBackPressCoordinator.ets
 * 职责: 将 @Entry 的系统返回事件转交给当前最上层笔记详情浮层。
 * 依赖: 无。
 *
 * 数据流:
 *   NoteDetailOverlay lifecycle -> register/unregister -> @Entry onBackPress
 */

export type NoteDetailBackPressHandler = () => void

class NoteDetailBackPressRegistration {
  id: number
  handler: NoteDetailBackPressHandler

  constructor(id: number, handler: NoteDetailBackPressHandler) {
    this.id = id
    this.handler = handler
  }
}

export class NoteDetailBackPressCoordinator {
  private nextRegistrationId: number = 1
  private registrations: NoteDetailBackPressRegistration[] = []

  register(handler: NoteDetailBackPressHandler): number {
    const registrationId: number = this.nextRegistrationId
    this.nextRegistrationId += 1
    this.registrations.push(new NoteDetailBackPressRegistration(registrationId, handler))
    return registrationId
  }

  unregister(registrationId: number): void {
    const index: number = this.registrations.findIndex(
      (registration: NoteDetailBackPressRegistration): boolean => registration.id === registrationId,
    )
    if (index >= 0) {
      this.registrations.splice(index, 1)
    }
  }

  handleBack(): boolean {
    if (this.registrations.length === 0) {
      return false
    }
    const active: NoteDetailBackPressRegistration = this.registrations[this.registrations.length - 1]
    active.handler()
    return true
  }
}

export const noteDetailBackPressCoordinator: NoteDetailBackPressCoordinator =
  new NoteDetailBackPressCoordinator()
