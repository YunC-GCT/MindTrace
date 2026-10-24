/**
 * FileName: VendorPicker.ets — 厂商选择器(PR2-T2 UI 重构)
 *
 * 路径: entry/src/main/ets/pages/AiSettings/VendorPicker.ets
 * 职责: 渲染 5 预设厂商(DeepSeek/通义/GLM/Kimi/豆包) + 用户添加的自定义 vendor;
 *       每行右侧 [编辑] 按钮展开该 row 下方 panel(API Key 输入 + 模型目录 + 添加模型 + 取消/保存)。
 *       底部 [+ 添加新供应商] 按钮触发父级弹 modal(P3)。
 * 依赖: common(providers.ts: PROVIDERS 常量 + ProviderConfig 类型;
 *       model-catalog: getProviderCatalog; model-discovery 经 ViewModel 回调)
 *
 * 数据流:
 *   AiSettingsPage.vm.vendorId → VendorPicker.props.currentVendorId
 *   onSelect(id) → vm.selectVendor(id)
 *   编辑 button 自管 @State editingVendorId(单真理源,不再通知 ViewModel)
 *   panel 内 取消/保存 2 按钮:
 *     取消: discard local draft, collapse panel
 *     保存: commit local draft 到 parent via onApiKeyChange / onAddModel / onRemoveModel, 再调 onSaveEdit 触发 vm.saveLlm()
 *
 * 2026-10-25 Phase 1.5: 模型 chip 不再写死
 *   - DeepSeek chip 来自 catalog(displayName / contextWindow 只读展示)
 *   - catalog 为空的 vendor 显示「未提供内置清单」+「获取模型清单」;
 *     discovery 结果只作候选(标记「未保存」), 用户点 chip 才走 onCommitModel 落盘
 *   - 发现失败显示 errorCode 对应中文提示, 不静默吞掉
 *
 * PR2-T2 ticket #83 follow-up (2026-09-08): 重写为 draft pattern
 *   - @State apiKeyInput + @State localModels(本地 draft,不在 onChange 立即 push 到 parent)
 *   - 取消 真正 discard,保存 真正 commit
 *   - 之前 always-visible 改动被 revert(用户要回折叠)
 *
 * 5 预设 vendor 的 route 仍来自 providers.ets; 模型清单不再写第二份:
 *   DeepSeek   · model-catalog: deepseek-flash / deepseek-v4-pro
 *   通义 / GLM / Kimi / 豆包 · catalog 为空, 显示已保存 vendor_models + discovery 入口
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式类型标注(: string / : void 等)
 *   - 不使用 any / for-in / as-casts / 尖括号断言
 *   - 显式 list 类型 ProviderConfig[]
 *   - 仅用 @Prop 与 @State 装饰器(@Entry/@Component 除外)
 */

import { PROVIDERS, getProviderCatalog } from 'common';
import type {
  CustomVendorConfig, DiscoveryResult, ModelEffortInfo, ModelListing, ProviderCatalog, ProviderConfig,
} from 'common';
import {
  MINT, MINT_BORDER, BG_CARD, BG_DARK, TEXT, TEXT_2, TEXT_3, TEXT_4, BORDER,
  F_XS, F_SM, F_MD, W_NORMAL, W_MEDIUM, W_SEMIBOLD,
  R_SM, R_MD, S_1, S_2, S_3, S_4,
} from 'common';

// PR2-T2 P3: 添加新供应商 modal 提交的 4 字段配置
// ArkTS 1.1 strict: 必须显式 interface,不允许 inline { name: string, ... } object literal as type
interface AddCustomVendorCfg {
  name: string;
  baseUrl: string;
  apiKey: string;
  firstModel: string;
}

// v6 设计稿: success-dim bg = MINT 颜色 15% 透明度(PR2-T2 polish ticket #81 task A5)
// MINT = #5BE3B0 = rgb(91, 227, 176);light mint bg
const SUCCESS_DIM: string = 'rgba(91, 227, 176, 0.15)'

// 2026-10-25 Phase 1.5: discovery 错误行颜色(与现有暗色卡片对比可读)
const ERROR_TEXT: string = '#FF8A8A'

// 未接入回调时的空结果: 让 UI 走"失败可见"分支, 不静默成功
const EMPTY_DISCOVERY: DiscoveryResult = {
  ok: false,
  models: [],
  errorCode: 'DISCOVERY_NOT_WIRED',
  errorReason: 'no discovery handler',
};

@Component
export struct VendorPicker {
  // 当前选中的 vendor
  @Prop currentVendorId: string = 'deepseek';

