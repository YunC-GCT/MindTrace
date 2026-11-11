# MindTrace 项目介绍

> 项目介绍入口。完整介绍是 12 页 PDF；HTML 页面用于补充查看产品流程、架构、A2A 时序、检索与质量设计。

## 材料清单

| 材料 | 路径 | 用途 |
|---|---|---|
| 项目介绍 PDF | [`MindTrace-Portfolio.pdf`](./MindTrace-Portfolio.pdf) | 直接阅读或分享 |
| 站点首页 | [`index.html`](./index.html) | 项目定位、关键数字、导航 |
| 产品流程 | [`flow.html`](./flow.html) | 四条入口、确认链路、失败路径 |
| 架构 | [`architecture.html`](./architecture.html) | 五模块、三条硬边界、本地/云端 |
| A2A 草稿确认 | [`a2a.html`](./a2a.html) | 时序、命令、真机指标 |
| 检索与证据 | [`retrieval.html`](./retrieval.html) | 五路召回、证据策略、MathNet 评测 |
| 质量与边界 | [`quality.html`](./quality.html) | 判重、幂等写入、测试与限制 |
| PDF 源文件 | [`print.html`](./print.html) | 12 页 A4 排版源，浏览器打印即 PDF |

## 内容口径

- 只引用有真机或自动化测试记录的结果；未验证、部分实现、平台阻塞项在质量页和 PDF 第 11 页单独标注。
- 检索指标只使用公开基准 MathNet-Retrieve（CC-BY-4.0），评测脚本与原始记录可复现。
- 项目处于测试态，未上架应用市场；不把“代码已实现”写成“已上线”。
- 公开仓库仅用于项目介绍与技术交流，授权说明见根目录 [`NOTICE`](../NOTICE)。

## 重新生成 PDF

`print.html` 是 PDF 的唯一排版源。修改内容后，用 Edge / Chrome 无头模式打印：

```bash
"$EDGE" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf=portfolio/MindTrace-Portfolio.pdf \
  --virtual-time-budget=15000 \
  "file://$(pwd)/portfolio/print.html"
```

生成后检查页数是否为 12：

```bash
python -c "import re; d=open('portfolio/MindTrace-Portfolio.pdf','rb').read(); print(len(re.findall(rb'/Type\\s*/Page[^s]', d)))"
```

## 站点发布

使用 GitHub Actions 发布 `portfolio/` 目录，避免把仓库源码整体作为站点：

- 站点地址：`https://yunc-gct.github.io/MindTrace/`
- 工作流：[`.github/workflows/pages.yml`](../.github/workflows/pages.yml)
- 启用方式：仓库 Settings → Pages → Build and deployment → Source 选 `GitHub Actions`
- 首次部署在 `main` 分支 push 后触发，也可以手动 `workflow_dispatch`

## 相关工程文档

- [`README.md`](../README.md) — 技术版项目介绍
- [`docs/system-architecture-layered.md`](https://github.com/YunC-GCT/MindTrace/blob/b97812869d41cbcbfb4e5edbf7d49998356d5f69/docs/system-architecture-layered.md) — 分层架构
- [`docs/research/agent-framework-layering-review-2026-11-02.md`](https://github.com/YunC-GCT/MindTrace/blob/b97812869d41cbcbfb4e5edbf7d49998356d5f69/docs/research/agent-framework-layering-review-2026-11-02.md) — 研究日志与评测原始记录
- [`docs/agents/phase-tracker.md`](https://github.com/YunC-GCT/MindTrace/blob/b97812869d41cbcbfb4e5edbf7d49998356d5f69/docs/agents/phase-tracker.md) — 阶段进度与验收
