// ============================================================================
//  overlays/NoteDetailOverlay/NoteActionBar.ets - note detail footer action bar
// ============================================================================

import { BG_DARK, BORDER, TEXT_2, S_2, S_4, S_6 } from 'common'
import { NoteIconButton } from './NoteIconButton'

@Component
export struct NoteActionBar {
  onEdit: () => void = (): void => {}
  onShare: () => void = (): void => {}

  build() {
    Row() {
      Blank()
      NoteIconButton({ name: 'edit', color: TEXT_2, onTap: (): void => this.onEdit() })
      Blank().width(S_2)
      NoteIconButton({ name: 'share', color: TEXT_2, onTap: (): void => this.onShare() })
    }
    .width('100%')
    .padding({ left: S_4, right: S_4, top: S_2, bottom: S_6 })
    .backgroundColor(BG_DARK)
    .border({ width: { top: 1 }, color: BORDER })
  }
}
