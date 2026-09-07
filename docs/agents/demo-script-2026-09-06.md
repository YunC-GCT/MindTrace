# 复赛演示脚本与赛前检查 — 2026-09-06

> **适用**: 鸿蒙高校创新赛复赛 5 分钟 walk-through + 赛前环境准备。
> **配套**: 提交前快速回归见 [`smoke-test.md`](./smoke-test.md); 设计叙事依据见 AGENTS.md「比赛定位」与 [`docs/architecture/agent-tools-inventory-2026-09-06.md`](../architecture/agent-tools-inventory-2026-09-06.md) §6.1。
> **原则**: 每一步都写"操作 → 预期 → 一句叙事"; 故障表现全部来自代码事实, 不承诺未实现的行为。

---

## 1. 赛前准备 (T-1 天完成)

| # | 事项 | 操作 | 验证 |
|---|---|---|---|
| P1 | 真机/模拟器运行 | DevEco `Run → Run 'entry'` | App 启动进 Home, 5 Tab 可切换 |
| P2 | OCR 服务启动 | 运行 `tools/ocr_service/start.bat` (Windows PC; 首次跑依赖下载较慢) | 浏览器开 `http://localhost:8000/docs` 有 API 页 |
| P3 | OCR 端点指向 PC | App 内 `AI 设置 → OCR 配置 (OcrConfigSection)`, endpoint 填 `http://<PC局域网IP>:8000` | **真机必须用 PC 的局域网 IP** (默认 127.0.0.1 只适用于本机模拟器); PC 与设备同一 Wi-Fi |
| P4 | LLM API Key | App 内 `AI 设置` 填 DeepSeek key → 连接测试 | statusText "已配置 / 连接正常" |
| P5 | 通知权限 | 设置 → 通知 → MindTrace → 允许 | 为提醒能力 (ReminderFacadeImpl 已注入) 预留 |
| P6 | 测试全绿 | `npm --prefix scripts/arkts-lint test` + DevEco GUI Hypium 全量 | Node 全绿 + Hypium 0 fail |
| P7 | 演示数据 | 建议 **0 笔记起步** | Home 显示引导横幅 + 复习环 0%, 演示"从零到一"最完整 |

---

## 2. 主演示脚本 (5 分钟)

| 步 | 操作 | 预期 | 叙事 (对评委) |
|---|---|---|---|
| 1 | Home 首页浏览, 切 5 Tab | 复习环/Hero 卡渲染流畅; 知识星系**无"示例:*"假学科** | 端到端数据都是真实的 — 我们修掉了 fixture 泄漏 (ticket #16), 宁可空也不造假 |
| 2 | AI 浮窗发起提问 | 回复**逐字流式**出现 (真 SSE, requestInStream) | LLM 调用层是统一 `call(request)` 入口: JSON 与流式双适配, 自研于 ArkTS |
| 3 | 对话中说"把刚才内容记成笔记" | 意图门禁识别 → 生成完整笔记材料 → 入库 | 对话→笔记有显式意图门禁, AI 不会偷偷写库 |
| 4 | 拍照/相册导入一道题 | OCR (公式走 PC 服务, 端侧 CoreVisionKit 兜底) → AI 五分类 + 结构化 → **入库出现在最近笔记** | 后端是自研 CaptureGraph: LangGraph 的图模型 (节点/条件边/状态) 原生实现在 ArkTS, 零外部依赖 (ADR-0008) |
| 5 | 打开该笔记详情 | MM-MD-v1 渲染: 独立公式 $$ 单独成行, 字段分区 | 结构化输出经协议校验 (JSON schema + MM-MD-v1), 不合格直接报错不落库 |
| 6 | 复习 Tab → 学习计划 → AI 生成 | 生成 3-5 条计划待办 | 计划生成在 Service 层, 与 UI 状态分离 |
| 7 | 知识星系 | 学科/章节图可视化 | 数据来自真实入库的 KnowledgeUnit |
| 8 | (收尾叙事, 不 live) | 打开 `docs/adr/` 与 `docs/architecture/agent-tools-inventory-2026-09-06.md` | 平台路线图: ReminderFacade 已实现注入 (ADR-0009)、LLM 工具调用协议 + ToolRegistry 已落地 (ADR-0012/spec 014)、小艺 skill 预留位 (ADR-0011) — 设计透明度是我们的工程支柱 |

---

## 3. 故障与降级表现 (演示中出问题时的口径)

| 故障 | 用户看到 | 一句话解释 |
|---|---|---|
| OCR 服务未启动/断网 | 纯文本仍可识别 (端侧 CoreVisionKit 兜底); 公式识别不可用, 部分结果也算成功 | 自研双路径: 端侧保底, PC 服务增强 |
| LLM key 未配置 | 引导"请先在设置中配置 API Key" | 配置缺失显式引导, 不静默失败 |
| LLM 网络失败 (聊天) | 自动降级为非流式完整回复, 已收到的部分保留 | 流式失败降级非流式, 不白屏 |
| LLM 结构化失败 | **报错提示, 不生成假笔记** | spec 011 §9: AI 失败宁可显式失败, 绝不造 fallback 占位数据污染知识库 (ticket #16 教训) |
| 学习计划解析失败 | 返回空列表, 界面不崩溃 | 解析容错: 非 JSON/畸形输入安全返回 |
| 提醒按钮 (未来 UI) 失败 | (当前 UI 未挂) 实现已注入; 需设备通知开关开启 | 能力就绪, 入口待产品需要 |

---

## 4. 赛前检查清单 (当场过一遍)

- [ ] start.bat 已运行, PC 防火墙放行 8000, 设备能打开 `http://<PC_IP>:8000/docs`
- [ ] App 内 OCR endpoint = `http://<PC局域网IP>:8000` (真机勿用 127.0.0.1)
- [ ] LLM key 已配置且连接测试通过
- [ ] 通知权限已允许 (P5)
- [ ] Node 测试全绿 + GUI Hypium 全量 0 fail
- [ ] 演示数据已就位 (0 笔记起步 / 或按叙事需要预置)
- [ ] 备选: 一段预录视频兜底 (真机 OCR 演示失败时切)

---

## Last updated

2026-09-06 (创建 — 复赛冲刺; 拆分与工具化落地后的第一条完整演示脚本)
