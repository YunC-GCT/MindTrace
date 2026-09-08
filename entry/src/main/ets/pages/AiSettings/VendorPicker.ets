/**
 * FileName: VendorPicker.ets — 厂商选择器(PR2-T2 UI 重构)
 *
 * 路径: entry/src/main/ets/pages/AiSettings/VendorPicker.ets
 * 职责: 渲染 5 预设厂商(DeepSeek/通义/GLM/Kimi/豆包) + 用户添加的自定义 vendor;
 *       每行右侧 [编辑] 按钮展开该 row 下方 panel(API Key + 模型目录 + 添加模型)。
 *       底部 [+ 添加新供应商] 按钮触发父级弹 modal(P3)。
 * 依赖: common(providers.ts: PROVIDERS 常量 + ProviderConfig 类型)
 *
 * 数据流:
 *   AiSettingsPage.vm.vendorId → VendorPicker.props.currentVendorId
 *   onSelect(id) → vm.selectVendor(id)(in-memory, save() 持久化)
 *   onAddCustom() → vm.openAddCustomVendor()(父级弹 modal)
 *   编辑 button 自管 @State editingVendorId(单真理源,不再通知 ViewModel)
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
import type { ProviderConfig } from 'common';
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

@Component
export struct VendorPicker {
  // 当前选中的 vendor
  @Prop currentVendorId: string = 'deepseek';

  // 预设 vendor 列表(caller 可覆盖,默认从 common.PROVIDERS 取)
  providers: ProviderConfig[] = [];

  // PR2-T2: 编辑 panel 展开状态(单真理源 — VendorPicker 自管,不通知 ViewModel)
  // null = 全折叠;非 null = 该 vendorId 对应 row 下 panel 展开
  @State editingVendorId: string | null = null;

  // PR2-T2: panel 内 model 状态(panel 自管,刷新页面会丢失 — 后续 PR 接 per-vendor models 持久化)
  @State models: string[] = [];
  @State activeModel: string = '';
  @State newModelInput: string = '';

  // PR2-T2 P3: 添加新供应商 modal 状态(单真理源 — modal 是纯 UI 状态,VendorPicker 自管)
  @State addCustomModalOpen: boolean = false;
  @State newVendorName: string = '';
  @State newVendorBaseUrl: string = '';
  @State newVendorApiKey: string = '';
  @State newVendorModel: string = '';

  // 回调
  onSelect: (id: string) => void = (_id: string): void => {};
  onEdit: (id: string) => void = (_id: string): void => {};
  onAddCustom: () => void = (): void => {};

  // PR2-T2 P3: 添加新 vendor 完成回调(把 cfg 传给 ViewModel,ViewModel 加到 customVendors + 切 vendorId)
  // ArkTS 1.1 strict 要求 callback 参数用 interface 声明,不允许 inline object literal as type
  onAddVendorConfirm: (cfg: AddCustomVendorCfg) => void = (_cfg: AddCustomVendorCfg): void => {};

  build() {
    Column() {
      // 5 预设 vendor + 用户添加的 custom vendors
      ForEach(this.providers.length > 0 ? this.providers : PROVIDERS,
        (item: ProviderConfig): void => {
          this.renderVendorRow(item)
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
  renderVendorRow(item: ProviderConfig) {
    Column() {
      // 主行:radio + 厂商名 + baseUrl + 编辑 button(卡片化)
      Row() {
        // Radio:Text 字符 ● / ○(真机一定渲染;Circle 之前不渲染)
        Text(this.currentVendorId === item.id ? '●' : '○')
          .fontSize(20)
          .fontColor(this.currentVendorId === item.id ? MINT : TEXT_3)
          .margin({ right: S_2 })
          .width(16)

        // 厂商名 + baseUrl(纵向堆叠)
        Column() {
          Text(item.vendorName)
            .fontSize(F_SM)
            .fontColor(TEXT)
            .fontWeight(W_MEDIUM)
          Text(item.baseUrl.replace(/^https?:\/\//, ''))
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 编辑 button(Text + border 风格,避免 default blue Button)
        Text('编辑')
          .fontSize(F_XS)
          .fontColor(MINT)
          .fontWeight(W_MEDIUM)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .border({ width: 1, color: MINT_BORDER })
          .borderRadius(R_SM)
          .onClick((): void => {
            const opening: boolean = this.editingVendorId !== item.id
            this.editingVendorId = opening ? item.id : null
            if (opening) {
              this.models = [item.defaultModel]
              this.activeModel = item.defaultModel
            }
          })
      }
      .width('100%')
      .padding({ left: S_3, right: S_3, top: S_3, bottom: S_3 })
      .backgroundColor(this.currentVendorId === item.id ? '#0F2A22' : 'transparent')
      .border({ width: 1, color: this.currentVendorId === item.id ? MINT : BORDER })
      .borderRadius(R_MD)
      .margin({ top: S_2 })
      .onClick((): void => {
        this.onSelect(item.id)
      })

      // "当前" badge 行(整行卡片下,视觉强调当前选中状态)
      // v6 设计稿(PR2-T2 polish): filled MINT bg + white text(替代 outline mint 描边 pill)
      if (this.currentVendorId === item.id) {
        Row() {
          Text('当前活跃')
            .fontSize(F_XS)
            .fontColor('#FFFFFF')
            .fontWeight(W_SEMIBOLD)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor(MINT)
            .borderRadius(3)
        }
        .width('100%')
        .padding({ left: 16, top: 4, bottom: 6 })
      }

      // PR2-T2: 编辑 panel(完整版)— API Key 输入 + 模型目录 + 添加 model
      if (this.editingVendorId === item.id) {
        Column() {
          Text(`${item.vendorName} · ${item.defaultModel}`)
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .margin({ bottom: S_2 })

          // API Key 输入
          TextInput({ placeholder: 'API Key(per-vendor)' })
            .width('100%')
            .height(36)
            .fontSize(F_SM)
            .placeholderColor(TEXT_4)
            .backgroundColor(BG_CARD)
            .border({ width: 1, color: BORDER })
            .borderRadius(R_SM)
            .padding({ left: S_2 })
            .margin({ bottom: S_3 })

          Text('模型目录')
            .fontSize(F_XS)
            .fontColor(TEXT_3)
            .fontWeight(W_MEDIUM)
            .margin({ bottom: S_2 })
          ForEach(this.models,
            (m: string): void => {
              Row() {
                Text(this.activeModel === m ? '●' : '○')
                  .fontSize(16)
                  .fontColor(this.activeModel === m ? MINT : TEXT_3)
                  .margin({ right: 8 })
                  .width(12)
                Text(m)
                  .fontSize(F_SM)
                  .fontColor(TEXT)
                  .layoutWeight(1)
                if (this.models.length > 1) {
                  Text('×')
                    .fontSize(16)
                    .fontColor(TEXT_3)
                    .padding(4)
                    .onClick((): void => {
                      const next: string[] = []
                      for (const x of this.models) {
                        if (x !== m) { next.push(x) }
                      }
                      this.models = next
                      if (this.activeModel === m && next.length > 0) {
                        this.activeModel = next[0]
                      }
                    })
                }
              }
              .width('100%')
              .padding({ left: S_2, right: S_2, top: 6, bottom: 6 })
              .borderRadius(R_SM)
              .backgroundColor(this.activeModel === m ? '#0F2A22' : 'transparent')
              .onClick((): void => {
                this.activeModel = m
              })
            }
          )

          // 添加 model 输入
          Row() {
            TextInput({ placeholder: '输入模型名后回车', text: this.newModelInput })
              .layoutWeight(1)
              .height(32)
              .fontSize(F_SM)
              .placeholderColor(TEXT_4)
              .backgroundColor(BG_CARD)
              .border({ width: 1, color: BORDER })
              .borderRadius(R_SM)
              .padding({ left: S_2 })
              .onChange((v: string): void => { this.newModelInput = v })
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
                if (m.length > 0 && !this.models.includes(m)) {
                  this.models = [...this.models, m]
                  this.newModelInput = ''
                }
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
                this.onAddVendorConfirm({ name: n, baseUrl: b, apiKey: k, firstModel: m })
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
