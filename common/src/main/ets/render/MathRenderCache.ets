// ============================================================================
//  common/src/main/ets/render/MathRenderCache.ets
//  ----------------------------------------------------------------------------
//  职责: MathTextRenderer 的 LRU 渲染缓存。spec 016 PR-B (issue #66, audit C1)
//        从 entry/.../shared/atoms/MathTextRenderer.ets:44-179 提取。
//
//  原位置违规 (audit 报告):
//    - MathTextRenderer.ets:13 import '../../utils/UiCacheDebug'
//      → 违反 spec 012 §"Atom: 0 依赖内部模块" 规则
//    - MathTextRenderer.ets:44-180 模块级 MATH_RENDER_CACHE_* 状态
//      → Atom 不应有分子/器官级复杂度
//
//  修复: 缓存下沉到 common 模块 (shared library), MathTextRenderer 只保留
//  @Component 渲染逻辑 + 引用本模块的 seam。Atom 只依赖 common 不依赖 entry/utils。
//
//  ArkTS 1.1 约束:
//    - 不用 spread / destruct 参数 / typed catch
//    - 类字段显式 `: type = default` 标注
// ============================================================================

import { defaultLog } from '../utils/logger';

/**
 * 单条缓存记录。key = profile|version|forceDisplay|contentHash,
 * encodedHtml = 渲染好的 HTML(给 WebView applyCached bridge 用),
 * height = 估算或实测高度(给首屏占位用, 避免 layout shift)。
 */
export class MathRenderCacheEntry {
  key: string = '';
  encodedHtml: string = '';
  height: number = 0;
  touched: number = 0;
  touchedAt: number = 0;
  size: number = 0;

  constructor(key: string, encodedHtml: string, height: number, touched: number, touchedAt: number) {
    this.key = key;
    this.encodedHtml = encodedHtml;
    this.height = height;
    this.touched = touched;
    this.touchedAt = touchedAt;
    this.size = encodedHtml.length;
  }
}

// ========================================================================
//  容量 / 生命周期常量 — 调整此处即可全局生效
// ========================================================================

/** 缓存条目上限。超限触发 LRU 淘汰。 */
export const MATH_RENDER_CACHE_LIMIT: number = 64;

/** 缓存总字符数上限(encodedHtml 累计)。超限按 LRU 继续淘汰。 */
export const MATH_RENDER_CACHE_MAX_CHARS: number = 600000;

/** cacheKey 版本号。协议变更时 +1, 旧缓存自然失效。 */
export const MATH_RENDER_CACHE_KEY_VERSION: string = 'v2';

/** TTL: 超过此 ms 未访问的条目视为过期。 */
export const MATH_RENDER_CACHE_TTL_MS: number = 10 * 60 * 1000;

/** 每 N 次访问做一次被动 trim(check + drop expired)。避免过期条目堆积。 */
export const MATH_RENDER_CACHE_PASSIVE_TRIM_TICKS: number = 12;

// ========================================================================
//  模块级状态 — 单例 LRU 缓存
// ========================================================================

const MATH_RENDER_CACHE: MathRenderCacheEntry[] = [];
let mathRenderCacheClock: number = 0;

function nextCacheTick(): number {
  mathRenderCacheClock += 1;
  return mathRenderCacheClock;
}

// ========================================================================
//  公共 API
// ========================================================================

export function cacheGet(key: string): MathRenderCacheEntry | null {
  const now: number = Date.now();
  trimCacheIfNeeded(now);
  for (const entry of MATH_RENDER_CACHE) {
    if (entry.key === key) {
      entry.touched = nextCacheTick();
      entry.touchedAt = now;
      defaultLog.info('[UiDataCache] math hit key=' + key);
      return entry;
    }
  }
  defaultLog.info('[UiDataCache] math miss key=' + key);
  return null;
}

export function cacheSet(key: string, encodedHtml: string, height: number): void {
  const now: number = Date.now();
  const touched: number = nextCacheTick();
  if (encodedHtml.length > MATH_RENDER_CACHE_MAX_CHARS) {
    cacheRemove(key);
    trimCache(now);
    return;
  }
  for (const entry of MATH_RENDER_CACHE) {
    if (entry.key === key) {
      entry.encodedHtml = encodedHtml;
      entry.height = height;
      entry.touched = touched;
      entry.touchedAt = now;
      entry.size = encodedHtml.length;
      trimCacheIfNeeded(now);
      return;
    }
  }
  MATH_RENDER_CACHE.push(new MathRenderCacheEntry(key, encodedHtml, height, touched, now));
  trimCache(now);
}

export function cacheRemove(key: string): void {
  let index: number = MATH_RENDER_CACHE.length - 1;
  while (index >= 0) {
    if (MATH_RENDER_CACHE[index].key === key) {
      MATH_RENDER_CACHE.splice(index, 1);
    }
    index -= 1;
  }
}

/**
 * 内容哈希(djb2 变体)。不依赖加密强度, 只要求稳定 + 冲突率低。
 * key 格式: <length>_<positive_hash>, 前缀长度避免截断碰撞。
 */
export function contentHash(text: string): string {
  let hash: number = 5381;
  let index: number = 0;
  while (index < text.length) {
    hash = ((hash << 5) + hash + text.charCodeAt(index)) | 0;
    index += 1;
  }
  const positive: number = hash < 0 ? -hash : hash;
  return text.length.toString() + '_' + positive.toString();
}

// ========================================================================
//  内部 trim 逻辑(纯函数, 可独立单测)
// ========================================================================

function trimCacheIfNeeded(now: number): void {
  if (MATH_RENDER_CACHE.length > MATH_RENDER_CACHE_LIMIT
    || mathRenderCacheClock % MATH_RENDER_CACHE_PASSIVE_TRIM_TICKS === 0) {
    trimCache(now);
  }
}

function trimCache(now: number): void {
  dropExpiredCacheEntries(now);
  while (MATH_RENDER_CACHE.length > MATH_RENDER_CACHE_LIMIT) {
    removeOldestCacheEntry();
  }
  while (cacheTotalSize() > MATH_RENDER_CACHE_MAX_CHARS && MATH_RENDER_CACHE.length > 0) {
    removeOldestCacheEntry();
  }
}

function dropExpiredCacheEntries(now: number): void {
  let index: number = MATH_RENDER_CACHE.length - 1;
  while (index >= 0) {
    if (now - MATH_RENDER_CACHE[index].touchedAt > MATH_RENDER_CACHE_TTL_MS) {
      MATH_RENDER_CACHE.splice(index, 1);
    }
    index -= 1;
  }
}

function removeOldestCacheEntry(): void {
  if (MATH_RENDER_CACHE.length === 0) {
    return;
  }
  let oldestIndex: number = 0;
  let oldestTick: number = MATH_RENDER_CACHE[0].touched;
  let index: number = 1;
  while (index < MATH_RENDER_CACHE.length) {
    if (MATH_RENDER_CACHE[index].touched < oldestTick) {
      oldestTick = MATH_RENDER_CACHE[index].touched;
      oldestIndex = index;
    }
    index += 1;
  }
  MATH_RENDER_CACHE.splice(oldestIndex, 1);
}

function cacheTotalSize(): number {
  let total: number = 0;
  for (const entry of MATH_RENDER_CACHE) {
    total += entry.size;
  }
  return total;
}