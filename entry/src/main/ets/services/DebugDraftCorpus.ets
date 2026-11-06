/**
 * DebugDraftCorpus.ets — 生成笔记的相似度对照实验输入（纯数据，无 IO）
 *
 * 路径: entry/src/main/ets/services/DebugDraftCorpus.ets
 * 职责: 给「生成→确认」探针提供成对的输入：同一主题两种说法（应当判重）、
 *       相邻但不同的主题（不应判重）。用来检验判重规则在真实生成文本上的边界。
 * 依赖: 无。
 *
 * 约束: expect 只是实验预期，不参与任何生产逻辑；结果以日志为准。
 */
export interface DraftProbeInput {
  /** 实验分组：same-topic（应判重）/ related-different（不应判重）。 */
  group: string;
  label: string;
  instruction: string;
  sourceText: string;
}

export const DRAFT_PROBE_INPUTS: DraftProbeInput[] = [
  // ===== 数学分析：同题异构 =====
  {
    group: 'same-topic',
    label: 'ma-continuity-a',
    instruction: '整理一致连续的定义与判定',
    sourceText: '一致连续要求区间上任意两点距离足够近时，函数值也足够近，而且同一个 δ 对所有点通用。'
      + '闭区间上的连续函数一定一致连续。',
  },
  {
    group: 'same-topic',
    label: 'ma-continuity-b',
    instruction: '整理函数在区间上能否用同一个 delta 控制的问题',
    sourceText: '对给定的 ε，存在一个 δ，使得区间内任意两点只要距离小于 δ，函数值之差就小于 ε，'
      + '这个 δ 不依赖具体位置。',
  },
  {
    group: 'same-topic',
    label: 'ma-series-a',
    instruction: '整理函数项级数一致收敛的判别',
    sourceText: '一致收敛指部分和与和函数之差在上确界意义下趋于零；魏尔斯特拉斯判别法用数值级数来控制。',
  },
  {
    group: 'same-topic',
    label: 'ma-series-b',
    instruction: '整理什么时候可以把极限和积分交换次序',
    sourceText: '如果函数项级数在区间上一致收敛，则可以先积分再取极限，也可以逐项求导，'
      + '但需要导函数一致收敛。',
  },

  // ===== 高等代数：同题异构 =====
  {
    group: 'same-topic',
    label: 'la-kernel-a',
    instruction: '整理线性变换的核与像',
    sourceText: '核是被映到零向量的向量集合，像是所有像向量构成的子空间；'
      + '维数公式为定义域维数等于核维数加像维数。',
  },
  {
    group: 'same-topic',
    label: 'la-kernel-b',
    instruction: '整理线性映射的零空间与值域的维数关系',
    sourceText: '线性映射的零空间维数称为零度，值域维数称为秩，两者之和等于定义域的维数。',
  },

  // ===== 第三轮：同一主题的第三种说法（库里已有 a/b，用来验证向量兜底判重）=====
  {
    group: 'same-topic-c',
    label: 'ma-continuity-c',
    instruction: '整理什么叫函数在区间上一致地连续',
    sourceText: '函数在区间上一致连续，是指不论取区间里的哪两个点，只要它们靠得足够近，'
      + '函数值就靠得足够近，而且这个"足够近"的标准不随位置改变。',
  },
  {
    group: 'same-topic-c',
    label: 'ma-series-c',
    instruction: '整理函数项级数在什么条件下可以逐项积分',
    sourceText: '函数项级数在区间上一致收敛时，可以逐项积分再求和；若要逐项求导，'
      + '还需要导函数级数本身一致收敛。',
  },
  {
    group: 'same-topic-c',
    label: 'la-kernel-c',
    instruction: '整理线性变换把空间映到哪里、哪些向量会被映成零',
    sourceText: '线性变换的像空间是所有像向量组成的子空间，核是被映成零向量的全体，'
      + '两者维数之和等于定义域维数。',
  },

  // ===== 补充关系：同一主题，第二条带已有笔记没有的内容（应写入 + 发合并建议）=====
  {
    group: 'supplement',
    label: 'supp-greens-a',
    instruction: '整理格林公式',
    sourceText: '格林公式把闭合曲线上的线积分化为区域上的二重积分，条件是 P、Q 在区域上有一阶连续偏导，'
      + '且曲线取正向。',
  },
  {
    group: 'supplement',
    label: 'supp-greens-b',
    instruction: '整理格林公式的应用：用它计算平面区域面积',
    sourceText: '格林公式把闭合曲线上的线积分化为区域上的二重积分；取 P=-y/2、Q=x/2 '
      + '可以得到面积公式 A=½∮(x dy − y dx)，这是用它求面积的典型用法。',
  },

  // ===== 高等代数：相关但不同（不应判重）=====
  {
    group: 'related-different',
    label: 'la-jordan-a',
    instruction: '整理若尔当标准形的构造',
    sourceText: '对不能对角化的矩阵，用若尔当块拼成相似标准形，块的大小由广义特征向量链的长度决定。',
  },
  {
    group: 'related-different',
    label: 'la-jordan-b',
    instruction: '整理不可对角化矩阵如何化成最简形式',
    sourceText: '当特征向量不够时，引入广义特征向量构成若尔当链，矩阵相似于由若尔当块组成的块对角矩阵。',
  },
];
