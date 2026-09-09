/**
 * FileName: VendorPicker.ets — 厂商选择器(PR2-T2 UI 重构)
 *
 * 路径: entry/src/main/ets/pages/AiSettings/VendorPicker.ets
 * 职责: 渲染 5 预设厂商(DeepSeek/通义/GLM/Kimi/豆包) + 用户添加的自定义 vendor;
 *       每行右侧 [编辑] 按钮展开该 row 下方 panel(API Key 输入 + 模型目录 + 添加模型 + 取消/保存)。
 *       底部 [+ 添加新供应商] 按钮触发父级弹 modal(P3)。
 * 依赖: common(providers.ts: PROVIDERS 常量 + ProviderConfig 类型)
 *
 * 数据流:
 *   AiSettingsPage.vm.vendorId → VendorPicker.props.currentVendorId
 *   onSelect(id) → vm.selectVendor(id)
 *   onAddCustom() → vm.openAddCustomVendor()
 *   编辑 button 自管 @State editingVendorId(单真理源,不再通知 ViewModel)
 *   panel 内 取消/保存 2 按钮:
 *     取消: discard local draft, collapse panel
 *     保存: commit local draft 到 parent via onApiKeyChange / onAddModel / onRemoveModel, 再调 onSaveEdit 触发 vm.save()
 *
 * PR2-T2 ticket #83 follow-up (2026-09-08): 重写为 draft pattern
 *   - @State apiKeyInput + @State localModels(本地 draft,不在 onChange 立即 push 到 parent)
 *   - 取消 真正 discard,保存 真正 commit
 *   - 之前 always-visible 改动被 revert(用户要回折叠)
 *
 * 5 预设 vendor(2026-09 一手信源调研):
 *   DeepSeek   · deepseek-v4-pro     · api.deepseek.com
 *   通义千问    · qwen3-max          · dashscope.aliyuncs.com/compatible-mode/v1
 *   智谱 GLM   · glm-5.3            · open.bigmodel.cn/api/paas/v4/
 *   Kimi 月之暗面 · kimi-k2.6      · api.moonshot.cn/v1
 *   字节豆包    · doubao-seed-1.6  · ark.cn-beijing.volces.com/api/v3
 *
 * ArkTS 1.1 strict 适配:
 *   - 显式类型标注(: string / : void 等)
 *   - 不使用 any / for-in / as-casts / 尖括号断言
 *   - 显式 list 类型 ProviderConfig[]
 *   - 仅用 @Prop 与 @State 装饰器(@Entry/@Component 除外)
 */

