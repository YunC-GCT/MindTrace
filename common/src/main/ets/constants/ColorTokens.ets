// ============================================================================
//  MindTrace 设计 Token — 令牌层
//  ----------------------------------------------------------------------------
//  对照: styles.css :root + app.js tc()/sc()
//  层级: 令牌层是所有视觉属性的唯一真相源 (single source of truth)
//
//  分类:
//    主色板 → 语义色 → 玻璃色 → 文字/边框 → 间距/圆角/字号 → 字重/行高/阴影
//  ============================================================================

// ========================================================================
//  主色板 (Palette) — 11 个
// ========================================================================
export const MINT: string         = "#FF5BE3B0"
export const MINT_DARK: string    = "#FF1F8F65"
export const MINT_LIGHT: string   = "#245BE3B0"
export const MINT_GLOW: string    = "#6B5BE3B0"
export const MINT_BORDER: string  = "#475BE3B0"
export const PURPLE: string       = "#FF8F95D3"
export const PURPLE_DARK: string  = "#FF7278BA"
export const PURPLE_LIGHT: string = "#248F95D3"
export const PINK: string         = "#FFD989A6"
export const PINK_LIGHT: string  = "#1AFF6B9D"   // PINK 10% (Hero 梯度收尾)
export const AMBER: string        = "#FFB8A7D9"
export const BG_DARK: string      = "#FF0A0C10"

// ========================================================================
//  扩展背景色
// ========================================================================
export const BG_CARD: string = "#FF10131A"
export const TAB_NAV_BG: string = "#FF12181C"
export const TAB_NAV_ACTIVE: string = "#FF68E2BC"
export const TAB_NAV_MUTED: string = "#FF8B9998"
export const TAB_NAV_BORDER: string = "#FF222C30"
export const TAB_AI_BG: string = "#FF090D10"
export const TAB_AI_BORDER: string = "#FF335E59"
export const TAB_AI_INNER_BORDER: string = "#FF203835"

// ========================================================================
//  语义色 (Semantic)
// ========================================================================
export const DANGER: string        = "#FF6B6B"    // 错误/删除 (软红)
export const DANGER_BRIGHT: string = "#FFEF4444"  // 高亮红 (高优先级/删除按钮)
export const WARNING: string       = "#FFFBBF24"  // 告警/中等置信度
export const SUCCESS: string       = MINT          // 成功 alias

// ========================================================================
//  玻璃色 (Glass) — 白色半透明阶梯，深色背景上叠层用
// ========================================================================
export const GLASS_8: string  = "#08FFFFFF"  // 8%  极淡玻璃
export const GLASS_10: string = "#1AFFFFFF"  // 10% 边框/按钮背景 (原 BORDER)
export const GLASS_14: string = "#0DFFFFFF"  // ~5%? AI 卡背景 (原硬编码)
// 注意: GLASS_10 与 BORDER 值相同，BORDER 保留作为语义别名

// ========================================================================
//  遮罩色 (Overlay)
// ========================================================================
export const OVERLAY_MASK: string     = "#80000000"  // 50% 黑 (AgentFloatWindow)
export const OVERLAY_MASK_SOLID: string = "#CC000000" // 80% 黑 (NoteDetailOverlay)

// ========================================================================
//  学科色 (Record)
// ========================================================================
export const SUBJECT_COLORS: Record<string, string> = {
  "数学分析": PINK,
  "高等代数": PURPLE,
  "空间解析几何": AMBER,
  "解析几何": AMBER,
}

// ========================================================================
//  类型色 (Record)
// ========================================================================
export const TYPE_COLORS: Record<string, string> = {
  "概念": MINT,
  "定理": PURPLE,
  "公式": PINK,
  "证明": AMBER,
  "证明题": AMBER,
  "计算": "#FF64B7C8",
  "计算题": "#FF64B7C8",
}

// ========================================================================
//  文字色 — 4 级
// ========================================================================
export const TEXT: string   = "#FFFFFFFF"
export const TEXT_2: string = "#FFB0B3C1"
export const TEXT_3: string = "#FF6B7280"
export const TEXT_4: string = "#FF4B5563"

// ========================================================================
//  边框色
// ========================================================================
export const BORDER: string = GLASS_10  // alias

// ========================================================================
//  间距 (Spacing) — 6 级 (vp)
// ========================================================================
export const S_1: number = 4
export const S_2: number = 8
export const S_3: number = 12
export const S_4: number = 16
export const S_5: number = 20
export const S_6: number = 24

// ========================================================================
//  圆角 (Radius) — 6 级 (vp)
// ========================================================================
export const R_SM: number  = 6
export const R_MD: number  = 8
export const R_LG: number  = 12
export const R_XL: number  = 16
export const R_2XL: number = 24
export const R_FULL: number = 9999

// ========================================================================
//  字号 (Font Size) — 8 级 (fp)
// ========================================================================
export const F_XS: number   = 11
export const F_SM: number   = 12
export const F_BASE: number = 14
export const F_MD: number   = 16
export const F_LG: number   = 18
export const F_XL: number   = 20
export const F_2XL: number  = 24
export const F_3XL: number  = 30

