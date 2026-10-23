# 鸿蒙 7 端侧大模型：第三方应用到底能不能直接用

> 调研日期：2026-10-24 · 环境：SDK `26.0.0.105`（`apiVersion=26`）+ 真机 MRO-W00（`const.product.devicetype`=`tablet`，API 26）
> 来源优先级：本机 SDK 源码/清单 > developer.huawei.com 官方文档

---

## 0. 结论

| 追问 | 结论 |
|---|---|
| 设备上有端侧大模型吗 | 有（小艺/系统侧），但**模型不对外暴露** |
| 手机/平板第三方 App 能调吗 | **不能**：`phone-hmos.json`/`tablet-hmos.json` 均无 LLM syscap |
| 有官方端侧 LLM API 吗 | 仅 `localChatModel`，**限 PC/2in1 + 企业申请 + 模型需下载** |
| `@hms.ai.largeLanguageModel` | **不存在** |
| 手机/平板跑 LLM 的唯一办法 | 自带模型 + MindSpore Lite / HiAI 自建推理 |

一句话：**「系统有模型」≠「应用能用模型」**。生成式能力收在智能体侧，第三方只能「拉起智能体」，不能「调用模型」。

## 1. Kit 全目录：无 LLM/盘古/小艺模型 Kit

`kit-version.json` 共 **112 个 Kit**，名匹配 `llm|pangu|chat|ai` → **0 命中**。官方「AI」分组 10 个：Agent Framework Kit（拉起智能体+A2A，Phone/Tablet）、CANN Kit（NPU 异构计算，含 CANN LLM Engine）、Core Speech Kit（语音识别/合成）、Core Vision Kit（OCR/人脸/分割）、Intents Kit（意图框架）、MindSpore Lite Kit（轻量推理）、Natural Language Kit（文本处理）、Neural Network Runtime Kit（NNRt）、Speech Kit（朗读/字幕）、Vision Kit（卡证/文档扫描）。`Data Augmentation Kit` 归「应用框架」。
来源：`kit-version.json`；<https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/cann-kit-guide>（左侧目录）

## 2. `@hms.ai.largeLanguageModel` 查无此物

- `hms/ets/api`、`hms/ets/kits`、`openharmony/ets/api` 搜 `largeLanguageModel` → **0 命中**，无同名文件。
- `@hms.ai.*` 23 个模块只有 OCR/人脸/语音/NLU/视觉/InsightIntent/A2A/AgentFramework/appController，无 LLM。
- 候选页 `js-apis-hms-ai-largeLanguageModel` 标题即 **404**。

传闻的 3B/7B 模块在 API 26 不存在，别按它设计。

## 3. CANN / HiAI / MindSpore：都是「自带模型跑推理」

- **CANN LLM Engine**：`llm_engine.h:9` `Provides APIs for LLM model inference`、`:10` `@since 6.1.1(24)`；入口 `HMS_LLMEngineContext_CreateFromContextJson(const char* jsonFile)`（`:47`）**必须传自己的 JSON 配置**。官方流程「量化→ONNX→转 CANN→集成」，支持 Qwen2.5-1.5B/7B、DeepSeek-R1-Distill-Qwen-1.5B、GLM-1.5B、Qwen3-8B → **BYOM，官方不发模型**。注意 Kit 在 phone 有 5.0.0(12)，但 `SystemCapability.AI.CANN.LLMEngine` 只给 2in1。
- **MindSpore Lite**：只提供模型转换/部署/图像分类/语音识别 → 自带 `.ms`。
- **HiAI Foundation**：NPU 算子加速，syscap 覆盖 phone/tablet/2in1/tv/car，是底层加速不是模型服务。

官方**未提供**预置 LLM 文件或下载渠道（未找到一手来源）；唯一模型渠道是 PC 端 Matrix 模型库 <https://matrix.openharmony.cn/#/model/main>。

## 4. 设备预置模型：手机/平板无可加载入口

`localChatModel` 声明 `@syscap SystemCapability.DataAugmentation.LocalChatModel`、`@since 6.0.0(20)`（`@hms.data.localChatModel.d.ts:14,16`），仅 `init()`/`chat()`。`init()` 注释原文：`Initializes the on-device Q&A model and starts the model management app`（`:108`）——**拉起的是「模型管理应用」，不是内置模型**。

官方约束两条：①「当前端侧模型问答仅支持 PC/2in1 设备类型」②「仅对企业开发者提供申请能力」。开发步骤：「首次拉起弹隐私声明→同意后**下载**默认模型」或「设置>系统>本地 AI 模型管理」下载；默认 Qwen25-7B-Instruct。
syscap 坐实边界：`syscap-version.json:2953` 仅 `2in1`；`2in1-hmos.json:49` 有，`phone-hmos.json`（131 行）与 `tablet-hmos.json` 均 0 命中——本机真机 MRO-W00 正是 tablet。文档未公开模型路径/共享方式（未找到一手来源）。

## 5. 官方给第三方的路径：上架智能体

> 「Agent Framework Kit（智能体框架服务）提供了拉起指定智能体的能力。应用在**小艺开放平台**上线智能体后，向用户提供应用+智能体组合的服务……通过 Agent Framework Kit 的 UI 控件能力主动拉起智能体。」

约束：Phone/Tablet，仅中国境内。此路 + Intents Kit 即官方唯一生成式路径：**能力留小艺侧，应用只做入口与 A2A 编排**。
「生成式能力请用云侧」之类明确表述：**未找到一手原文**——官方靠 Kit 目录与 syscap 边界表达，没有 slogan。

## 6. 对 MindTrace

- 手机/平板端放弃 `localChatModel`（不支持+需企业申请+仅境内 PC）。
- 端侧只剩「自带小模型 + MindSpore Lite」，7B 不现实；`OnDeviceLlm` 若声称走系统端侧模型属错误承诺，应改名或改走云端/智能体。

## 来源清单

| # | 来源 | 位置 |
|---|---|---|
| 1 | syscap 清单 | `sdk/default/hms/ets/api/device-define/{phone,tablet,2in1}-hmos.json`、`syscap-version.json:35,2953` |
| 2 | 模块声明 | `hms/ets/api/@hms.data.localChatModel.d.ts:14,16,108`；`hms/ets/kits/@kit.DataAugmentationKit.d.ts:15` |
| 3 | 原生头文件 | `hms/native/sysroot/usr/include/CANNKit/llm_engine.h:9-10,43,47` |
| 4 | 端侧问答模型指南 | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/dataaugmentation-localchatmodel> |
| 5 | Kit 简介（设备约束表） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/dataaugmentation-introduction> |
| 6 | API 参考（标「PC/2in1 6.0.0(20)+」） | <https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/dataaugmentation-localchatmodel-api> |
| 7 | CANN LLM 简介（模型清单） | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/cannkit-llm-summary> |
| 8 | Agent Framework Kit 简介 | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/hmaf-introduction> |
| 9 | MindSpore Lite Kit 目录 | <https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/mindspore-lite-kit> |