  // PR2-T2 ticket #83 L1+L2+L3 (2026-09-08): per-vendor 持久化数据(由 parent 提供)
  @Prop vendorApiKeys: Record<string, string> = {};
  @Prop vendorModels: Record<string, string[]> = {};
  @Prop activeVendorModels: Record<string, string> = {};
  @Prop modelContextWindows: Record<string, number> = {};
  @Prop customVendors: CustomVendorConfig[] = [];

  // PR2-T2 ticket #83 follow-up (2026-09-08): 恢复 click-to-expand
  @State editingVendorId: string | null = null;

  // PR2-T2 ticket #83 follow-up (2026-09-08): local draft state
  // 不在 onChange/onAdd/onRemove 立即 push 到 parent — 等保存按钮 一次性 commit
  @State apiKeyInput: string = '';
  @State originalApiKeyInput: string = '';
  @State localModels: string[] = [];
  @State localActiveModel: string = '';
  @State localContextWindow: string = '65536';

  // PR2-T2: panel 内 model 输入(仅 input 状态,实际数据走 local localModels)
  @State newModelInput: string = '';

  // 2026-10-25 Phase 1.5: 当前展开 vendor 的模型清单(catalog 或 vendor_models)
  // 只驱动 chip 显示; 落盘仍走 saveEdit / commitCandidate
  @State modelListings: ModelListing[] = [];
  // discovery 返回的候选(未保存); 只有用户点 chip 才落盘
  @State discoveryCandidates: ModelListing[] = [];
  @State discoveryLoading: boolean = false;
  @State discoveryError: string = '';
  @State discoveryNotice: string = '';
  @State savingModelId: string = '';
  // 请求序号: collapse / 切 vendor 后旧响应不得覆盖新状态
  private discoverySeq: number = 0;

  // PR2-T2 P3: 添加新供应商 modal 状态(单真理源 — modal 是纯 UI 状态,VendorPicker 自管)
  @State addCustomModalOpen: boolean = false;
  @State newVendorName: string = '';
  @State newVendorBaseUrl: string = '';
  @State newVendorApiKey: string = '';
  @State newVendorModel: string = '';

  // PR2-T2 polish ticket #81 task A4: 新加 custom vendor 标记(session 内有效,无需持久化)
  @State isNewVendorIds: Set<string> = new Set();

  onSelect: (id: string) => void = (_id: string): void => {};

  // PR2-T2 P3: 添加新 vendor 完成回调(把 cfg 传给 ViewModel,ViewModel 加到 customVendors + 切 vendorId)
  onAddVendorConfirm: (cfg: AddCustomVendorCfg) => string = (_cfg: AddCustomVendorCfg): string => '';

  // PR2-T2 ticket #83 L3 (2026-09-08): per-vendor API Key onChange
  // PR2-T2 ticket #83 follow-up (2026-09-08): 不再每键调 — 改为保存按钮 一次性 commit
  onApiKeyChange: (vendorId: string, key: string) => void =
    (_v: string, _k: string): void => {};

  // PR2-T2 ticket #83 L2 (2026-09-08): per-vendor models UI 动作
  // PR2-T2 ticket #83 follow-up (2026-09-08): 不再每点调 — 改为保存按钮 一次性 commit
  onAddModel: (vendorId: string, model: string) => void =
    (_v: string, _m: string): void => {};
  onRemoveModel: (vendorId: string, model: string) => void =
    (_v: string, _m: string): void => {};
  onSelectModel: (vendorId: string, model: string) => void =
    (_v: string, _m: string): void => {};
  onContextWindowChange: (vendorId: string, model: string, value: number) => void =
    (_v: string, _m: string, _value: number): void => {};

  // PR2-T2 ticket #83 follow-up (2026-09-08): 保存按钮 触发 parent save
  onSaveEdit: (vendorId: string) => void = (_vendorId: string): void => {};

  // 2026-10-25 Phase 1.5: 按 vendor 取模型清单(DeepSeek 走 catalog, 其它走 vendor_models)
  onGetModels: (vendorId: string) => ModelListing[] =
    (_vendorId: string): ModelListing[] => [];
  // 拉 /models 候选(不落盘); ViewModel 转调 discoverModels
  onDiscoverModels: (vendorId: string) => Promise<DiscoveryResult> =
    (_vendorId: string): Promise<DiscoveryResult> => Promise.resolve(EMPTY_DISCOVERY);
  // 用户点「未保存」chip 才落盘
  onCommitModel: (vendorId: string, model: string, contextWindow: number) => Promise<boolean> =
    (_v: string, _m: string, _c: number): Promise<boolean> => Promise.resolve(false);

