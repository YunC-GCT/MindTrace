/**
 * RrfFusion.ets — 多路召回的 Reciprocal Rank Fusion（纯函数，无 IO）
 *
 * 路径: common/src/main/ets/utils/RrfFusion.ets
 * 职责: 把 FTS / 数学签名 / 词 OR / 短词 / 向量各路的有序 id 列表融合成一个排序。
 *       分路权重表达「这一路有多可信」，rank 而不是原始分数参与计算，
 *       避免不同通道的分数量纲互不可比。
 * 依赖: 无。
 *
 * 公式: score(d) = Σ_ch w_ch / (k + rank_ch(d))，rank 从 1 开始，k 默认 60。
 * 平局按首次出现顺序（通道顺序即优先级），保证结果确定。
 */

export interface RrfChannel {
  weight: number;
  ids: string[];
}

export const RRF_DEFAULT_K: number = 60;

export function fuseRrf(channels: RrfChannel[], limit: number, k: number = RRF_DEFAULT_K): string[] {
  if (limit <= 0 || channels.length === 0) {
    const empty: string[] = [];
    return empty;
  }
  const scores: Map<string, number> = new Map<string, number>();
  const firstSeen: string[] = [];
  for (let c = 0; c < channels.length; c += 1) {
    const channel: RrfChannel = channels[c];
    const seen: string[] = [];
    for (let i = 0; i < channel.ids.length; i += 1) {
      const id: string = channel.ids[i];
      if (id.length === 0 || seen.indexOf(id) >= 0) {
        continue;
      }
      seen.push(id);
      if (!scores.has(id)) {
        firstSeen.push(id);
      }
      scores.set(id, (scores.get(id) ?? 0) + channel.weight / (k + i + 1));
    }
  }
  const ranked: string[] = firstSeen.slice(0);
  ranked.sort((left: string, right: string): number => {
    const leftScore: number = scores.get(left) ?? 0;
    const rightScore: number = scores.get(right) ?? 0;
    if (leftScore !== rightScore) {
      return rightScore - leftScore;
    }
    return firstSeen.indexOf(left) - firstSeen.indexOf(right);
  });
  return ranked.slice(0, limit);
}
