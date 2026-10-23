# HarmonyOS API 26 端侧生成式大模型：官方可用能力与真实限制

> 调研日期：2026-10-24 · 目标工程：`D:/HMgent/MindTrace`（Stage 模型 / targetSdk 26）
> 取证环境：DevEco Studio 26 自带 SDK `C:/Program Files/Huawei/DevEco Studio/sdk/default`，`sdk-pkg.json` → `apiVersion: "26"`、`version: "26.0.0.105"`、`releaseType: Release`〔S1〕
> 来源优先级：本机 SDK `.d.ts`（最权威） > OpenHarmony 文档仓库（`gh api` 读 master） > developer.huawei.com 官方文档 > MindSpore 官方文档。**未使用任何第三方博客作为结论依据**（§7 单列了社区流传但查无实据的说法）。

---

## 0. 结论摘要

| # | 问题 | 结论 | 关键依据 |
|---|---|---|---|
| 1 | API 26 有官方系统级端侧生成式 LLM API 吗？ | **不存在**。整个 ArkTS SDK 里 `LLM` 只出现在 2 个文件，且都是「抽象类/接口，由应用自己实现」的壳；无 `generateText` / `chatCompletion` / `textGeneration` / `promptTokens` 等任何生成式推理入口 | §1 全量符号扫描〔S2–S7〕 |
| 2 | MindSpore Lite 在 API 26 的边界 | **通用张量推理引擎，不是 LLM 运行时**：只吃 `.ms`（由 MindIR/ONNX/TF/TFLite/Caffe 转），ArkTS 侧 API 自 API 12 起冻结、**不支持动态 Shape**、CPU 算子表 65 个且不支持 int64 输入、无 KV-Cache/采样/tokenizer 任何封装 | §2〔S2, S8–S12〕 |
| 3 | Data Augmentation Kit 提供什么 | 提供**知识加工 + 检索 + RAG 编排**三件套；**不自带生成模型**，`ChatLLM` 必须应用实现，官方要求所选 LLM 上下文 ≥30k tokens（举例 Qwen2.5-7B-32K/Llama-3.1-8B）并申请网络权限 → 官方方案生成段在端外；知识加工依赖的嵌入模型**只在 PC/2in1 部署** | §3〔S4–S6, S14–S17〕 |
| 4 | 0.5B 端侧 LLM 的官方路径 | 官方只有一条通用路径：模型 → `converter_lite` 转 `.ms` → 训练后量化 → 用 MindSpore Lite Runtime 做**手工自回归循环**（tokenizer、KV-Cache、采样全自己写）。**官方没有 LLM 示例、没有 ArkTS tokenizer、没有 KV-Cache 管理 API** | §4〔S8–S12, S20–S23〕 |
| — | 对本项目的直接含义 | 「默认走端侧模型」在 API 26 **没有系统 API 可接**；要么自带权重用 MindSpore Lite 硬扛（工程量大、内存风险高），要么走云端并在 UI 标注降级。详见 §5 | — |

---

## 1. Q1：API 26 有没有系统级端侧生成式模型 API？

### 1.1 结论

**不存在。** 这是本次调研最硬的一条结论，依据是三层独立证据。

### 1.2 证据 A：SDK 全量符号扫描（可复现）

对 `openharmony/ets/api` 与 `hms/ets/api` 两个目录下全部 `.d.ts` / `.d.ets` 做大小写敏感检索：

```bash
cd "C:/Program Files/Huawei/DevEco Studio/sdk/default"
grep -ril "generateText"     --include="*.d.ts" --include="*.d.ets" openharmony/ets/api hms/ets/api  # 0 命中
grep -ril "chatCompletion"   ...  # 0 命中
grep -ril "textGeneration"   ...  # 0 命中
grep -ril "generateContent"  ...  # 0 命中
grep -ril "promptTokens"     ...  # 0 命中
grep -rl  "LLM"              ...  # 只有 2 个文件
```

`LLM`（大小写敏感）在整个 ArkTS SDK 中只命中两个文件〔S4, S5〕：

