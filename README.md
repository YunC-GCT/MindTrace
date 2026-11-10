# MindTrace

[简体中文](./README.md) | [English](./docs/readme-en.md)

> 面向数学学习的鸿蒙原生智能笔记与可追溯复习应用。

## 一、项目简介

MindTrace 将数学截图、公式与零散文本整理为结构化笔记，经用户确认后保存，并结合个人笔记检索、知识关联与来源引用辅助复习。

项目采用 ArkTS 原生 Agent 工作流组织材料理解、笔记生成和复习问答；笔记检索为五路混合召回（整句全文检索、数学签名、分词 OR、短词匹配、向量语义），经 RRF 融合后再按需做查询改写与交叉编码器重排；写入前对笔记判重并做三分类仲裁，避免重复笔记，同时不丢弃补充内容。前端通过 3D 知识星系展示知识联系，构建“输入—整理—关联—复习—溯源”的学习闭环。

当前阶段（2026 年 11 月）：v1 端A2A 链路已打通，小艺可直接整理入库并回执；主线转为检索质量与笔记治理。项目处于测试态，不推进上架。

> **求职作品集**：[12 页 PDF](portfolio/MindTrace-Portfolio.pdf) · [HTML 设计说明](portfolio/index.html) · [作品集索引](portfolio/README.md)

## 二、功能实现状态

以下为代码实现与真机探针验证状态（2026-11-07）。

| 功能 | 状态 | 说明 |
|---|---|---|
| 图片与文本输入 | 已实现 | 支持拍照、相册、文本及 OCR；小艺端A2A 消息可就地整理入库 |
| 结构化笔记生成 | 已实现 | 支持轻量、标准、分节生成路线 |
| 草稿确认与增量编辑 | 已实现 | 预览、修改、取消、确认保存及限定章节编辑 |
| AI 对话 | 已实现 | 支持流式输出、会话历史与生成进度 |
| 个人笔记检索 | 已实现 | 五路混合召回（整句 FTS / 数学签名 / 词 OR / 短词 LIKE / 向量语义）+ RRF 融合，检索分随引用返回 |
| 语义向量检索 | 已实现（需配置服务） | 本地 BGE 服务（`tools/embedding_service`，默认 bge-m3）或兼容 OpenAI 接口的云端 embedding；未配置时自动只用词面通道 |
| 证据判定与学习模式 | 部分实现 | 回答前由 LLM 判定候选是否切题，过滤语料外引用；strict / balanced / expansive 三档策略已进编排层并接入设置页，默认 balanced |
| 笔记判重与仲裁 | 已实现 | L1 确定性规则 + 向量兜底 + LLM 三分类仲裁（same / supplement / different）；supplement 照常写入，不丢补充内容 |
| 笔记建议 | 部分实现 | create / append / merge 三类建议已发事件与日志，暂未渲染到界面 |
| 可追溯复习回答 | 已实现 | 概念解释、知识比较、前置查询、笔记定位与出题，来源带融合分与摘要，可回看笔记版本 |
| 3D 知识星系 | 已实现 | 展示知识关联，提供兼容渲染；当前包含预览样例 |
| 鸿蒙系统入口 | 部分实现 | 卡片展示学习概览；小艺端A2A 已支持草稿预览与确认入库（回复「确认」保存 / 「取消」放弃），并支持回执、图片降级规划；意图注册与 Agent Framework Kit 拉起依赖上架，测试态暂缓 |
| 数形交互、碰一碰共学 | 规划中 | 尚未形成完整产品链路 |

评测使用公开基准 **MathNet-Retrieve**（CC-BY-4.0，数学等价检索，中文子集 334 条查询）。离线评测脚本见 [`scripts/rag-lab/`](./scripts/rag-lab/)，原始记录见 [`docs/research/agent-framework-layering-review-2026-11-02.md`](./docs/research/agent-framework-layering-review-2026-11-02.md) §37–§54。

## 三、核心使用流程

**整理笔记**

输入图片或文本 → 说明整理要求 → 查看草稿 → 编辑确认 → 保存笔记。

**复习与溯源**

提出基于笔记的问题 → 检索相关材料 → 生成带来源的回答 → 点击引用查看笔记及其版本。

例如：

```text
根据我的笔记解释极限。
比较笔记中的极限与连续。
学习导数前需要哪些前置知识？
根据积分笔记出 3 道复习题。
```

