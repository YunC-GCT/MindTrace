/**
 * EvidenceModeSection.ets — 回答证据策略选择
 *
 * 路径: entry/src/main/ets/pages/AiSettings/EvidenceModeSection.ets
 * 职责: 在 AI 设置页选择 strict / balanced / expansive 三档证据策略；
 *       纯展示组件，读写走 AiSettingsViewModel 与 LlmConfig。
 * 依赖: common 主题 token。
 */

import { BG_CARD, BORDER, MINT, TEXT, TEXT_3, R_MD, R_LG, F_XS, F_SM } from 'common';
import type { EvidenceMode } from 'common';

interface EvidenceOption {
  mode: EvidenceMode;
  label: string;
  hint: string;
}

const EVIDENCE_OPTIONS: EvidenceOption[] = [
  { mode: 'strict', label: '严格', hint: '判定服务不可用时，按「没有可用依据」处理。' },
  { mode: 'balanced', label: '平衡', hint: '默认。判定服务不可用时放行候选，保持回答可用。' },
  { mode: 'expansive', label: '宽松', hint: '跳过相关性判定，尽量多给候选。' },
];

@Component
export struct EvidenceModeSection {
  @Prop mode: EvidenceMode = 'balanced';
  onModeChange?: (mode: EvidenceMode) => void = (_mode: EvidenceMode): void => {};

  build() {
    Column() {
      Row() {
        Text('回答证据')
          .fontSize(F_SM)
          .fontColor(TEXT)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })

      Row({ space: 8 }) {
        ForEach(EVIDENCE_OPTIONS, (option: EvidenceOption): void => {
          Button(option.label)
            .layoutWeight(1)
            .fontSize(F_XS)
            .fontColor(this.mode === option.mode ? BG_CARD : TEXT)
            .backgroundColor(this.mode === option.mode ? MINT : '#0AFFFFFF')
            .borderRadius(R_MD)
            .height(36)
            .onClick((): void => {
              if (this.onModeChange) {
                this.onModeChange(option.mode);
              }
            });
        }, (option: EvidenceOption): string => option.mode)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })

      Row() {
        Text(this.hintFor(this.mode))
          .fontSize(F_XS)
          .fontColor(TEXT_3)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 0, bottom: 8 })
    }
    .width('100%')
    .borderRadius(R_LG)
    .backgroundColor(BG_CARD)
    .margin({ left: 8, right: 8 })
    .border({ width: 1, color: BORDER });
  }

  private hintFor(mode: EvidenceMode): string {
    for (let i = 0; i < EVIDENCE_OPTIONS.length; i += 1) {
      if (EVIDENCE_OPTIONS[i].mode === mode) {
        return EVIDENCE_OPTIONS[i].hint;
      }
    }
    return '';
  }
}