| 文件 | 类型 | 说明 |
|---|---|---|
| `hms/ets/api/@hms.data.rag.d.ts:188` | `abstract class ChatLLM` | `abstract streamChat(query, callback): Promise<LLMRequestInfo>`、`abstract cancel(chatId)`；注释原文：*"Abstract class for requesting the LLM. **Your app needs to inherit from this class** to implement the logic of each API"*〔S4〕 |
| `hms/ets/api/@hms.data.knowledgeProcessor.d.ts:49` | `interface ChatLLM` | `chat(query: string): Promise<string>`；`KnowledgeProcessorConfig.llm?: ChatLLM`，注释：*"**Custom** chat LLM functional API"*〔S5〕 |

也就是说：系统只定义了「你怎么把 LLM 接进来」的协议，**没有提供任何 LLM 本体**。

### 1.3 证据 B：官方 AI Kit 清单里没有「大模型 Kit」

developer.huawei.com 当前 AI 分类下共 10 个 Kit〔S19〕：

`Agent Framework Kit`、`CANN Kit`、`Core Speech Kit`、`Core Vision Kit`、`Intents Kit`、`MindSpore Lite Kit`、`Natural Language Kit`、`Neural Network Runtime Kit`、`Speech Kit`、`Vision Kit`

无 LLM / 大模型 / 生成式相关 Kit。且 `CANN Kit` 在本机 SDK 中**查无对应 `.d.ts`**（`ls hms/ets/api | grep -i cann` 为空），说明它当前不属于手机侧 ArkTS 能力面。

### 1.4 证据 C：RAG 文档自己承认要外部大模型

官方《知识问答》指南「约束限制」第 4、5 条〔S14〕：

> 4. 开发者应选择**上下文长度至少应该为 30k Tokens** 的 LLM，如 **Qwen2.5-7B-32K、Mistral-7B-Instruct-v0.2、Llama-3.1-8B** 等。否则可能会因大模型上下文长度超限而导致知识问答失败。
> 5. **LLM 由开发者自行选择**，问答支持的语言受选择的 LLM 影响。

「开发准备」第 1 条〔S14〕：

> 申请**网络权限**。`streamChat` 中需要开发者实现与 LLM 交互的功能，因此需要为应用申请网络权限。

30k 上下文 + 7B/8B 量级 + 必须联网 —— 这套要求与「端侧小模型」在事实层面互斥。

### 1.5 现有 AI 能力是什么性质

`hms/ets/api` 下 23 个 `@hms.ai.*` 模块全部是**判别式/专用小模型**，没有任何生成式入口〔S2–S7, S19〕：

| 模块 | 能力 | 版本 |
|---|---|---|
| `@hms.ai.ocr.textRecognition` | 通用文字识别（OCR） | 已上线 |
| `@hms.ai.nlp.textProcessing` | **仅**分词 `getWordSegment` + 实体抽取 `getEntity`（无摘要/无生成） | 5.0.0(12)+，`EntityConfig.timestamp` 新增于 26.0.0〔S7〕 |
| `@hms.ai.speechRecognizer` / `textToSpeech` | ASR / TTS | 已上线 |
| `@hms.ai.vision.*` | 目标检测、主体分割、骨骼点、超分、**文搜图** | 已上线 |
| `@hms.ai.AgentFramework` / `A2A` | 拉起**小艺智能体**（云侧），不是本地生成 | 6.0.0(20) / 26.0.0 |

`@hms.ai.nlp.textProcessing` 全文 264 行只有 `init/release/getWordSegment/getEntity` 四个函数〔S7〕——社区文章所说的「Natural Language Kit 提供文本总结」在本机 SDK 中**未找到**。

### 1.6 关于「小艺帮写 / `@hms.ai.largeLanguageModel`」

搜索到多篇 2026-09 报道称 HarmonyOS 7 开放了端侧大模型 API，模块名 `@hms.ai.largeLanguageModel`，参数含 modelMode / 预设提示模板 ID / temperature / topP / repetitionPenalty / maxLength。

