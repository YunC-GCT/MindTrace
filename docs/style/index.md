# Style rules index

> 编码与文档规范的权威目录。`AGENTS.md` 的硬规则从这里引用。

| File | 作用 |
|---|---|
| [`arkts-ai-coding.md`](./arkts-ai-coding.md) | **AI coding 60 秒预检**：高频编译阻断、ArkUI 硬约束、工程结构、验证命令与 DoD |
| [`naming-conventions.md`](./naming-conventions.md) | **命名唯一权威源**：文件 / 目录 / 分支 / commit / 测试 / 生成物 / 禁用模式 |
| [`mm-md-v1.md`](./mm-md-v1.md) | **笔记正文协议**：MM-MD-v1 白名单、公式定界符、块级/行内规则与兜底层级 |
| [`arkts-1.1.md`](./arkts-1.1.md) | ArkTS 1.1 严格语法规则（40+ 条）与常见编译陷阱 |
| [`html-in-docs.md`](./html-in-docs.md) | `docs/` 里 HTML 的决策树：生成物 / 配对视觉稿 / 冻结历史 / 真源 HTML |

## 维护

- 改规则必须 bump `naming-conventions.md` 头部版本（MAJOR / MINOR / PATCH 语义见该文件 §Versioning）
- 规则变更后跑 `node scripts/naming-lint/index.mjs` 与 `node scripts/naming-lint/tests/*.test.mjs`
- HTML 白名单在 `.naminglintrc.json` 的 `skip.files` 里逐文件登记