  // PR2-T2 ticket #83 follow-up (2026-09-08): 展开 vendor 编辑 panel
  openEdit = (vendorId: string): void => {
    this.editingVendorId = vendorId
    // initialize drafts from parent's current state
    this.apiKeyInput = this.vendorApiKeys[vendorId] ?? ''
    this.originalApiKeyInput = this.apiKeyInput
    const current: string[] | undefined = this.vendorModels[vendorId]
    this.localModels = current !== undefined ? [...current] : []
    const active: string | undefined = this.activeVendorModels[vendorId]
    this.localActiveModel = active !== undefined && active.length > 0
      ? active
      : (this.localModels.length > 0 ? this.localModels[0] : '')
    this.newModelInput = ''
    // Phase 1.5: chip 清单来自 catalog / vendor_models, 不在这里猜能力
    this.modelListings = this.onGetModels(vendorId)
    if (this.localActiveModel.length === 0 && this.modelListings.length > 0) {
      this.localActiveModel = this.modelListings[0].id
    }
    this.localContextWindow = this.initialContextWindow(vendorId, this.localActiveModel).toString()
    // 作废上一次未完成的 discovery 响应
    this.discoverySeq += 1
    this.discoveryCandidates = []
    this.discoveryLoading = false
    this.discoveryError = ''
    this.discoveryNotice = ''
    this.savingModelId = ''
  }

  // PR2-T2 ticket #83 follow-up (2026-09-08): 取消 — discard local drafts, collapse panel
  cancelEdit = (): void => {
    if (this.editingVendorId !== null) {
      this.onApiKeyChange(this.editingVendorId, this.originalApiKeyInput)
    }
    this.editingVendorId = null
    this.apiKeyInput = ''
    this.originalApiKeyInput = ''
    this.localModels = []
    this.localActiveModel = ''
    this.localContextWindow = '65536'
    this.newModelInput = ''
    this.modelListings = []
    this.discoverySeq += 1
    this.discoveryCandidates = []
    this.discoveryLoading = false
    this.discoveryError = ''
    this.discoveryNotice = ''
    this.savingModelId = ''
  }

  // PR2-T2 ticket #83 follow-up (2026-09-08): 保存 — commit drafts 到 parent + 触发 save
  saveEdit = (vendorId: string): void => {
    const pendingModel: string = this.newModelInput.trim()
    if (pendingModel.length > 0) {
      if (!this.localModels.includes(pendingModel)) {
        this.localModels = [...this.localModels, pendingModel]
      }
      this.attachDraftModel(vendorId, pendingModel)
      this.newModelInput = ''
    }
    this.onApiKeyChange(vendorId, this.apiKeyInput)
    const original: string[] | undefined = this.vendorModels[vendorId]
    const base: string[] = original !== undefined ? original : []
    for (const m of base) {
      if (!this.localModels.includes(m)) {
        this.onRemoveModel(vendorId, m)
      }
    }
    for (const m of this.localModels) {
      if (!base.includes(m)) {
        this.onAddModel(vendorId, m)
      }
    }
    if (this.localActiveModel.length > 0) {
      this.onSelectModel(vendorId, this.localActiveModel)
      const parsedWindow: number = Number(this.localContextWindow)
      this.onContextWindowChange(vendorId, this.localActiveModel, parsedWindow)
    }
    this.originalApiKeyInput = this.apiKeyInput
    this.onSaveEdit(vendorId)
  }

  private contextWindowFor(vendorId: string, model: string): number {
    const value: number | undefined = this.modelContextWindows[vendorId + '::' + model]
    return value === undefined ? 65536 : value
  }

  // 优先用 catalog/已保存 listing 的 contextWindow, 避免把 catalog 模型显示成 65536
  private initialContextWindow = (vendorId: string, modelId: string): number => {
    for (const listing of this.modelListings) {
      if (listing.id === modelId && listing.contextWindow > 0) {
        return listing.contextWindow
      }
    }
    return this.contextWindowFor(vendorId, modelId)
  }

  // ===== 2026-10-25 Phase 1.5: 模型 chip / discovery =====

  private hasBuiltinCatalog = (vendorId: string): boolean => {
    const catalog: ProviderCatalog | null = getProviderCatalog(vendorId)
    return catalog !== null && catalog.models.length > 0
  }

  // token 数 → 只读副标题, 不在 UI 里推导能力
  private formatContextWindow = (tokens: number): string => {
    if (tokens >= 1000000) {
      return (Math.round(tokens / 100000) / 10).toString() + 'M 上下文'
    }
    if (tokens >= 1000) {
      return Math.round(tokens / 1000).toString() + 'K 上下文'
    }
    return tokens.toString() + ' 上下文'
  }