**在 API 26 公开 SDK（26.0.0.105）与官方 API 参考目录中均未找到该模块**：

- `ls hms/ets/api | grep -i large` → 空
- 官方 AI Kit 导航无对应条目〔S19〕
- `https://developer.huawei.com/consumer/cn/doc/harmonyos-references/largelanguagemodel-api` → 404

判定：**可能存在于更高版本 SDK / 灰度 / 未公开的能力白名单中，但在本项目当前可编译的 API 26 SDK 上不可用**。若要跟进，需要向华为确认准入条件，不能写进设计假设。（此条为「未找到」，非「不存在」的强断言。）

---

## 2. Q2：MindSpore Lite 在 API 26 的能力边界

### 2.1 ArkTS API 面：自 API 12 起冻结

`@ohos.ai.mindSporeLite.d.ts` 共 986 行，**全部 `@since` 只有 10 和 12 两个值**〔S2〕——意味着 API 13→26 之间这个 ArkTS 接口没有任何新增。可用面：

| 类别 | 成员 | since |
|---|---|---|
| 加载 | `loadModelFromFile(model, context?)` / `loadModelFromBuffer(ArrayBuffer, context?)` / `loadModelFromFd(fd, context?)`，各有 Promise 与 Callback 重载 | 10 |
| 训练 | `loadTrainModelFromFile/Buffer/Fd(..., trainCfg?)` | 12 |
| 推理 | `Model.getInputs(): MSTensor[]`、`predict(inputs): Promise<MSTensor[]>`、`resize(inputs, dims): boolean` | 10 |
| 训练相关 | `runStep`、`getWeights`、`updateWeights`、`setupVirtualBatch`、`exportModel`、`exportWeightsCollaborateWithMicro` | 12 |
| 张量 | `MSTensor.name/shape/elementNum/dataSize/getData(): ArrayBuffer/setData(ArrayBuffer)` | 10 |
| 上下文 | `Context.target?: string[]`、`cpu?: {threadNum, threadAffinityMode, threadAffinityCoreList, precisionMode}`、`nnrt?: NNRTDevice` | 10 |
| 设备枚举 | `getAllNNRTDeviceDescriptions()`、`NNRTDeviceType{OTHERS,CPU,GPU,ACCELERATOR}`、`PerformanceMode`、`Priority` | 12 |

**没有**：tokenizer、embedding lookup、attention mask、KV-Cache、采样（top-k/top-p/temperature）、流式回调、动态 batch。这些全部要应用自己做〔S2〕。

### 2.2 模型格式

- 运行时只吃 **`.ms`**〔S8：「MindSpore Lite 使用 `.ms` 格式模型进行推理」〕。
- 转换工具 `converter_lite` 支持 `--fmk`：**MINDIR、CAFFE、TFLITE、TF、ONNX、PYTORCH、MSLITE**〔S11 参数表；S21 同〕。
- **PyTorch 是例外**：编译选项默认关闭，「下载的安装包不支持转换 PyTorch 模型，只能通过源码编译方式获取」，需 `export MSLITE_ENABLE_CONVERT_PYTORCH_MODEL=on && export LIB_TORCH_PATH=...`〔S11, S21〕。这是本项目若选 HF/PyTorch 权重时最容易被忽略的一步。
- 导出类型：`--saveType=MINDIR_LITE`（默认）才是端侧可推理格式〔S21〕。

### 2.3 算子边界（CPU 后端）

官方《算子支持列表》明确「与 ONNX Opset18 相比所支持的 **CPU 后端**算子列表」，共 **65 个**算子，且**所有算子均不支持 int64 类型输入**〔S12〕。

与 transformer 相关的关键项：

