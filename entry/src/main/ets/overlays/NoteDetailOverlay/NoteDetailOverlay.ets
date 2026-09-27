// ============================================================================
//  overlays/NoteDetailOverlay/NoteDetailOverlay.ets - note detail/editor overlay
// ============================================================================

import {
  BG_DARK, BG_CARD, TEXT, DANGER_BRIGHT, MINT, TEXT_2, TEXT_3, BORDER,
  F_SM, F_MD,
  W_SEMIBOLD, W_BOLD,
  R_MD,
  S_3, S_4,
  OVERLAY_MASK_SOLID,
  NoteItem,
  KnowledgeUnit,
  DifficultyLevel,
  ReviewStatus,
  uuid,
  isKnownNoteType,
  normalizeNoteType,
  ContentExcerptBuilder,
  NOTE_SUMMARY_MAX_LENGTH,
} from 'common'
import { promptAction } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import { NoteEditService } from '../../services/NoteEditService'
import { NoteDetailMeta } from './NoteDetailMeta'
import { NoteDetailBody } from './NoteDetailBody'
import { NoteActionBar } from './NoteActionBar'
import { NoteIconButton } from './NoteIconButton'
import { NoteEditForm } from './NoteEditForm'
import { invalidateDetailRender } from './model/DetailRenderCache'
import { invalidateMarkdownText } from '../../utils/MarkdownParseCache'
import {
  KnowledgeUnitWriteErrorCode,
  KnowledgeUnitWriteResult,
} from '../../models/KnowledgeUnitWriteModels'
import { NoteDraftReadyEvent, IncrementalDiffItem } from 'common'
import {
  NOTE_DETAIL_STABILITY_QUIET_MS,
  NoteDetailRenderMetrics,
} from '../../services/NoteDetailRenderMetrics'

@Component
export struct NoteDetailOverlay {
  @Prop @Watch('onDetailInputChanged') note: NoteItem = new NoteItem(0, '', '', '', '', 0, '', [], '')
  @Prop @Watch('onDetailInputChanged') unit: KnowledgeUnit | null = null
  @Prop @Watch('onDetailInputChanged') units: KnowledgeUnit[] = []
  @Prop @Watch('onDetailInputChanged') isCreating: boolean = false
  @Prop generatedDraft: NoteDraftReadyEvent | null = null
  onDraftCancel: () => void = (): void => {}
  onDraftConfirm: (candidate: KnowledgeUnit) => Promise<KnowledgeUnit> = async (_candidate: KnowledgeUnit): Promise<KnowledgeUnit> => {
    throw new Error('草稿确认不可用')
  }
  @StorageProp('statusBarHeight') sbh: number = 0
  @State localUnit: KnowledgeUnit | null = null
  @State isEditing: boolean = false
  @State titleText: string = ''
  @State summaryText: string = ''
  @State contentText: string = ''
  @State tagsText: string = ''
  @State initialTitleText: string = ''
  @State initialSummaryText: string = ''
  @State initialContentText: string = ''
  @State initialTagsText: string = ''
  @State saving: boolean = false
  @State showDiscardConfirm: boolean = false
  private summaryBuilder: ContentExcerptBuilder = new ContentExcerptBuilder()
  private stableObservationSeq: number = 0
  onClose: () => void = (): void => {}
  onEdit: (id: number) => void = (_id: number): void => {}
  onDelete: (id: string) => void = (_id: string): void => {}
  onSaved: (unit: KnowledgeUnit) => void = (_unit: KnowledgeUnit): void => {}

  aboutToAppear(): void {
    if (this.generatedDraft !== null) {
      NoteDetailRenderMetrics.recordDraftState()
      NoteDetailRenderMetrics.recordEditState()
      this.isEditing = true
      this.loadForm(this.generatedDraft.candidate)
      return
    }
    if (this.isCreating) {
      NoteDetailRenderMetrics.recordEditState()
      this.isEditing = true
      this.loadForm(null)
    }
  }

  aboutToDisappear(): void {
    this.stableObservationSeq += 1
  }

  build() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor(OVERLAY_MASK_SOLID)
        .onClick((): void => this.closeOrCancel())