  private containsModelId = (listings: ModelListing[], id: string): boolean => {
    for (const listing of listings) {
      if (listing.id === id) { return true }
    }
    return false
  }

  // catalog chip: 只改本地 draft, 仍由「保存」提交(保持原交互)
  private selectCatalogModel = (vendorId: string, listing: ModelListing): void => {
    const m: string = listing.id
    this.localActiveModel = m
    this.localContextWindow = listing.contextWindow > 0
      ? listing.contextWindow.toString()
      : this.contextWindowFor(vendorId, m).toString()
  }

  // 只负责 chip 清单与选中态; localModels 的 draft 追加由调用方保持原交互
  private attachDraftModel = (vendorId: string, model: string): void => {
    const t: string = model.trim()
    if (t.length === 0) { return }
    if (!this.containsModelId(this.modelListings, t)) {
      const effort: ModelEffortInfo = { supportedLevels: [], defaultLevel: '' }
      const listing: ModelListing = {
        id: t,
        displayName: t,
        providerId: vendorId,
        contextWindow: 0,
        maxOutputTokens: 0,
        inputModalities: [],
        effort: effort,
        source: 'user',
      }
      this.modelListings = [...this.modelListings, listing]
    }
    this.localActiveModel = t
    this.localContextWindow = this.contextWindowFor(vendorId, t).toString()
  }

  private removeDraftModel = (vendorId: string, m: string): void => {
    this.modelListings = this.modelListings.filter(
      (listing: ModelListing): boolean => listing.id !== m
    )
    this.localModels = this.localModels.filter((item: string): boolean => item !== m)
    if (this.localActiveModel === m) {
      this.localActiveModel = this.localModels.length > 0 ? this.localModels[0] : ''
      this.localContextWindow = this.localActiveModel.length > 0
        ? this.initialContextWindow(vendorId, this.localActiveModel).toString()
        : '65536'
    }
  }

  // discovery 只取候选, 绝不在这里写 preferences
  private openDiscovery = (vendorId: string): void => {
    if (this.discoveryLoading) { return }
    this.discoverySeq += 1
    const seq: number = this.discoverySeq
    this.discoveryLoading = true
    this.discoveryError = ''
    this.discoveryNotice = ''
    this.discoveryCandidates = []
    this.onDiscoverModels(vendorId).then((result: DiscoveryResult): void => {
      if (seq !== this.discoverySeq) { return }
      this.discoveryLoading = false
      if (this.editingVendorId !== vendorId) { return }
      if (!result.ok) {
        this.discoveryError = this.discoveryMessage(result)
        return
      }
      const fresh: ModelListing[] = []
      for (const listing of result.models) {
        if (!this.containsModelId(this.modelListings, listing.id)) {
          fresh.push(listing)
        }
      }
      this.discoveryCandidates = fresh
      this.discoveryNotice = fresh.length > 0
        ? '新增 ' + fresh.length.toString() + ' 个候选，点击 chip 保存'
        : '清单中的模型均已在列'
    }).catch((e: Error): void => {
      if (seq !== this.discoverySeq) { return }
      this.discoveryLoading = false
      if (this.editingVendorId !== vendorId) { return }
      this.discoveryError = '获取模型清单失败：' + e.message
    })
  }

  private discoveryMessage = (result: DiscoveryResult): string => {
    const code: string = result.errorCode
    if (code === 'DISCOVERY_TOO_LARGE') { return '模型清单超过 4 MiB，已拒绝加载' }
    if (code === 'DISCOVERY_PARSE_FAILED' || code === 'DISCOVERY_PARSE_ERROR') {
      return '返回内容不是可识别的模型清单'
    }
    if (code === 'DISCOVERY_TIMEOUT') { return '请求超时（15 秒），请检查网络或 Base URL' }
    if (code === 'DISCOVERY_EMPTY_LIST') { return '服务端返回的模型清单为空' }
    if (code === 'DISCOVERY_INVALID_BASE_URL') { return '该提供商未配置 Base URL' }
    if (code === 'DISCOVERY_NO_API_KEY') { return '请先填写该提供商的 API Key' }
    if (code === 'DISCOVERY_NETWORK_ERROR') { return '网络请求失败，请检查网络或 Base URL' }
    if (code === 'DISCOVERY_HTTP_ERROR') {
      return result.errorReason.length > 0
        ? '服务端返回错误：' + result.errorReason
        : '服务端返回错误'
    }
    return '获取模型清单失败（' + code + '）'
  }