- 有：`MatMulFusion`(Gemm/MatMul)、`Softmax`、`Activation`(Gelu/Relu/Sigmoid/Tanh/Clip…)、`Reduce`(ReduceMean/Max/Sum)、`PowFusion`、`Sqrt`、`AddFusion`、`MulFusion`、`SubFusion`、`DivFusion`、`Reshape`、`Transpose`、`Concat`、`SliceFusion`、`Gather`、`Cast`、`Squeeze/Unsqueeze`、`Trilu`、`Where`
- **没有** `LayerNormalization` / `RMSNorm` —— 必须拆成 `Reduce(Mean) → Sub → Pow → Reduce(Mean) → Add(eps) → Sqrt → Div → Mul(γ) → Add(β)` 的手工子图，融合度差、算子数翻倍〔S12〕
- **没有** `Attention` / `RotaryEmbedding` / `FlashAttention` 之类融合算子

没有 int64 输入，对 LLM 影响很直接：token id / position id / attention mask 通常是 int64，必须在图内或图外统一转 int32〔S12〕。

### 2.4 动态 Shape：ArkTS 侧明确不支持

官方《使用 MindSpore Lite 实现图像分类（ArkTS）》原文〔S10〕：

> 若需基于本 Demo 适配自有模型，请优先选择**静态 Shape** 模型。**由于 ArkTS 暂不支持动态 Shape**，如确有相关需求，请参考（C/C++）…通过 Native 侧的 `OH_AI_ModelResize` 接口对模型 inputs 进行动态调整。

这正是 LLM 的命门：自回归解码每步序列长度 +1，天然是动态 shape。ArkTS 路线只能「固定最大长度 + padding + mask」，把每一步都按 `max_seq_len` 满算，算力浪费与延迟随长度线性放大。

### 2.5 设备与加速

- 支持设备：`Phone、Tablet、PC/2in1、TV`〔S8「约束与限制」〕。
- CPU 线程可配（`threadNum`、大/中/小核亲和 `ThreadAffinityMode`）；`precisionMode` 字符串。
- NPU 走 **NNRt**：`target: ["nnrt"]` 或 `nnrt.deviceID`；官方明确 NNRt「支持的算子规格少」，不支持的算子回退 CPU，构成异构推理〔S9〕。样例模型本身「不支持使用 NNRt 推理」〔S10〕——是否真能吃到 NPU 取决于模型算子与机型，不可默认假设。
- 需要在自己工程的 `syscap.json` 里补 `SystemCapability.AI.MindSporeLite`（「工程默认设备定义的能力集可能不包含 MindSporeLite」），否则编译期就报不支持〔S10 line 55〕。

### 2.6 内存限制

**未找到**官方对 MindSpore Lite（ArkTS 或 Native）给出的模型体积/常驻内存上限数值。SDK 与文档只有间接线索：`Context` 无内存参数、无 mmap/按需加载选项；`model` 必须整体 load 进进程（`loadModelFromBuffer` 吃 `ArrayBuffer`）〔S2, S9〕。

工程推断（非官方）：0.5B 参数 fp16 ≈ 1.0 GB 权重，加上 KV-Cache 与中间激活，在手机应用进程内属于高风险区间；官方文档未提供任何「大模型分片/按页加载」机制。

### 2.7 官方有没有 LLM 示例

**未找到**。MindSpore Lite Kit 官方示例只有：图像分类（ArkTS）〔S10〕、图像分类（C/C++）〔S9〕、以及 `quick_start_c`（mobilenetv2）〔S9 末尾链接〕。官方 Kit 简介列举的典型场景是「图像分类、目标识别、人脸识别、文字识别」〔S8〕，无 LLM。

MindSpore 侧唯一相关的一句话在《MindSpore 大语言模型推理》〔S23〕：

> 由于大语言模型体积巨大，MindSpore 大语言模型推理推荐用户使用更灵活的在线推理（权重 CKPT + 网络脚本），但是在一些特定场景，如**端侧或者边缘侧大模型**，由于运行环境受限…用户可以使用 **MindSpore Lite 离线推理方案**。此时，用户需要将模型导出成 MindIR，并将其传给 MindSpore Lite 运行时。