// ========================================================================
//  字重 (Font Weight) — 4 级
// ========================================================================
export const W_NORMAL: number = 400
export const W_MEDIUM: number = 500
export const W_SEMIBOLD: number = 600
export const W_BOLD: number = 700

// ========================================================================
//  行高 (Line Height) — 5 级 (vp)
// ========================================================================
export const LH_TIGHT: number  = 16
export const LH_BASE: number   = 18
export const LH_COMFORT: number = 20
export const LH_LOOSE: number  = 22
export const LH_HEADING: number = 30

// ========================================================================
//  阴影 (Shadow) — 预设
// ========================================================================
interface ShadowPreset {
  radius: number
  color: string
  offsetX: number
  offsetY: number
}

export const SHADOW_FAB: ShadowPreset = {
  radius: 28,
  color: "#595BE3B0",
  offsetX: 0,
  offsetY: 8,
}

export function SHADOW_GLOW_MINT(alpha: number): ShadowPreset {
  return {
    radius: 32,
    color: "rgba(91, 227, 176, " + alpha.toFixed(2) + ")",
    offsetX: 0,
    offsetY: 0,
  }
}

// ========================================================================
//  动画时长 (ms) — 对齐 v2-ui motion.css
// ========================================================================
export const DUR_INSTANT: number = 80     // 微交互 (hover/tap 反馈)
export const DUR_FAST: number    = 150    // 快过渡 (开关/显隐)
export const DUR_BASE: number    = 250    // 默认 (入场/切换/浮层)
export const DUR_SLOW: number    = 400    // 慢过渡 (展开/折叠)
export const DUR_SLOWER: number  = 600    // 更慢 (页面转场)
export const DUR_SLOWEST: number = 1200   // 最慢 (复杂动画)
export const DUR_BREATH: number  = 3000   // 光晕呼吸周期

// ========================================================================
//  缓动曲线 — 对齐 v2-ui motion.css
//  使用: 组件的 animation({ curve: Curve.FastOutSlowIn }) 等处
//  ArkTS 内置曲线对照:
//    EASE_SPRING  → Curve.FastOutSlowIn       (cubic-bezier(.2,.8,.3,1))
//    EASE_OUT     → Curve.LinearOutSlowIn      (cubic-bezier(.16,1,.3,1))
//    EASE_IN      → Curve.FastOutLinearIn      (cubic-bezier(.4,0,1,1))
//    EASE_IN_OUT  → Curve.EaseInOut            (cubic-bezier(.4,0,.2,1))
//    EASE_BOUNCE  → Curves.cubicBezier(.34,1.56,.64,1)  (手动指定)
// ========================================================================

// ========================================================================
//  屏幕尺寸 (vp) — 固定参考值
// ========================================================================
export const SCREEN_W: number = 377
export const SCREEN_H: number = 816

// ========================================================================
//  组件尺寸 (vp)
// ========================================================================
export const HEADER_H: number       = 60
export const FAB_SIZE: number       = 54
export const HERO_RING_SIZE: number = 120
export const NOTE_ICON_SIZE: number = 36
export const DOT_SIZE: number       = 8
export const AVATAR_SIZE: number    = 72
export const AI_SETTINGS_BTN_H: number = 44   // AiSettings 按钮/输入框高度

// ========================================================================
//  TabBar 组件尺寸 (vp)
// ========================================================================
export const TAB_BAR_HEIGHT: number = 94
export const TAB_ROW_HEIGHT: number = 70
export const TAB_CREST_HEIGHT: number = 24
export const TAB_CREST_WIDTH: number = 96
export const TAB_AI_SLOT_WIDTH: number = 74
export const TAB_LABEL_HEIGHT: number = 17
export const TAB_LABEL_GAP: number = 6
export const TAB_BOTTOM_PADDING: number = 7
export const TAB_ICON_SIZE: number  = 22
export const TAB_BTN_RADIUS: number = 14
export const AI_BTN_SIZE: number    = 56
export const AI_ICON_SIZE: number   = 30

// ========================================================================
//  TabBar 阴影
// ========================================================================

// ========================================================================
//  相机组件 (vp)
// ========================================================================
export const CAM_SHUTTER_OUTER: number = 68
export const CAM_SHUTTER_INNER: number = 54
export const CAM_BTN_SIZE: number      = 44
export const CAM_ALBUM_SIZE: number    = 52
export const CAM_CONFIRM_H: number     = 48
export const CAM_OVERLAY_BG: string    = "#FF0E1014"
export const CAM_PREVIEW_BG: string    = "#FF1A1A1A"
export const CAM_MASK: string          = "#CC000000"
export const SHADOW_AI_BTN: ShadowPreset = {
  radius: 20,
  color: "#284CCDA4",   // 草稿柔和光晕
  offsetX: 0,
  offsetY: 5,
}