import { PROVIDERS } from 'common';
import type { CustomVendorConfig, ProviderConfig } from 'common';
import {
  MINT, MINT_BORDER, BG_CARD, BG_DARK, TEXT, TEXT_2, TEXT_3, TEXT_4, BORDER,
  F_XS, F_SM, F_MD, W_NORMAL, W_MEDIUM, W_SEMIBOLD,
  R_SM, R_MD, S_2, S_3, S_4,
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

@Component
export struct VendorPicker {
  // 当前选中的 vendor
  @Prop currentVendorId: string = 'deepseek';

  // 预设 vendor 列表(caller 可覆盖,默认从 common.PROVIDERS 取)
  providers: ProviderConfig[] = [];

  // PR2-T2 ticket #83 L1+L2+L3 (2026-09-08): per-vendor 持久化数据(由 parent 提供)
  @Prop vendorApiKeys: Record<string, string> = {};
  @Prop vendorModels: Record<string, string[]> = {};
  @Prop customVendors: CustomVendorConfig[] = [];

  // PR2-T2 ticket #83 follow-up (2026-09-08): 恢复 click-to-expand
  @State editingVendorId: string | null = null;

  // PR2-T2 ticket #83 follow-up (2026-09-08): local draft state
  // 不在 onChange/onAdd/onRemove 立即 push 到 parent — 等保存按钮 一次性 commit
  @State apiKeyInput: string = '';
  @State localModels: string[] = [];

  // PR2-T2: panel 内 model 输入(仅 input 状态,实际数据走 local localModels)
  @State newModelInput: string = '';

  // PR2-T2 P3: 添加新供应商 modal 状态(单真理源 — modal 是纯 UI 状态,VendorPicker 自管)
  @State addCustomModalOpen: boolean = false;
  @State newVendorName: string = '';
  @State newVendorBaseUrl: string = '';
  @State newVendorApiKey: string = '';
  @State newVendorModel: string = '';

  // PR2-T2 polish ticket #81 task A4: 新加 custom vendor 标记(session 内有效,无需持久化)
  @State isNewVendorIds: Set<string> = new Set();

  onSelect: (id: string) => void = (_id: string): void => {};
  onAddCustom: () => void = (): void => {};

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

  // PR2-T2 ticket #83 follow-up (2026-09-08): 保存按钮 触发 parent save
  onSaveEdit: (vendorId: string) => void = (_vendorId: string): void => {};

  // PR2-T2 ticket #83 follow-up (2026-09-08): 展开 vendor 编辑 panel
  openEdit = (vendorId: string): void => {
    this.editingVendorId = vendorId
    // initialize drafts from parent's current state
    this.apiKeyInput = this.vendorApiKeys[vendorId] ?? ''
    const current: string[] | undefined = this.vendorModels[vendorId]
    this.localModels = current !== undefined ? [...current] : []
    this.newModelInput = ''
  }

  // PR2-T2 ticket #83 follow-up (2026-09-08): 取消 — discard local drafts, collapse panel
  cancelEdit = (): void => {
    this.editingVendorId = null
    this.apiKeyInput = ''
    this.localModels = []
    this.newModelInput = ''
  }

  // PR2-T2 ticket #83 follow-up (2026-09-08): 保存 — commit drafts 到 parent + 触发 save
  saveEdit = (vendorId: string): void => {
    // commit API key
    this.onApiKeyChange(vendorId, this.apiKeyInput)
    // commit model list via diff
    const original: string[] | undefined = this.vendorModels[vendorId]
    const base: string[] = original !== undefined ? original : []
    // remove what's in base but not in local
    for (const m of base) {
      if (!this.localModels.includes(m)) {
        this.onRemoveModel(vendorId, m)
      }
    }
    // add what's in local but not in base
    for (const m of this.localModels) {
      if (!base.includes(m)) {
        this.onAddModel(vendorId, m)
      }
    }
    // clear drafts + collapse
    this.editingVendorId = null
    this.apiKeyInput = ''
    this.localModels = []
    this.newModelInput = ''
    // trigger parent save (persist to LlmConfig)
    this.onSaveEdit(vendorId)
  }

  build() {
    Column() {
      // 5 预设 vendor + 用户添加的 custom vendors
      ForEach(this.providers.length > 0 ? this.providers : PROVIDERS,
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
        this.onAddCustom()
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
            })

          Text('模型目录')
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_MEDIUM)
            .margin({ bottom: S_2 })

          // PR2-T2 ticket #83 follow-up (2026-09-08): 列表用 local localModels(不立即同步 parent)
          ForEach(this.localModels,
            (m: string): void => {
              Row() {
                Text('•')
                  .fontSize(16)
                  .fontColor(MINT)
                  .margin({ right: 8 })
                  .width(12)
                Text(m)
                  .fontSize(F_SM)
                  .fontColor(TEXT)
                  .layoutWeight(1)
                Text('×')
                  .fontSize(16)
                  .fontColor(TEXT_3)
                  .padding(4)
                  .onClick((): void => {
                    this.localModels = this.localModels.filter((x: string): boolean => x !== m)
                  })
              }
              .width('100%')
              .padding({ left: S_2, right: S_2, top: 6, bottom: 6 })
              .borderRadius(R_SM)
            }
          )

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
                if (m.length > 0 && !this.localModels.includes(m)) {
                  this.localModels = [...this.localModels, m]
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
                if (m.length > 0 && !this.localModels.includes(m)) {
                  this.localModels = [...this.localModels, m]
                  this.newModelInput = ''
                }
              })
          }
          .width('100%')
          .margin({ top: S_2 })

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