即：官方承认「端侧 LLM = MindIR + Lite」，但**没有给出任何端侧 LLM 的教程、示例或最佳实践**，只有云侧/服务侧的 LLM 推理教程（vLLM 式，非 Lite）。

### 2.8 小结：能跑 transformer 吗

| 维度 | 判断 |
|---|---|
| 技术上是否可行 | 可行。65 个算子足以拼出 decoder-only 结构（LayerNorm 需分解），C/C++ 侧可 resize 支持变长 |
| ArkTS 侧是否可行 | 勉强可行但代价大：静态 shape → 全长 padding 重算；无 KV-Cache 封装 → 每步重算全序列或自己把 cache 当 I/O 张量管理 |
| 是否有官方 LLM 支持 | 无。无示例、无 tokenizer、无采样、无 cache 管理 |
| 主要风险 | 内存（1GB 级权重 + 激活）、首 token 延迟、功耗与热、算子缺失导致的转换失败 |

---

## 3. Q3：Data Augmentation Kit（rag / retrieval / knowledgeProcessor）

### 3.1 它到底是什么

三个模块，同属 `@kit.DataAugmentationKit`，官方定位是「**ArkData Intelligence Platform (AIP)**」的上层〔S6 文件头〕：

| 模块 | 职责 | 设备 |
|---|---|---|
| `knowledgeProcessor` | 知识加工：解析 txt/html/doc(x)/ppt(x)/xls(x)/pdf/图片 → 切块 → 文本/图像嵌入 → 写倒排表与向量表；schema 放 `resources/rawfile/arkdata/knowledge/knowledge_schema.json` | **仅 PC/2-in-1**〔S5 头部注释〕 |
| `retrieval` | 智慧化检索：多通道召回（倒排 bm25 + 向量相似度）+ RRF 重排 + 检索解释 | Phone/Tablet/PC/2in1 6.0.0(20)+〔S24〕 |
| `rag` | RAG 会话编排：`createRagSession` → `streamRun` 流式问答 → `feedback` → `close` | **PC/2in1**〔S17 页头〕 |

### 3.2 是否需要外部模型

**需要，而且是两处**：

1. **生成模型**：`rag.ChatLLM` 是抽象类，应用必须继承实现 `streamChat` / `cancel`〔S4〕。官方示例里就是一个 `MockLLMEngine` / `MyChatLLM`〔S15, S14〕。
2. **嵌入模型**：由系统提供（`@ohos.data.intelligence` 的 `getTextEmbeddingModel` / `getImageEmbeddingModel`），但**只在 2in1 部署**，且单次推理限 **512 字符**、图像 **<20MB**、建议 NPU 加速〔S3, S13, S5〕。

### 3.3 能否离线

| 环节 | 是否端侧 | 依据 |
|---|---|---|
| 文档解析 / 切块 / 嵌入 / 建索引 | 端侧（进程内，「数据不出应用」） | AIP 文档原文「相关能力均运行在应用进程内，数据不出应用，保证隐私安全」〔S13〕 |
| 检索 / 重排 | 端侧 | `retrieval` 模块本地执行〔S6〕 |
| **生成** | **官方设计与示例为端外（联网）** | `streamChat` 由应用实现，协议上不禁止接本地引擎；但官方要求 LLM 上下文 ≥30k tokens 且需网络权限〔S14〕，端侧不现实 |

所以：**RAG Kit 不是一个「离线大模型方案」，它是「本地知识库 + 你的云端大模型」**。且因为知识加工只在 2in1，手机端连本地知识库都建不起来（推断，依据 `knowledgeProcessor` 的 2in1 限制 + RAG「必须先知识加工」的约束〔S5, S14〕）。

### 3.4 其他硬约束（官方原文）

- 不支持多线程：同一时刻只能有一个 RAG 会话执行 `streamRun` 或 `cancel`〔S4, S17〕。
- `streamRun` 问题长度 ≤ **1000 字符**〔S14 接口表〕。
- RAG **不提供敏感词风控**，需应用自己做输入/输出过滤〔S14〕。
- 知识加工的表不支持同时端端同步、端云同步、搜索〔S15〕。
- schema 里可配 `pipelineHandlers`（FileParser → SplitText → TextEmbedding → ImageEmbedding）与 `chunkSplitter`（chunkSize 100–5000，默认 3072）〔S15〕。

