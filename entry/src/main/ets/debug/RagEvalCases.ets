/**
 * RagEvalCases.ets — RAG 召回评测集（纯数据，无 IO）
 *
 * 路径: entry/src/main/ets/debug/RagEvalCases.ets
 * 职责: 044 R5 的固定查询集：每条给出用户问法、期望命中的笔记标题，以及用例类型。
 *       kind 用于分组统计：paraphrase 考语义召回，exact 考字面召回，negative 考拒答。
 * 依赖: 无。
 *
 * 约束: 期望标题必须与 TestCorpusSeed 里导入的测试语料一致；
 *       paraphrase 刻意避开标题里的关键词——否则测不出「换个说法」能不能召回。
 */
export interface RagEvalCase {
  query: string;
  expectTitle: string;
  kind: string;
}

export const RAG_EVAL_CASES: RagEvalCase[] = [
  // ========== 同义改写（10）：不含标题关键词，考语义召回 ==========
  { query: '任何有界的非空集合都存在最小上界吗', expectTitle: '实数与确界原理', kind: 'paraphrase' },
  { query: '当 n 足够大时项都落在任意小的邻域里，怎么严格说明', expectTitle: '数列极限的 ε-N 定义', kind: 'paraphrase' },
  { query: 'x 靠近某点时函数值靠近某个值，怎么写成一串不等式', expectTitle: '函数极限的 ε-δ 定义', kind: 'paraphrase' },
  { query: '函数图像没有断开说明什么', expectTitle: '连续与一致连续', kind: 'paraphrase' },
  { query: '能求导是不是就能用线性部分近似', expectTitle: '可导与可微的关系', kind: 'paraphrase' },
  { query: '存在一点其切线平行于两端连线', expectTitle: '拉格朗日中值定理', kind: 'paraphrase' },
  { query: '什么样的函数才能做定积分', expectTitle: 'Riemann 积分的可积条件', kind: 'paraphrase' },
  { query: '无穷多项相加会不会收敛到有限值', expectTitle: '数项级数的收敛判别', kind: 'paraphrase' },
  { query: '矩阵化成阶梯形后有几个非零行', expectTitle: '矩阵的秩与初等变换', kind: 'paraphrase' },
  { query: '矩阵什么时候没有逆', expectTitle: '可逆矩阵的判定', kind: 'paraphrase' },

  // ========== 精确查询（8）：直接用标题，考字面召回 ==========
  { query: '多元函数偏导数与全微分', expectTitle: '多元函数偏导数与全微分', kind: 'exact' },
  { query: '二重积分的计算', expectTitle: '二重积分的计算', kind: 'exact' },
  { query: '行列式按行展开', expectTitle: '行列式按行展开', kind: 'exact' },
  { query: '特征值与特征向量', expectTitle: '特征值与特征向量', kind: 'exact' },
  { query: '条件概率与乘法公式', expectTitle: '条件概率与乘法公式', kind: 'exact' },
  { query: '全概率公式与贝叶斯公式', expectTitle: '全概率公式与贝叶斯公式', kind: 'exact' },
  { query: '期望与方差的性质', expectTitle: '期望与方差的性质', kind: 'exact' },
  { query: '大数定律与中心极限定理', expectTitle: '大数定律与中心极限定理', kind: 'exact' },

  // ========== 负样本（4）：命中数必须为 0 ==========
  { query: '今天天气怎么样', expectTitle: '', kind: 'negative' },
  { query: '如何做红烧肉', expectTitle: '', kind: 'negative' },
  { query: '股票明天涨不涨', expectTitle: '', kind: 'negative' },
  { query: '给我讲个笑话', expectTitle: '', kind: 'negative' },
];
