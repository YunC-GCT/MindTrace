/**
 * NoteDetailBody.ets - note detail body renderer dispatcher
 *
 * Path: entry/src/main/ets/overlays/NoteDetailOverlay/NoteDetailBody.ets
 * Responsibility: Build one DetailRenderModel and dispatch it to the category-specific renderer.
 * Dependencies: common models, DetailRenderCache, six detail renderers.
 *
 * Data flow:
 *   NoteDetailOverlay -> NoteDetailBody -> getDetailRenderModel -> detail renderer
 *
 * ArkTS 1.1 strict:
 *   - Struct logic uses arrow fields and builders
 *   - Render model is obtained once per build branch
 */

import {
  NoteItem,
  KnowledgeUnit,
} from 'common'
import {
  DetailRenderModel,
  emptyDetailRenderModel,
} from './model/DetailRenderModel'
import { getDetailRenderModel } from './model/DetailRenderCache'
import { DetailRenderSession } from './components/DetailRenderSession'
import { NoteDetailRenderMetrics } from '../../services/NoteDetailRenderMetrics'
import { ConceptDetailView } from './renderers/ConceptDetailView'
import { TheoremDetailView } from './renderers/TheoremDetailView'
import { FormulaDetailView } from './renderers/FormulaDetailView'
import { ProofDetailView } from './renderers/ProofDetailView'
import { ComputationDetailView } from './renderers/ComputationDetailView'
import { FallbackDetailView } from './renderers/FallbackDetailView'

@Component
export struct NoteDetailBody {
  @Prop @Watch('onRenderInputChanged') note: NoteItem = new NoteItem(0, '', '', '', '', 0, '', [], '')
  @Prop @Watch('onRenderInputChanged') unit: KnowledgeUnit | null = null
  @Prop units: KnowledgeUnit[] = []
  @Prop renderSession: DetailRenderSession = new DetailRenderSession()

  aboutToAppear(): void {
    NoteDetailRenderMetrics.recordBodyMount()
  }

  aboutToDisappear(): void {
    NoteDetailRenderMetrics.recordBodyUnmount()
  }

  onRenderInputChanged(): void {
    NoteDetailRenderMetrics.recordBodyInputChange()
  }

  build() {
    Column() {
      this.RenderByModel(this.renderModel())
    }
    .width('100%')
  }

  @Builder
  RenderByModel(model: DetailRenderModel) {
    if (model.category === '概念') {
      ConceptDetailView({ model: model, renderSession: this.renderSession })
    } else if (model.category === '定理') {
      TheoremDetailView({ model: model, renderSession: this.renderSession })
    } else if (model.category === '公式') {
      FormulaDetailView({ model: model, renderSession: this.renderSession })
    } else if (model.category === '证明题') {
      ProofDetailView({ model: model, renderSession: this.renderSession })
    } else if (model.category === '计算题') {
      ComputationDetailView({ model: model, renderSession: this.renderSession })
    } else {
      FallbackDetailView({ model: model, renderSession: this.renderSession })
    }
  }

  private renderModel = (): DetailRenderModel => {
    if (this.unit === null && this.note.title.length === 0) {
      return emptyDetailRenderModel()
    }
    return getDetailRenderModel(this.note, this.unit, this.units)
  }
}