### 3.5 官方推荐架构

`RAG概述` 给出的流程〔S16〕：请求 → LLM 解析问题 → 检索知识库 → LLM 融合检索结果生成 → 流式返回。即官方推荐的是**「端侧检索 + 云端生成」的混合架构**，不是端侧全栈。

---

## 4. Q4：真要端侧跑 0.5B，官方路径是什么

### 4.1 官方唯一路径（4 步）

| 步 | 做什么 | 官方文档 |
|---|---|---|
| 1 | 选模型并拿到可转换的图（推荐 MindIR；ONNX 次之，需核对算子表） | 〔S8, S12〕 |
| 2 | `converter_lite` 转 `.ms`（`--fmk=MINDIR/ONNX`、`--saveType=MINDIR_LITE`、`--fp16=on`） | 〔S11, S21〕 |
| 3 | 训练后量化：`WEIGHT_QUANT`（1–16bit / 混合比特）、`FULL_QUANT`、或 NLP 用的 `DYNAMIC_QUANT`（注意：动态量化**不支持** FP16 运行模式） | 〔S22〕 |
| 4 | 运行时加载 + 自建自回归循环（ArkTS 或 C/C++） | 〔S2, S9, S10〕 |

### 4.2 转换与量化细节

- 权重量化 / 全量化 / 动态量化三选一；动态量化「针对 NLP 模型」设计，权重离线量化、激活运行期量化，需 SDOT 指令的 ARM 架构才有额外加速〔S22〕。
- `--fp16` 优先级低于量化：已量化权重不会被再次转 fp16〔S21〕。
- 转换出的 `.ms` 需由**同版本或更高版本**的 Runtime 执行〔S21〕——注意本机 SDK 内置 Runtime 版本未知，务必用不高于目标设备 Runtime 的 converter。
- 若模型含 int64 输入，转换/推理会失败，需在导出前把 dtype 改成 int32 或 int64→int32 的 Cast 前置〔S12〕。

### 4.3 tokenizer：官方没有

**未找到**任何 ArkTS/HarmonyOS 官方 tokenizer 组件。可选做法（均为工程实践，非官方文档）：

1. 把 BPE/vocab 打包进 `rawfile`，用 ArkTS 手写 encode/decode（0.5B 词表 ~15 万条，需注意启动解析耗时）；
2. 在 C/C++ 侧用 sentencepiece/tokenizers 编译成 so，N-API 暴露给 ArkTS（官方 Native 开发方式支持这条链）〔S8「开发方式二」〕。

### 4.4 推理循环要怎么搭（ArkTS 现实写法）

1. `mindSporeLite.loadModelFromBuffer(rawfileBuffer, ctx)` 一次加载，**复用 Model 实例**（官方强调「一次编译，多次推理」，图编译高耗时）〔S20〕。
2. 输入张量：`input_ids[1, max_seq]`、`attention_mask[1, max_seq]`、`position_ids[1, max_seq]`，全部 int32、静态 shape。
3. KV-Cache 必须**显式建模为模型输入/输出张量**（`past_k[layers, 1, heads, max_seq, dim]`），每步 `getData()` 取出上一步输出、`setData()` 喂回下一步 —— ArkTS 没有隐式 cache。
4. `predict()` 拿 logits → ArkTS 侧做 temperature/top-k/top-p 采样 → 拼回输入 → 循环。
5. 每步都要 `MSTensor.setData()` 全量写 `max_seq` 长度，**无法只写增量**（ArkTS 无动态 shape、无 resize）〔S2, S10〕。

### 4.5 官方明确不提供的