草稿确认前不创建正式笔记；来源不足时提示补充材料。

## 四、技术架构

| 层次 | 主要职责 |
|---|---|
| 交互层 | ArkUI 页面、AI 浮窗、知识星系、桌面卡片与小艺入口 |
| 编排层 | ArkTS 原生 `StateGraph`，复用到采集、对话、工具调用与技能意图工作流 |
| 业务层 | 材料理解、笔记生成、混合检索（RRF 融合）、证据判定、判重与仲裁、来源解析 |
| 公共能力 | `LlmClient` 统一模型请求，OCR 处理图片，内容协议统一 Markdown 与公式，向量端口兼容词面与云端 embedding |
| 数据层 | HarmonyOS RDB（schema v22）保存笔记、版本、关系、生成记录、全文索引与向量块，本地快照保存会话状态 |

工作流在鸿蒙端运行，聊天与生成模型由配置的模型服务提供。语义检索需要另行配置 embedding 端点：可用 `tools/embedding_service` 在本地启动 BGE 服务，也可接兼容 OpenAI 接口的云端 embedding；未配置或服务离线时，检索自动只用词面通道。

## 五、快速开始

1. **获取代码**

   ```bash
   git clone --branch develop https://github.com/YunC-GCT/MindTrace.git
   cd MindTrace
   ```

2. **打开工程**

   使用 DevEco Studio 打开仓库根目录，完成依赖同步。当前 SDK 配置为 **HarmonyOS 6.1.1（API 24）**，具体以 `build-profile.json5` 为准。

3. **配置并运行**

   配置本地调试签名，连接符合版本要求的真机或模拟器，运行 `entry`。

4. **配置模型**

   在应用“AI 设置”中选择供应商，填写 API Key、服务地址与模型，保存后测试连接。

5. **按需配置外部 OCR**

   快速模式优先使用端侧文字识别。公式识别或服务端回退需要启动配套 OCR 服务：

   ```powershell
   .\start-ocr-server.bat
   ```

   服务脚本面向 Windows，需要 Python 3.10+。将启动后显示的地址填入应用 OCR 设置，例如：

   ```text
   http://192.168.1.50:8000/api/v1/ocr/recognize
   ```

   IP 应替换为服务电脑的实际地址，并确保设备可以访问。详细依赖见 [OCR 服务说明](./tools/ocr_service/README.md)。

6. **可选：启用语义检索**

   词面检索开箱即用。需要语义召回时，启动本地 embedding 服务（Windows，Python 3.10+，首次运行会下载模型，约 1.3GB）：

   ```powershell
   .\tools\embedding_service\start.bat
   ```

   然后在应用“AI 设置”的 embedding 配置中填写服务地址与模型名，例如：

   ```text
   端点：http://<PC-IP>:8001/v1
   模型：BAAI/bge-m3
   ```

   IP 替换为服务电脑的实际地址，密钥可留空。设置页会显示“在线 · 1024 维”；服务未启动时检索自动退回词面通道。

首次使用建议先完成“文本生成笔记 → 确认保存 → 基于笔记提问 → 查看来源”，再尝试图片输入。

## 六、仓库结构

```text
MindTrace/
├── entry/                  # 主应用、页面、业务服务与数据访问
├── agents/                 # 调度、分类、笔记生成与采集工作流
├── common/                 # StateGraph、模型调用、工具及公共能力
├── skill/                  # 小艺意图入口
├── cardservice/            # 桌面卡片
├── AppScope/               # 应用级配置与资源
├── tools/
│   ├── ocr_service/        # 独立 OCR 服务
│   └── embedding_service/  # 本地 BGE 语义检索服务
├── scripts/                # 测试与工程检查脚本
├── docs/                   # 架构、规格、方案与历史归档
├── build-profile.json5     # SDK、模块与签名配置
├── oh-package.json5        # 工程依赖
├── CONTEXT.md              # 项目术语
└── AGENTS.md               # 仓库协作约定
```

## 七、后续补充

- 产品截图与演示：待补充。
- 测试与验证：检索评测与真机探针记录见 `docs/research/`；系统性回归报告待补充。
- 已知问题与后续路线：见 `docs/agents/phase-tracker.md` 与上文“当前评测口径”。
- 文档导航：见 `docs/index.md`。
- 许可证与致谢：待补充。