      Column() {
        Scroll() {
          Column() {
            if (this.isEditing) {
              Row().width('100%').height(this.sbh).backgroundColor(BG_DARK)
              NoteEditForm({
                titleText: this.titleText,
                summaryText: this.summaryText,
                contentText: this.contentText,
                tagsText: this.tagsText,
                onTitleChange: (value: string): void => { this.titleText = value },
                onSummaryChange: (value: string): void => { this.summaryText = value },
                onContentChange: (value: string): void => { this.contentText = value },
                onTagsChange: (value: string): void => { this.tagsText = value },
              })
              if (this.generatedDraft !== null) {
                Text('AI 草稿 · 来源 ' + this.generatedDraft.sourceCount.toString()
                  + ' · soft issues ' + this.generatedDraft.softIssueCount.toString())
                  .fontSize(F_SM)
                  .fontColor(TEXT_3)
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })
                if (this.generatedDraft.incrementalDiff !== undefined) {
                  ForEach(this.generatedDraft.incrementalDiff, (item: IncrementalDiffItem) => {
                    Text(this.diffLabel(item))
                      .fontSize(F_SM)
                      .fontColor(TEXT_3)
                      .width('100%')
                      .padding({ left: 16, right: 16, bottom: 4 })
                  }, (item: IncrementalDiffItem): string => item.sectionId)
                }
              }
            } else if (!this.canRenderReadOnlyDetail()) {
              Row().width('100%').height(this.sbh).backgroundColor(BG_DARK)
              this.LoadingState()
            } else {
              Column() {
                NoteDetailMeta({
                  note: this.note,
                  unit: this.effectiveUnit(),
                  units: this.units,
                  topInset: this.sbh,
                })
                NoteDetailBody({ note: this.note, unit: this.effectiveUnit(), units: this.units })
              }
              .width('100%')
              .onAreaChange((_oldValue: Area, newValue: Area): void => {
                this.observeReadOnlyArea(Number(newValue.height))
              })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        if (this.isEditing) {
          Row() {
            Blank()
            NoteIconButton({
              name: 'close',
              color: TEXT_2,
              isEnabled: !this.saving,
              onTap: (): void => this.cancelEdit(),
            })
            Blank().width(8)
            if (this.saving) {
              NoteIconButton({
                name: 'more',
                color: TEXT_3,
                isEnabled: false,
                onTap: (): void => {},
              })
            } else {
              NoteIconButton({
                name: 'check',
                color: MINT,
                isEnabled: true,
                onTap: (): void => {
                  this.saveEdit().then((): void => {}).catch((_e: Error): void => {})
                },
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
          .backgroundColor(BG_DARK)
        } else if (this.effectiveUnit() !== null) {
          NoteActionBar({
            onDelete: (): void => this.confirmDelete(),
            onEdit: (): void => this.startEdit(),
            onShare: (): void => this.mockShare(),
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(BG_DARK)

      if (this.showDiscardConfirm) {
        this.DiscardConfirm()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LoadingState() {
    Column() {
      Blank()

      Text('正在加载笔记内容')
        .fontSize(F_MD)
        .fontWeight(W_SEMIBOLD)
        .fontColor(TEXT)
        .width('100%')
        .textAlign(TextAlign.Center)

      Text('稍等片刻，完整正文马上呈现。')
        .fontSize(F_SM)
        .fontColor(TEXT_3)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: S_3 })

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: S_4, right: S_4 })
  }

  @Builder
  DiscardConfirm() {
    Column() {
      Blank()
      Column() {
        Text('放弃修改？')
          .fontSize(F_MD)
          .fontWeight(W_BOLD)
          .fontColor(TEXT)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: S_3 })

        Text('当前编辑内容尚未保存。')
          .fontSize(F_SM)
          .fontColor(TEXT_2)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: S_4 })

        Row() {
          Text('继续编辑')
            .fontSize(F_SM)
            .fontWeight(W_SEMIBOLD)
            .fontColor(TEXT_2)
            .height(40)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .borderRadius(R_MD)
            .backgroundColor('#12FFFFFF')
            .onClick((): void => {
              this.showDiscardConfirm = false
            })

          Blank().width(10)

          Text('放弃')
            .fontSize(F_SM)
            .fontWeight(W_SEMIBOLD)
            .fontColor(BG_DARK)
            .height(40)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .borderRadius(R_MD)
            .backgroundColor(MINT)
            .onClick((): void => this.confirmDiscardEdit())
        }
        .width('100%')
      }
      .width('78%')
      .padding({ left: S_4, right: S_4, top: S_4, bottom: S_4 })
      .borderRadius(R_MD + 4)
      .backgroundColor(BG_CARD)
      .border({ width: 1, color: BORDER })

      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(OVERLAY_MASK_SOLID)
    .onClick((): void => {
      this.showDiscardConfirm = false
    })
  }

  private effectiveUnit(): KnowledgeUnit | null {
    return this.localUnit !== null ? this.localUnit : this.unit
  }

  private canRenderReadOnlyDetail = (): boolean => {
    if (this.effectiveUnit() !== null) {
      return true
    }
    return this.note.title.trim().length > 0 || this.note.body.trim().length > 0
  }

  onDetailInputChanged(): void {
    this.stableObservationSeq += 1
    if (this.localUnit !== null && this.localUnit.id !== this.currentNoteRawId()) {
      this.localUnit = null
    }
  }

  private diffLabel = (item: IncrementalDiffItem): string => {
    if (item.kind === 'added') {
      return '新增 · ' + item.label
    }
    if (item.kind === 'changed') {
      return '修改 · ' + item.label
    }
    if (item.kind === 'locked') {
      return '锁定 · ' + item.label
    }
    return '保留 · ' + item.label
  }

  private startEdit = (): void => {
    const current: KnowledgeUnit | null = this.effectiveUnit()
    if (current === null) {
      promptAction.showToast({ message: '笔记仍在加载', duration: 1200 })
      return
    }
    this.loadForm(current)
    this.isEditing = true
    NoteDetailRenderMetrics.recordEditState()
    this.onEdit(this.note.id)
  }

  private loadForm(unit: KnowledgeUnit | null): void {
    if (unit === null) {
      this.titleText = ''
      this.summaryText = ''
      this.contentText = ''
      this.tagsText = ''
      this.captureInitialSnapshot()
      return
    }
    this.titleText = unit.title
    this.summaryText = unit.summary
    this.contentText = unit.content
    this.tagsText = unit.tags.join(', ')
    this.captureInitialSnapshot()
  }

  private cancelEdit = (): void => {
    if (this.saving) {
      return
    }
    if (this.hasUnsavedChanges()) {
      this.showDiscardConfirm = true
      return
    }
    this.discardEdit()
  }

  private discardEdit(): void {
    this.showDiscardConfirm = false
    if (this.generatedDraft !== null) {
      this.onDraftCancel()
      return
    }
    if (this.isCreating) {
      this.onClose()
      return
    }
    this.isEditing = false
    this.loadForm(this.effectiveUnit())
  }

  private confirmDiscardEdit = (): void => {
    NoteDetailRenderMetrics.recordDiscardConfirm()
    this.discardEdit()
  }

  private closeOrCancel = (): void => {
    if (this.saving) {
      return
    }
    if (this.isEditing) {
      this.cancelEdit()
      return
    }
    this.onClose()
  }

  private saveEdit = async (): Promise<void> => {
    if (this.saving) {
      return
    }
    const title: string = this.titleText.trim()
    const summary: string = this.summaryBuilder.buildSummary(this.summaryText.trim(), NOTE_SUMMARY_MAX_LENGTH)
    const content: string = this.contentText.trim()
    if (title.length === 0) {
      promptAction.showToast({ message: '请输入标题', duration: 1200 })
      return
    }
    if (summary.length === 0 && content.length === 0) {
      promptAction.showToast({ message: '摘要和正文至少填写一项', duration: 1500 })
      return
    }

    this.saving = true
    let databaseCommitted: boolean = false
    try {
      const now: number = Date.now()
      const current: KnowledgeUnit | null = this.effectiveUnit()
      const expectedVersion: number = current !== null ? current.version : 0
      const saved: KnowledgeUnit = this.generatedDraft !== null
        ? this.buildGeneratedUnit(now, title, summary, content)
        : this.isCreating
          ? this.buildManualUnit(now, title, summary, content)
          : this.buildUpdatedUnit(now, title, summary, content)
      const result: KnowledgeUnitWriteResult = this.generatedDraft !== null
        ? await this.confirmGeneratedDraft(saved)
        : await NoteEditService.upsert(getContext(this) as common.UIAbilityContext, saved, this.isCreating, expectedVersion)
      if (!result.committed) {
        if (result.errorCode === KnowledgeUnitWriteErrorCode.VERSION_CONFLICT) {
          promptAction.showToast({ message: '笔记已被修改，请重新打开后再保存', duration: 1800 })
          this.saving = false
          return
        }
        throw new Error(result.errorMessage ?? '笔记未保存')
      }
      databaseCommitted = true
      const committed: KnowledgeUnit = result.unit
      this.invalidateSavedRenderCaches(committed)
      this.localUnit = committed
      this.isEditing = false
      this.showDiscardConfirm = false
      this.loadForm(committed)
      this.onSaved(committed)
      const suffix: string = result.warnings.length > 0 ? '，部分刷新稍后重试' : ''
      promptAction.showToast({ message: (this.isCreating ? '笔记已新建' : '笔记已保存') + suffix, duration: 1500 })
    } catch (e) {
      const message: string = (e as Error).message ?? String(e)
      const prefix: string = databaseCommitted ? '笔记已保存，但页面刷新失败：' : '保存失败：'
      promptAction.showToast({ message: prefix + message, duration: 1800 })
    }
    this.saving = false
  }

  private async confirmGeneratedDraft(candidate: KnowledgeUnit): Promise<KnowledgeUnitWriteResult> {
    if (this.generatedDraft === null) {
      throw new Error('草稿不可用')
    }
    const committed: KnowledgeUnit = await this.onDraftConfirm(candidate)
    return { committed: true, rowId: 0, unit: committed, warnings: [] }
  }

  private buildGeneratedUnit(now: number, title: string, summary: string, content: string): KnowledgeUnit {
    if (this.generatedDraft === null) {
      throw new Error('草稿不可用')
    }
    const source: KnowledgeUnit = this.generatedDraft.candidate
    return {
      id: source.id,
      title: title,
      content: content,
      summary: summary,
      tags: this.parseTags(this.tagsText),
      subject: source.subject,
      category: source.category,
      chapter: source.chapter,
      difficulty: source.difficulty,
      source: source.source,
      createdAt: source.createdAt,
      updatedAt: now,
      reviewStatus: source.reviewStatus,
      nextReviewAt: source.nextReviewAt,
      intervalDays: source.intervalDays,
      easeFactor: source.easeFactor,
      repetitions: source.repetitions,
      prerequisites: source.prerequisites,
      related: source.related,
      embedding: source.embedding,
      userId: source.userId,
      version: source.version,
    }
  }

  private buildManualUnit(now: number, title: string, summary: string, content: string): KnowledgeUnit {
    return {
      id: uuid(),
      title: title,
      content: content,
      summary: summary,
      tags: this.parseTags(this.tagsText),
      subject: this.resolveManualSubject(),
      category: this.resolveManualCategory(),
      chapter: '',
      difficulty: DifficultyLevel.MEDIUM,
      source: 'manual',
      createdAt: now,
      updatedAt: now,
      reviewStatus: ReviewStatus.NEW,
      nextReviewAt: now + 86400000,
      intervalDays: 1,
      easeFactor: 2.5,
      repetitions: 0,
      prerequisites: [],
      related: [],
      embedding: [],
      userId: '',
      version: 1,
    }
  }

  private buildUpdatedUnit(now: number, title: string, summary: string, content: string): KnowledgeUnit {
    const current: KnowledgeUnit | null = this.effectiveUnit()
    if (current === null) {
      throw new Error('笔记不可用')
    }
    return {
      id: current.id,
      title: title,
      content: content,
      summary: summary,
      tags: this.parseTags(this.tagsText),
      subject: this.resolveExistingSubject(current),
      category: this.resolveExistingCategory(current),
      chapter: current.chapter,
      difficulty: current.difficulty,
      source: current.source,
      createdAt: current.createdAt,
      updatedAt: now,
      reviewStatus: current.reviewStatus,
      nextReviewAt: current.nextReviewAt,
      intervalDays: current.intervalDays,
      easeFactor: current.easeFactor,
      repetitions: current.repetitions,
      prerequisites: current.prerequisites,
      related: current.related,
      embedding: current.embedding,
      userId: current.userId,
      version: current.version + 1,
    }
  }

  private resolveManualSubject(): string {
    const subject: string = this.note.subject.trim()
    if (subject.length > 0) {
      return subject
    }
    return '其它'
  }

  private resolveManualCategory(): string {
    const noteType: string = normalizeNoteType(this.note.type)
    if (isKnownNoteType(noteType)) {
      return noteType
    }
    const tags: string[] = this.parseTags(this.tagsText)
    for (const tag of tags) {
      const type: string = normalizeNoteType(tag)
      if (isKnownNoteType(type)) {
        return type
      }
    }
    return '概念'
  }

  private resolveExistingSubject(current: KnowledgeUnit): string {
    const subject: string = current.subject.trim()
    if (subject.length > 0) {
      return subject
    }
    return this.resolveManualSubject()
  }

  private resolveExistingCategory(current: KnowledgeUnit): string {
    const category: string = normalizeNoteType(current.category)
    if (isKnownNoteType(category)) {
      return category
    }
    return this.resolveManualCategory()
  }

  private parseTags(raw: string): string[] {
    const result: string[] = []
    const parts: string[] = raw
      .replace(/\r/g, '\n')
      .replace(/,/g, '\n')
      .replace(/\uFF0C/g, '\n')
      .replace(/\u3001/g, '\n')
      .replace(/;/g, '\n')
      .replace(/\uFF1B/g, '\n')
      .split(/\s+/)
    for (const part of parts) {
      const tag: string = part.trim()
      if (tag.length > 0 && result.indexOf(tag) < 0) {
        result.push(tag)
      }
    }
    return result
  }

  private captureInitialSnapshot(): void {
    this.initialTitleText = this.titleText
    this.initialSummaryText = this.summaryText
    this.initialContentText = this.contentText
    this.initialTagsText = this.tagsText
  }

  private hasUnsavedChanges(): boolean {
    return this.titleText !== this.initialTitleText
      || this.summaryText !== this.initialSummaryText
      || this.contentText !== this.initialContentText
      || this.tagsText !== this.initialTagsText
  }

  private invalidateSavedRenderCaches = (unit: KnowledgeUnit): void => {
    const previous: KnowledgeUnit | null = this.effectiveUnit()
    invalidateDetailRender(unit.id)
    invalidateMarkdownText(unit.summary)
    invalidateMarkdownText(unit.content)
    if (previous !== null) {
      invalidateMarkdownText(previous.summary)
      invalidateMarkdownText(previous.content)
    }
  }

  private currentNoteRawId = (): string => {
    return this.note.rawId.length > 0 ? this.note.rawId : this.note.id.toString()
  }

  private mockShare = (): void => {
    promptAction.showToast({ message: '分享功能暂未开放', duration: 1500 })
  }

  private confirmDelete = (): void => {
    const noteId: string = this.note.rawId.length > 0 ? this.note.rawId : this.note.id.toString()
    promptAction.showDialog({
      title: '删除笔记？',
      message: '删除后无法恢复，请确认是否继续。',
      buttons: [
        { text: '取消', color: TEXT_3 },
        { text: '删除', color: DANGER_BRIGHT },
      ],
    }).then((result): void => {
      if (result.index === 1) {
        NoteDetailRenderMetrics.recordDeleteConfirm()
        this.onDelete(noteId)
      }
    }).catch((): void => {
      promptAction.showToast({ message: '无法打开删除确认', duration: 1200 })
    })
  }

  private observeReadOnlyArea = (height: number): void => {
    if (!NoteDetailRenderMetrics.isEnabled()) {
      return
    }
    NoteDetailRenderMetrics.recordViewportHeight(height)
    this.stableObservationSeq += 1
    this.scheduleStabilityProbe(this.stableObservationSeq)
  }

  private scheduleStabilityProbe = (seq: number): void => {
    setTimeout((): void => {
      if (seq !== this.stableObservationSeq || !NoteDetailRenderMetrics.isEnabled()) {
        return
      }
      if (!NoteDetailRenderMetrics.markStable()) {
        this.scheduleStabilityProbe(seq)
      }
    }, NOTE_DETAIL_STABILITY_QUIET_MS)
  }
}