| 缺什么 | 影响 |
|---|---|
| LLM 示例工程 | 无参考实现，需从零搭 |
| tokenizer | 自建 |
| KV-Cache / PagedAttention | 自建（且 ArkTS 侧无动态 shape，实现受限） |
| 流式输出 / 中断 | 自建（`predict` 是同步语义的 Promise） |
| 内存上限与 oom 策略 | 未找到任何官方数值或机制 |
| NPU 上 LLM 算子的保证 | 未找到；NNRt 算子集更小〔S9〕 |

### 4.6 结论

0.5B 在 API 26 上**只能走「自带权重 + MindSpore Lite」**这条自建路线，官方只提供通用推理引擎和转换/量化工具，**不提供任何 LLM 级别的封装或示例**。若走 ArkTS，静态 shape 会带来「每步全长重算」的性能税；若走 C/C++，可用 `OH_AI_ModelResize` 缓解，但工程量显著上升〔S10〕。

---

## 5. 对本项目（MindTrace）的含义

产品设计要求「默认走端侧模型、只有用户主动配置云端模型才走云端、回退要标注已降级」。基于以上事实：

| 方案 | 可行性 | 代价 |
|---|---|---|
| A. 接系统端侧 LLM API | **不可行**（API 26 无此 API） | — |
| B. 自带 0.5B 权重 + MindSpore Lite | 技术可行 | 权重打包体积（int8 ~500MB 起）、内存风险、tokenizer/采样/cache 全部自研、无官方支持、机型适配不可控 |
| C. 端侧只做 OCR/结构化，生成走云端 | 可行且与官方推荐一致 | 需网络；必须在 UI 明示「已使用云端」 |
| D. Data Augmentation Kit | 手机端基本不可用（2in1 only） | 不可作为手机产品的主路径 |

建议的降级语义（与现有 `OnDeviceLlm` 路由一致）：端侧只承担 OCR + 规则/模板结构化；LLM 生成一律视为云端能力，UI 明示「云端处理」；若未来接入端侧 LLM，再用「端侧 / 云端」二态 + `degraded` 标记统一表达。

---

## 6. 未找到 / 待确认

| 项 | 状态 |
|---|---|
| `@hms.ai.largeLanguageModel`（小艺帮写 / 端侧 3B/7B 大模型 API） | **未找到**于 SDK 26.0.0.105 与官方 API 参考；社区报道存在，需华为确认准入与版本 |
| MindSpore Lite 内存上限 / 大模型分片加载 | **未找到**任何官方说明 |
| MindSpore Lite 官方 LLM 示例或端侧 LLM 教程 | **未找到**（仅云侧 LLM 推理教程） |
| ArkTS tokenizer 组件 | **未找到** |
| CANN Kit 的 ArkTS API | **未找到**（Kit 存在于文档导航，SDK 无对应 `.d.ts`） |
| `Natural Language Kit` 的「文本总结」能力 | **未找到**（SDK 仅分词 + 实体抽取） |
| HarmonyOS 内置 MindSpore Lite Runtime 的具体版本号 | **未找到**（`sdk-pkg.json` 只给 SDK 版本，不含 Runtime 版本） |

---

## 7. 社区流传但经核验不成立的说法

调研中检索到的第三方文章（不作结论依据，仅记录以免团队被误导）：

- 「`mindSporeLite.createModelSession()` / `modelSession.createGenerator()` / `npu.createNPUContext()`」——SDK 中**不存在**这些符号，`@ohos.ai.mindSporeLite` 只有 `loadModelFromFile/Buffer/Fd` 等〔S2〕。
- 「`@ohos/hmafsdk`、`@ohos/ai-engine`、`@ohos/mindspore-lite` npm 包」——SDK 中无此依赖；MindSpore Lite 是**系统 Kit**，不需要 oh-package 依赖。
- 「端侧 30B 大模型、<100ms 首 token」——无官方 API 支撑（见 §1.6）。

---

## 8. 来源清单

