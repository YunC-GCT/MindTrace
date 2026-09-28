/**
 * DetailReleaseGate.ets — NoteDetail 自动分块释放门
 *
 * 路径: entry/src/main/ets/overlays/NoteDetailOverlay/DetailReleaseGate.ets
 * 职责: 按文字/公式类别将单个详情分块提交给实例级 session，并在获准后自动展示。
 * 依赖: common ContentProtocol, DetailRenderSession
 *
 * 数据流:
 *   renderer block → ContentProtocol classification → session priority queue → builder content
 *
 * ArkTS 1.1 strict 适配:
 *   - 使用显式 builder 参数承载不同 NoteType 的内容块。
 *   - 本地 sequence 与 session generation 双重阻止陈旧回调写 UI。
 */

import { ContentProtocol } from 'common'
import {
  DetailRenderSession,
  DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT,
} from './components/DetailRenderSession'

@Builder
function EmptyDetailReleaseContent() {
  Blank()
}

@Component
export struct DetailReleaseGate {
  @Prop renderSession: DetailRenderSession = new DetailRenderSession()
  @Prop @Watch('onReleaseInputChanged') releaseKey: string = ''
  @Prop releaseContent: string = ''
  @Prop releasePriority: number = DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT
  @Prop formulaPriority: number = DETAIL_RENDER_PRIORITY_NEAR_VIEWPORT
  @BuilderParam content: () => void = EmptyDetailReleaseContent
  @State released: boolean = false
  private releaseSeq: number = 0
  private scheduledKey: string = ''
  private contentProtocol: ContentProtocol = new ContentProtocol()

  aboutToAppear(): void {
    this.resetRelease()
  }

  aboutToDisappear(): void {
    this.releaseSeq += 1
    this.scheduledKey = ''
    this.released = false
  }

  onReleaseInputChanged(): void {
    this.resetRelease()
  }

  build() {
    if (this.released) {
      this.content()
    }
  }

  private resetRelease = (): void => {
    const key: string = this.releaseKey.trim()
    const priority: number = this.contentProtocol.hasFormulaSyntax(this.releaseContent)
      ? this.formulaPriority
      : this.releasePriority
    const scheduledKey: string = key + '|' + priority.toString()
    if (scheduledKey === this.scheduledKey) {
      return
    }
    this.scheduledKey = scheduledKey
    this.releaseSeq += 1
    const seq: number = this.releaseSeq
    const sessionKey: string = this.renderSession.sessionKey()
    const generation: number = this.renderSession.generation()
    if (key.length === 0 || this.releaseContent.trim().length === 0) {
      this.released = false
      return
    }
    this.released = false
    this.renderSession.enqueue('release|' + key, priority, (): void => {
      if (seq !== this.releaseSeq || !this.renderSession.isCurrent(sessionKey, generation)) {
        return
      }
      this.released = true
    })
  }
}
