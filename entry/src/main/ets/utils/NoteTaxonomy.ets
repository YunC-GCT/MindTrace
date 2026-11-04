/**
 * NoteTaxonomy.ets — 笔记分类与学科颜色统一入口
 *
 * 路径: entry/src/main/ets/utils/NoteTaxonomy.ets
 * 职责: 集中管理笔记类型、旧类型别名、类型取色、类型图标和学科顺序取色。
 * 依赖: constants/ColorTokens
 *
 * 数据流:
 *   KnowledgeUnit.tags / NoteItem.type
 *     → normalizeNoteType / isKnownNoteType / typeColor / typeChar
 *     → Notes 页面统一渲染
 *
 * ArkTS 1.1 strict 适配:
 *   - 无 any/unknown
 *   - 无 C 风格 for
 */

import {
  MINT, PURPLE, PINK, AMBER,
  SUBJECT_COLORS, TYPE_COLORS,
} from 'common';
import { NOTE_TYPE_KEYS, normalizeNoteType } from 'common';

const SUBJECT_PALETTE: string[] = buildSubjectPalette();

export function typeChar(t: string): string {
  const type: string = normalizeNoteType(t);
  return type.length > 0 ? type.substring(0, 1) : '笔';
}

export function typeColor(t: string): string {
  const type: string = normalizeNoteType(t);
  const color: string | undefined = TYPE_COLORS[type];
  return color !== undefined ? color : '#FFA8A8B0';
}

export function typeGlassColor(t: string): string {
  return glassSurfaceColor(typeColor(t));
}

export function subjectColor(_subject: string, index: number = 0): string {
  return subjectColorByIndex(index);
}

export function subjectGlassColor(subject: string, index: number = 0): string {
  return glassSurfaceColor(subjectColor(subject, index));
}

export function subjectBorderColor(subject: string, index: number = 0): string {
  return borderToneColor(subjectColor(subject, index));
}

export function glassToneColor(color: string): string {
  return colorWithAlpha(color, '26');
}

export function glassSurfaceColor(color: string): string {
  return colorWithAlpha(color, '20');
}

export function glassHighlightColor(color: string): string {
  return colorWithAlpha(color, '36');
}

export function glassShadowColor(color: string): string {
  return colorWithAlpha(color, '1A');
}

export function borderToneColor(color: string): string {
  return colorWithAlpha(color, '66');
}

export function subjectColorByIndex(index: number): string {
  const size: number = SUBJECT_PALETTE.length;
  if (size <= 0) {
    return PURPLE;
  }
  const normalized: number = index >= 0 ? index : 0;
  return SUBJECT_PALETTE[normalized % size];
}

function buildSubjectPalette(): string[] {
  const palette: string[] = [];
  const subjectKeys: string[] = Object.keys(SUBJECT_COLORS);
  for (const key of subjectKeys) {
    appendUnique(palette, SUBJECT_COLORS[key]);
  }
  appendUnique(palette, MINT);
  appendUnique(palette, '#FF4FC99B');
  appendUnique(palette, '#FF64B7C8');
  appendUnique(palette, '#FF7CC9B3');
  appendUnique(palette, PURPLE);
  appendUnique(palette, '#FF86B7D8');
  appendUnique(palette, AMBER);
  appendUnique(palette, PINK);
  appendUnique(palette, '#FF5FAE91');
  appendUnique(palette, '#FF82C7BE');
  appendUnique(palette, '#FFA5B8D4');
  appendUnique(palette, '#FF8BCFB5');
  return palette;
}

function appendUnique(target: string[], color: string | undefined): void {
  if (color !== undefined && color.length > 0 && target.indexOf(color) < 0) {
    target.push(color);
  }
}

function colorWithAlpha(color: string, alpha: string): string {
  if (color.length === 9 && color.substring(0, 1) === '#') {
    return '#' + alpha + color.substring(3);
  }
  return color;
}
