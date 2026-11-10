# MindTrace 版本号

> **当前版本**: v1.0(2026-09-05, tag 实际打点日期)
> **版本号规范**: [semver](https://semver.org/) `vMAJOR.MINOR.PATCH`
> **打 tag 流程**: 从 `main` 分支打 tag,PR merge + Squash merge 后由 owner 创建 GitHub Release

## 版本历史

| 版本 | 发布日期 | 主要内容 |
|---|---|---|
| **v1.0** | 2026-09-05 | 比赛复赛 W4 增量;5 module (3 HAP: `entry` / `skill` / `cardservice` + 2 HSP: `common` / `agents`);CODEOWNERS 3-owner 路由;Git Flow 轻量版;Self-approve 兜底策略;arkts-lint v0.3 AST 引擎 (34 规则 / 63 tests);2026-09-01 架构审计落地 |
| **v1.1-dev** | 未发版 | 检索与证据策略、三分类判重、A2A 草稿确认、ReviewWritePort/schema v23、求职作品集 |

## 2026-11 未发版变更

- **检索**：五路混合召回（整句 FTS / 数学签名 / 词 OR / 短词 LIKE / 稠密向量）+ RRF；条件重排与查询改写按头部差触发；评测集切换为公开基准 MathNet-Retrieve。
- **证据判定**：`EvidencePolicy` strict / balanced / expansive 三档接入编排层与设置页，默认 balanced。
- **判重**：L1 规则 + 向量兜底 + LLM 三分类仲裁（same / supplement / different），补充内容不丢弃。
- **写入一致性**：`ReviewWritePort` + `ReviewWriteStoreDao`，schema v23 `review_op`，operationId 幂等。
- **A2A**：文本/计划/图片逐题草稿确认，支持确认、取消、详细、简洁、重新生成；草稿 24h 过期；25s 超时兜底、单回执、失败转待整理。
- **作品集**：`portfolio/` 下增加 12 页 PDF、五页 HTML 设计说明与生成说明。

## 升级触发

- **MAJOR** (x.0.0): API breaking change / 模块结构调整 / 比赛阶段切换(W5+)
- **MINOR** (0.x.0): 新功能 / 新规则 / 新 lint 规则
- **PATCH** (0.0.x): bug fix / docs fix / lint 误报修复

## 比赛复赛相关

- **复赛 W4** (2026-07-24): 公式渲染方案 + SSE 流式
- **复赛 W3.5** (2026-07-22): 渲染协议层加固
- **复赛 W3** 及之前: 旧计划已于 2026-10-18 清理，需要时查 git 历史（tag `v1.0` 之前的提交）

## 打 tag 命令(owner 操作)

```bash
# 在 main 分支上,PR merge 后
git checkout main
git pull origin main
git tag v1.0 main
git push origin v1.0

# 然后到 GitHub Releases 页 -> Draft a new release -> 选 tag v1.0
```

## 维护

- 每次 PR merge 到 main 后,在本文件追加新版本行
- 格式:`| **vX.Y.Z** | YYYY-MM-DD | ... |
- 同步更新 README.md 顶部 "当前阶段总览"