  // 用户显式点「未保存」chip 才落盘; 成功后 chip 变为已选
  private commitCandidate = (vendorId: string, listing: ModelListing): void => {
    if (this.savingModelId.length > 0) { return }
    this.savingModelId = listing.id
    this.discoveryError = ''
    this.onCommitModel(vendorId, listing.id, listing.contextWindow).then((ok: boolean): void => {
      this.savingModelId = ''
      if (this.editingVendorId !== vendorId) { return }
      if (!ok) {
        this.discoveryError = '模型保存失败，请重试'
        return
      }
      this.discoveryCandidates = this.discoveryCandidates.filter(
        (item: ModelListing): boolean => item.id !== listing.id
      )
      if (!this.containsModelId(this.modelListings, listing.id)) {
        const saved: ModelListing = {
          id: listing.id,
          displayName: listing.displayName,
          providerId: listing.providerId,
          contextWindow: listing.contextWindow,
          maxOutputTokens: listing.maxOutputTokens,
          inputModalities: listing.inputModalities,
          effort: listing.effort,
          source: 'user',
        }
        this.modelListings = [...this.modelListings, saved]
      }
      this.localActiveModel = listing.id
      this.localContextWindow = listing.contextWindow > 0
        ? listing.contextWindow.toString()
        : this.contextWindowFor(vendorId, listing.id).toString()
      if (!this.localModels.includes(listing.id)) {
        this.localModels = [...this.localModels, listing.id]
      }
      this.discoveryNotice = ''
    }).catch((_e: Error): void => {
      this.savingModelId = ''
      if (this.editingVendorId !== vendorId) { return }
      this.discoveryError = '模型保存失败，请重试'
    })
  }