| 编号 | 来源 | 读取方式 / 位置 |
|---|---|---|
| S1 | SDK 元数据 | `C:/Program Files/Huawei/DevEco Studio/sdk/default/sdk-pkg.json`（`apiVersion 26` / `26.0.0.105`） |
| S2 | `@ohos.ai.mindSporeLite.d.ts`（986 行） | 本机 `sdk/default/openharmony/ets/api/` |
| S3 | `@ohos.data.intelligence.d.ts`（327 行，ArkData AIP） | 本机 `sdk/default/openharmony/ets/api/` |
| S4 | `@hms.data.rag.d.ts`（516 行） | 本机 `sdk/default/hms/ets/api/` |
| S5 | `@hms.data.knowledgeProcessor.d.ts`（252 行） | 本机 `sdk/default/hms/ets/api/` |
| S6 | `@hms.data.retrieval.d.ts` | 本机 `sdk/default/hms/ets/api/` |
| S7 | `@hms.ai.nlp.textProcessing.d.ts`（264 行） | 本机 `sdk/default/hms/ets/api/` |
| S8 | OpenHarmony `MindSpore-Lite-Kit-Introduction.md` | `gh api repos/openharmony/docs/contents/zh-cn/application-dev/ai/mindspore/MindSpore-Lite-Kit-Introduction.md?ref=master`（master，2026-08-22 最后推送） |
| S9 | OpenHarmony `mindspore-lite-guidelines.md` | 同目录，`gh api` |
| S10 | OpenHarmony `mindspore-guidelines-based-js.md`（ArkTS 图像分类） | 同目录，`gh api`（「ArkTS 暂不支持动态 Shape」在 line 16） |
| S11 | OpenHarmony `mindspore-lite-converter-guidelines.md` | 同目录，`gh api` |
| S12 | OpenHarmony `mindspore-lite-supported-operators.md`（65 算子） | 同目录，`gh api` |
| S13 | OpenHarmony `database/aip-data-intelligence-embedding.md` | `gh api .../zh-cn/application-dev/database/aip-data-intelligence-embedding.md?ref=master` |
| S14 | 《知识问答》RAG 开发指南 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-augmentation-rag-development （约束限制 §4/§5、开发准备 §1） |
| S15 | 《知识加工》指南 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-augmentation-knowledge-processing |
| S16 | 《RAG 概述》 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/data-augmentation-rag-overview |
| S17 | 《rag（检索增强生成）API》页（页头标注 `PC/2in1 6.0.0(20)+`） | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/dataaugmentation-rag-api |
| S18 | 《使用 MindSpore Lite 进行模型推理 (C/C++)》 | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-lite-guidelines |
| S19 | AI Kit 导航（10 个 Kit，无 LLM Kit） | https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-speech-kit-guide 左侧 AI 分类 |
| S20 | MindSpore Lite 端侧推理文档首页 | https://www.mindspore.cn/lite/docs/zh-CN/master （图编译高耗时 / 一次编译多次推理 / 内存释放） |
| S21 | 《端侧模型转换》`converter_lite` 参数表 | https://www.mindspore.cn/lite/docs/zh-CN/stable/converter/converter_tool.html |
| S22 | 《训练后量化》权重量化/全量化/动态量化 | https://www.mindspore.cn/lite/docs/zh-CN/stable/advanced/quantization.html |
| S23 | 《MindSpore 大语言模型推理》（端侧/边缘侧改用 Lite 离线推理） | https://www.mindspore.cn/tutorials/zh-CN/r2.7.0rc1/model_infer/ms_infer/llm_inference_overview.html |
| S24 | 《retrieval（智慧化数据平台）API》页（页头 `Phone / PC/2in1 / Tablet 6.0.0(20)+`） | https://developer.huawei.com/consumer/cn/doc/harmonyos-references/dataaugmentation-retrieval-api |

> 版本提示：S20–S23 属 MindSpore Lite 2.9/2.10 文档，**不等于** HarmonyOS 设备内置 Runtime 的版本；转换工具与运行时版本配套关系见 S21「转换成的 ms 模型，支持转换工具配套及更高版本的 Runtime 推理框架执行推理」。