  build() {
    Column() {
      // 5 预设 vendor + 用户添加的 custom vendors
        ForEach(PROVIDERS,
        (item: ProviderConfig): void => {
          this.renderVendorRow(item.id, item.vendorName, item.baseUrl, item.defaultModel)
        }
      )

      ForEach(this.customVendors,
        (item: CustomVendorConfig): void => {
          if (item.id !== undefined && item.id.length > 0) {
            this.renderVendorRow(item.id, item.vendorName, item.baseUrl, item.model)
          }
        }
      )

      // [+ 添加新供应商] 按钮 — 统一设计语言(透明 + 虚线 + MINT 文字)
      Row() {
        Text('+ 添加新供应商')
          .fontSize(F_SM)
          .fontColor(MINT)
          .fontWeight(W_MEDIUM)
      }
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.Center)
      .border({ width: 1, style: BorderStyle.Dashed, color: MINT_BORDER })
      .borderRadius(R_MD)
      .margin({ top: S_2, bottom: S_4 })
      .onClick((): void => {
        this.addCustomModalOpen = true
      })

      // PR2-T2 P3: 添加新供应商 modal — Stack overlay + 4 字段卡片
      if (this.addCustomModalOpen) {
        this.renderAddCustomModal()
      }
    }
  }

  // PR2-T2: 单个 vendor row(重构:用 common tokens 统一视觉,Text 字符 radio + 卡片化)
  @Builder
  renderVendorRow(itemId: string, vendorName: string, baseUrl: string, defaultModel: string) {
    Column() {
      // 主行:radio + 厂商名 + baseUrl + 编辑 button(卡片化)
      Row() {
        // Radio:Text 字符 ● / ○(真机一定渲染;Circle 之前不渲染)
        Text(this.currentVendorId === itemId ? '●' : '○')
          .fontSize(20)
          .fontColor(this.currentVendorId === itemId ? MINT : TEXT_3)
          .margin({ right: S_2 })
          .width(16)

        // 厂商名 + NEW badge(内联)+ baseUrl(纵向堆叠)
        Column() {
          Row() {
            Text(vendorName)
              .fontSize(F_SM)
              .fontColor(TEXT)
              .fontWeight(W_MEDIUM)
            // PR2-T2 polish ticket #81 task A4: 新加 custom vendor 显示 NEW badge
            if (this.isNewVendorIds.has(itemId)) {
              Text('NEW')
                .fontSize(F_XS)
                .fontColor(BG_DARK)
                .fontWeight(W_SEMIBOLD)
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor(MINT)
                .borderRadius(3)
                .margin({ left: 6 })
            }
          }
          .alignItems(VerticalAlign.Center)
          Text(baseUrl.replace(/^https?:\/\//, ''))
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // PR2-T2 ticket #83 follow-up (2026-09-08): 恢复 编辑 button(click-to-expand)
        Text('编辑')
          .fontSize(F_XS)
          .fontColor(MINT)
          .fontWeight(W_MEDIUM)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .border({ width: 1, color: MINT_BORDER })
          .borderRadius(R_SM)
          .onClick((): void => {
            const opening: boolean = this.editingVendorId !== itemId
            if (opening) {
              this.openEdit(itemId)
            } else {
              this.cancelEdit()
            }
          })
      }
      .width('100%')
      .padding({ left: S_3, right: S_3, top: S_3, bottom: S_3 })
      // v6 设计稿(PR2-T2 polish ticket #81 task A5):success-dim bg + border-left 3px solid
      .backgroundColor(this.currentVendorId === itemId ? SUCCESS_DIM : 'transparent')
      .border({
        width: { left: this.currentVendorId === itemId ? 3 : 0, top: 0, right: 0, bottom: 0 },
        color: { left: MINT },
      })
      .borderRadius(R_MD)
      .margin({ top: S_2 })
      .onClick((): void => {
        this.onSelect(itemId)
      })

      // "currently active" badge 已删除 — 选中状态由行高亮(success-dim bg + border-left 3px)足够标识
      // 决策记录: ADR-0015(2026-09-08 双轴审查后 UX 简化)

      // PR2-T2 ticket #83 follow-up (2026-09-08): 恢复 click-to-expand panel
      if (this.editingVendorId === itemId) {
        Column() {
          Text(`${vendorName} · ${defaultModel}`)
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ bottom: S_2 })

          // PR2-T2 ticket #83 L3 (2026-09-08): API Key 输入(draft — 不再 onChange 立即 push)
          TextInput({ text: this.apiKeyInput, placeholder: 'API Key(per-vendor)' })
            .type(InputType.Password)
            .width('100%')
            .height(36)
            .fontSize(F_SM)
            .fontColor(TEXT)
            .placeholderColor(TEXT_4)
            .backgroundColor(BG_CARD)
            .border({ width: 1, color: BORDER })
            .borderRadius(R_SM)
            .padding({ left: S_2 })
            .margin({ bottom: S_3 })
            .onChange((v: string): void => {
              this.apiKeyInput = v
              this.onApiKeyChange(itemId, v)
            })

          Row() {
            Text('模型目录')
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .fontWeight(W_MEDIUM)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: S_2 })

          // Phase 1.5: catalog 为空的 vendor 才提供 discovery
          if (!this.hasBuiltinCatalog(itemId)) {
            Text('未提供内置清单')
              .fontSize(F_XS)
              .fontColor(TEXT_4)
              .width('100%')
              .margin({ bottom: S_1 })
            Row() {
              if (this.discoveryLoading) {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color(MINT)
                  .margin({ right: 4 })
              }
              Text(this.discoveryLoading ? '正在获取…' : '获取模型清单')
                .fontSize(F_XS)
                .fontColor(this.discoveryLoading ? TEXT_3 : MINT)
                .fontWeight(W_MEDIUM)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .border({ width: 1, color: this.discoveryLoading ? BORDER : MINT_BORDER })
                .borderRadius(R_SM)
                .opacity(this.discoveryLoading ? 0.6 : 1)
                .onClick((): void => {
                  this.openDiscovery(itemId)
                })
              Text('候选需点击后才保存')
                .fontSize(F_XS)
                .fontColor(TEXT_4)
                .margin({ left: S_2 })
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: S_2 })
          }

          if (this.discoveryError.length > 0) {
            Text(this.discoveryError)
              .fontSize(F_XS)
              .fontColor(ERROR_TEXT)
              .width('100%')
              .margin({ bottom: S_2 })
          }
          if (this.discoveryNotice.length > 0) {
            Text(this.discoveryNotice)
              .fontSize(F_XS)
              .fontColor(TEXT_3)
              .width('100%')
              .margin({ bottom: S_2 })
          }

          // chip 来源: 已保存(catalog / vendor_models) + 本次 discovery 候选(未保存)
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start,
            alignItems: ItemAlign.Center,
          }) {
            ForEach(this.modelListings,
              (listing: ModelListing): void => {
                this.renderModelChip(itemId, listing, false)
              },
              (listing: ModelListing): string => itemId + '::' + listing.id
            )
            ForEach(this.discoveryCandidates,
              (listing: ModelListing): void => {
                this.renderModelChip(itemId, listing, true)
              },
              (listing: ModelListing): string => itemId + '::unsaved::' + listing.id
            )
            if (this.modelListings.length === 0 && this.discoveryCandidates.length === 0) {
              Text('暂无模型，可获取清单或手动输入')
                .fontSize(F_XS)
                .fontColor(TEXT_4)
                .padding({ top: 4, bottom: 4 })
            }
          }
          .width('100%')
          .margin({ bottom: S_2 })

          // 添加 model 输入(draft — 加到 localModels,不立即 push)
          Row() {
            TextInput({ placeholder: '输入模型', text: this.newModelInput })
              .layoutWeight(1)
              .height(32)
              .fontSize(F_SM)
              .placeholderFont({ size: F_XS })
              .placeholderColor(TEXT_4)
              .backgroundColor(BG_CARD)
              .border({ width: 1, color: BORDER })
              .borderRadius(R_SM)
              .padding({ left: S_2 })
              .onChange((v: string): void => { this.newModelInput = v })
              .onSubmit((): void => {
                const m: string = this.newModelInput.trim()
                if (m.length > 0) {
                  if (!this.localModels.includes(m)) {
                    this.localModels = [...this.localModels, m]
                  }
                  this.attachDraftModel(itemId, m)
                  this.newModelInput = ''
                }
              })
            Text('+')
              .fontSize(18)
              .fontColor(MINT)
              .fontWeight(W_SEMIBOLD)
              .padding({ left: 10, right: 10 })
              .margin({ left: S_2 })
              .border({ width: 1, color: MINT_BORDER })
              .borderRadius(R_SM)
              .onClick((): void => {
                const m: string = this.newModelInput.trim()
                if (m.length > 0) {
                  if (!this.localModels.includes(m)) {
                    this.localModels = [...this.localModels, m]
                  }
                  this.attachDraftModel(itemId, m)
                  this.newModelInput = ''
                }
              })
          }
          .width('100%')
          .margin({ top: S_2 })

          Text('上下文窗口（token）')
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_MEDIUM)
            .margin({ top: S_3, bottom: S_2 })
          TextInput({ placeholder: '65536', text: this.localContextWindow })
            .width('100%')
            .height(32)
            .fontSize(F_SM)
            .inputFilter('[0-9]*')
            .backgroundColor(BG_CARD)
            .border({ width: 1, color: BORDER })
            .borderRadius(R_SM)
            .padding({ left: S_2 })
            .onChange((v: string): void => { this.localContextWindow = v })

          // PR2-T2 ticket #83 follow-up (2026-09-08): 取消 / 保存 2 按钮(draft 提交入口)
          Row() {
            Text('取消')
              .fontSize(F_SM)
              .fontColor(TEXT_3)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding(8)
              .border({ width: 1, color: BORDER })
              .borderRadius(R_SM)
              .onClick((): void => {
                this.cancelEdit()
              })
            Text('保存')
              .fontSize(F_SM)
              .fontColor(BG_DARK)
              .fontWeight(W_SEMIBOLD)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding(8)
              .backgroundColor(MINT)
              .borderRadius(R_SM)
              .margin({ left: S_2 })
              .onClick((): void => {
                this.saveEdit(itemId)
              })
          }
          .width('100%')
          .margin({ top: S_2 })
        }
        .width('100%')
        .padding(S_3)
        .backgroundColor(BG_CARD)
        .borderRadius(R_MD)
        .margin({ top: 2, bottom: S_2 })
      }
    }
  }

  // 2026-10-25 Phase 1.5: 单个模型 chip
  // unsaved=true = discovery 候选; 点击才落盘, 由 commitCandidate 处理
  @Builder
  renderModelChip(vendorId: string, listing: ModelListing, unsaved: boolean) {
    Row() {
      Column() {
        Row() {
          Text(listing.displayName)
            .fontSize(F_XS)
            .fontColor(this.localActiveModel === listing.id ? BG_DARK : TEXT)
            .fontWeight(W_MEDIUM)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (unsaved) {
            Text('未保存')
              .fontSize(F_XS)
              .fontColor(MINT)
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
        if (listing.contextWindow > 0) {
          Text(this.formatContextWindow(listing.contextWindow))
            .fontSize(F_XS)
            .fontColor(this.localActiveModel === listing.id ? BG_DARK : TEXT_3)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .onClick((): void => {
        if (unsaved) {
          this.commitCandidate(vendorId, listing)
        } else {
          this.selectCatalogModel(vendorId, listing)
        }
      })

      if (!unsaved && listing.source === 'user') {
        Text('×')
          .fontSize(16)
          .fontColor(this.localActiveModel === listing.id ? BG_DARK : TEXT_3)
          .padding({ left: 8 })
          .onClick((): void => {
            this.removeDraftModel(vendorId, listing.id)
          })
      }
    }
    .padding({ left: S_2, right: S_2, top: 6, bottom: 6 })
    .margin({ right: S_2, top: S_2 })
    .backgroundColor(this.localActiveModel === listing.id ? MINT : BG_DARK)
    .border({ width: 1, color: this.localActiveModel === listing.id ? MINT : BORDER })
    .borderRadius(R_SM)
    .opacity(this.savingModelId === listing.id ? 0.6 : 1)
  }

  // PR2-T2 P3: 添加新供应商 modal builder(Stack overlay + 卡片)
  // 4 字段:厂商显示名 / Base URL / API Key / 首个模型
  // 提交:校验 4 字段非空 → 通知 ViewModel + 关闭 modal + 重置字段
  // 取消:关闭 modal + 重置字段
  @Builder
  renderAddCustomModal() {
    Stack() {
      // 遮罩层
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(0.6)
        .onClick((): void => {
          this.addCustomModalOpen = false
          this.newVendorName = ''
          this.newVendorBaseUrl = ''
          this.newVendorApiKey = ''
          this.newVendorModel = ''
        })

      // 卡片层(用 common tokens 统一视觉)
      Column() {
        Text('添加新供应商')
          .fontSize(F_MD)
          .fontWeight(W_SEMIBOLD)
          .fontColor(TEXT)
          .margin({ bottom: S_3 })

        Text('厂商显示名')
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ bottom: 4 })
        TextInput({ placeholder: '例如:我的公司内网 LLM', text: this.newVendorName })
          .width('100%')
          .height(36)
          .fontSize(F_SM)
          .backgroundColor(BG_DARK)
          .border({ width: 1, color: BORDER })
          .borderRadius(R_SM)
          .padding({ left: S_2 })
          .margin({ bottom: S_2 })
          .onChange((v: string): void => { this.newVendorName = v })

        Text('Base URL')
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ bottom: 4 })
        TextInput({ placeholder: 'https://llm.example.com/v1', text: this.newVendorBaseUrl })
          .width('100%')
          .height(36)
          .fontSize(F_SM)
          .backgroundColor(BG_DARK)
          .border({ width: 1, color: BORDER })
          .borderRadius(R_SM)
          .padding({ left: S_2 })
          .margin({ bottom: S_2 })
          .onChange((v: string): void => { this.newVendorBaseUrl = v })

        Text('API Key')
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ bottom: 4 })
        TextInput({ placeholder: 'sk-••••••••••••••', text: this.newVendorApiKey })
          .width('100%')
          .height(36)
          .fontSize(F_SM)
          .backgroundColor(BG_DARK)
          .border({ width: 1, color: BORDER })
          .borderRadius(R_SM)
          .padding({ left: S_2 })
          .margin({ bottom: S_2 })
          .type(InputType.Password)
          .onChange((v: string): void => { this.newVendorApiKey = v })

        Text('首个模型 ID(将设为当前活跃)')
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .margin({ bottom: 4 })
        TextInput({ placeholder: '例如:my-llm-v1', text: this.newVendorModel })
          .width('100%')
          .height(36)
          .fontSize(F_SM)
          .backgroundColor(BG_DARK)
          .border({ width: 1, color: BORDER })
          .borderRadius(R_SM)
          .padding({ left: S_2 })
          .margin({ bottom: S_3 })
          .onChange((v: string): void => { this.newVendorModel = v })

        Row() {
          Text('取消')
            .fontSize(F_SM)
            .fontColor(TEXT_3)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding(8)
            .border({ width: 1, color: BORDER })
            .borderRadius(R_SM)
            .onClick((): void => {
              this.addCustomModalOpen = false
              this.newVendorName = ''
              this.newVendorBaseUrl = ''
              this.newVendorApiKey = ''
              this.newVendorModel = ''
            })
          Text('添加')
            .fontSize(F_SM)
            .fontColor(BG_DARK)
            .fontWeight(W_SEMIBOLD)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding(8)
            .backgroundColor(MINT)
            .borderRadius(R_SM)
            .margin({ left: S_2 })
            .onClick((): void => {
              const n: string = this.newVendorName.trim()
              const b: string = this.newVendorBaseUrl.trim()
              const k: string = this.newVendorApiKey.trim()
              const m: string = this.newVendorModel.trim()
              if (n.length > 0 && b.length > 0 && k.length > 0 && m.length > 0) {
                const newId: string = this.onAddVendorConfirm({ name: n, baseUrl: b, apiKey: k, firstModel: m })
                if (newId.length > 0) {
                  this.isNewVendorIds.add(newId)
                }
                this.addCustomModalOpen = false
                this.newVendorName = ''
                this.newVendorBaseUrl = ''
                this.newVendorApiKey = ''
                this.newVendorModel = ''
              }
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(S_4)
      .backgroundColor(BG_CARD)
      .border({ width: 1, color: BORDER })
      .borderRadius(R_MD)
    }
    .width('100%')
    .height('100%')
  }
}
