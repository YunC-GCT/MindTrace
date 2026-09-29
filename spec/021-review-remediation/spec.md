# Feature Specification: 021 合并结果 Review Remediation

**Created**: 2026-09-18
**Status**: Draft
**Input**: 用户确认统一处理 #140/#141 合并结果审查发现。

## Overview

本特性用于收敛 `origin/develop..develop` 对 spec 021 ticket-1（#140）与 ticket-5（#141）合并结果的审查发现。目标是在不扩大聊天增量渲染范围、不改变 ADR-0017 冻结预算的前提下，消除 RenderTick 生命周期歧义、统一聊天快照复制语义、修正持久化状态表达，并补齐相关能力边界与性能 follow-up 记录。

## User Scenarios & Testing

### User Story 1 - 不静默接受不支持的第二个 RenderTick 实例（Priority: P1）

作为维护者，我希望不支持的第二个浮窗节拍实例被明确报告，而不是在发布模式下静默失效，以便生命周期错误能够及时暴露并定位。

**Why this priority**: 静默 no-op 会让第二个实例看似创建成功但永远不处理节拍，可能造成不可诊断的 UI 不更新。

**Independent Test**: 在单实例已存在时创建第二个实例，验证其按统一契约明确失败；验证首个实例仍可正常工作，已销毁实例不会阻止后续合法实例创建。

**Acceptance Scenarios**:

1. **Given** 当前已有一个有效 RenderTick 实例，**When** 尝试创建第二个实例，**Then** 创建失败并返回明确的单实例错误，不因构建模式不同而静默变成 no-op。
2. **Given** 当前 RenderTick 实例已销毁，**When** 创建新的合法实例，**Then** 新实例可以正常接收节拍请求并驱动既定阶段顺序。
3. **Given** 第二实例创建失败，**When** 调用首实例的节拍流程，**Then** 首实例的 pending、定时器和订阅者状态不受影响。

---

### User Story 2 - 保持内存会话与持久化快照语义一致（Priority: P1）

作为维护者，我希望会话消息复制规则集中且语义明确，避免内存会话和持久化快照因重复实现而产生字段漂移。

**Why this priority**: 聊天历史是用户数据，复制规则分叉可能导致保存后字段丢失或后续字段扩展只修改一处。

**Independent Test**: 对包含正文、思考内容、流式状态和思考展开状态的会话执行内存复制与持久化快照复制，验证各自约定的字段保留规则稳定且有测试覆盖。

**Acceptance Scenarios**:

1. **Given** 会话包含全部当前消息字段，**When** 生成内存工作副本，**Then** 内存副本保留内存交互所需的字段。
2. **Given** 会话包含不可持久化的 UI 展开状态，**When** 生成持久化快照，**Then** 快照只保留持久化契约允许的纯数据字段，不写入 UI 展开状态。
3. **Given** 复制规则需要调整，**When** 维护者查找复制契约，**Then** 不存在两处未说明语义的重复实现。

---

### User Story 3 - 准确表达空闲 flush 结果（Priority: P1）

作为持久化调用方，我希望没有待写内容时的 `flush` 结果能明确表示“空闲且无需写入”，而不是伪装成已经进入写入准备阶段。

**Why this priority**: 阶段字段用于诊断和测试，错误的阶段会误导故障分析和调用方判断。

**Independent Test**: 分别验证无 pending、存在 pending、正在写入和失败重试时的 `flush` 结果阶段与状态。

**Acceptance Scenarios**:

1. **Given** 没有待写快照且没有正在进行的写入，**When** 调用 `flush`，**Then** 结果明确表示空闲/无需写入，且不报告为实际写入阶段。
2. **Given** 存在待写快照，**When** 调用 `flush`，**Then** 结果仍按实际异步写入生命周期报告阶段。
3. **Given** 写入失败后执行重试，**When** 调用 `flush`，**Then** 结果能够区分重试写入和空闲返回。

---

### User Story 4 - 明确持久化能力与 Worker 协议边界（Priority: P2）

作为维护者，我希望能力探针、生产持久化服务和 Worker 消息协议的职责边界有明确说明，避免把测试探针误认为生产写入入口。

**Why this priority**: #141 已启用生产迁移路径，旧 ticket-0.4 能力探针和新生产持久化服务并存，缺少边界说明会增加后续误用风险。

**Independent Test**: 查阅持久化相关代码头注释、协议说明和测试名称，能够区分能力探针、生产文件快照服务、Worker capability probe 与 Worker write request。

**Acceptance Scenarios**:

1. **Given** 维护者阅读能力探针，**When** 判断其职责，**Then** 文档明确它是验证/迁移能力探针，而不是生产持久化实现。
2. **Given** 维护者阅读 Worker 协议，**When** 区分 capability probe 与 write request，**Then** 两种消息的目的、合法响应和失败回传均有明确说明。
3. **Given** 维护者阅读生产持久化边界，**When** 判断保存路径，**Then** 文档明确生产保存使用私有文件快照，Preferences 仅作为迁移读取源，并且缺少 filesDir 时不回退同步写盘。

---

### User Story 5 - 如实记录性能 follow-up（Priority: P2）

作为项目维护者，我希望 ADR-0017 的预算冻结值保持不变，同时明确记录模拟器性能目标未达成和 #139 真机证据 follow-up，不把证据交付误报成性能达标。

**Why this priority**: 性能数据是架构决策的一部分，错误宣称达标会导致后续优化方向和验收判断失真。

**Independent Test**: 检查 ADR-0017、spec 021 和 remediation 记录，验证冻结预算不变、模拟器偏差保留、#139 follow-up 有明确入口和验收边界。

**Acceptance Scenarios**:

1. **Given** 当前 ADR-0017 已冻结预算，**When** 完成本次 remediation，**Then** `maxWebCreatesPerFrame=1` 和 `maxWebWorkMsPerFrame=16` 不被修改。
2. **Given** DevEco 模拟器上的 `T_finishToStable` 仍超过初始目标，**When** 记录验证结果，**Then** 结果明确标记为性能 follow-up，不宣称模拟器达标。
3. **Given** #139 尚未完成真机采集，**When** 维护者查看后续事项，**Then** 能看到真机证据采集、复算和不降低目标的约束。

### Edge Cases

- 第二个 RenderTick 实例创建失败后，首个实例必须保持可用；实例计数不能因失败路径泄漏。
- RenderTick 在测试中使用注入的计时器时，失败创建不能遗留定时器或订阅。
- 持久化复制遇到可选字段缺失时，结果必须保持合法且不凭空生成 UI 状态。
- 空闲 `flush`、未初始化管理器和 filesDir 缺失是不同状态，不得混用为“成功写入”。
- Worker 收到未知消息类型时，必须有可诊断的 unsupported 响应，不得将其当作写请求。
- 性能 follow-up 只能补充证据和记录，不能修改冻结预算或降低 `T_finishToStable` 初始目标。

## Requirements

### Functional Requirements

- **FR-001**: 系统 MUST 对第二个 RenderTick 实例采用统一的明确失败策略，不得因发布模式而静默 no-op。
- **FR-002**: 系统 MUST 保证 RenderTick 实例创建失败不破坏已有实例的运行、销毁和重新创建生命周期。
- **FR-003**: 系统 MUST 集中定义会话复制契约，并明确区分内存工作副本与持久化纯数据快照。
- **FR-004**: 持久化快照 MUST 不包含仅用于 UI 交互的展开状态；内存工作副本 MUST 保留继续交互所需状态。
- **FR-005**: 空闲 `flush` MUST 返回明确的 idle/no-write 状态，不得将没有发生的写入报告为 `PREPARE` 阶段。
- **FR-006**: 有实际待写内容或正在写入时，`flush` MUST 继续报告真实的异步写入结果和失败阶段。
- **FR-007**: 持久化能力探针 MUST 明确标识为测试/迁移能力边界，不得与生产 `ChatHistoryPersistence` 混为同一入口。
- **FR-008**: Worker 消息契约 MUST 明确区分能力探针、写入请求、成功响应、unsupported 响应和失败阶段。
- **FR-009**: 生产聊天历史 MUST 继续以私有文件快照为保存路径，Preferences 只作为迁移读取源；本次 remediation 不得恢复同步 UI 线程写盘或损坏新文件时回退旧数据。
- **FR-010**: ADR-0017 冻结预算 MUST 保持为每帧最多创建 1 个 Web 工作单元、每帧 Web 工作时间预算 16ms。
- **FR-011**: 性能记录 MUST 明确 DevEco 模拟器目标偏差和 #139 真机 follow-up，且不得降低原有 `T_finishToStable` 初始目标或伪报性能通过。
- **FR-012**: 本次 remediation MUST 保持 #142/#143/#144 尚未实施的范围边界，不引入 `StreamingReplyDocument`，不切换聊天主渲染入口。
- **FR-013**: 本次 remediation MUST 添加或更新针对 RenderTick 单实例、复制语义、idle flush 和 Worker 协议的自动化验证。

### Key Entities

- **RenderTick 实例策略**：浮窗级节拍实例的创建、失败、运行、暂停和销毁状态契约。
- **ChatSession 内存副本**：供运行中会话继续交互使用的完整内存数据副本。
- **Chat history persistence snapshot**：供异步文件保存使用的纯数据会话快照，不含 UI-only 状态。
- **Persistence stage result**：描述空闲、异步写入、失败和重试结果的外部诊断状态。
- **Worker message contract**：主线程与 Worker 之间的能力探针、写入请求及响应边界。
- **Performance follow-up record**：记录冻结预算、模拟器偏差和真机证据待办的可追踪记录。

## Success Criteria

### Measurable Outcomes

- **SC-001**: RenderTick 单实例相关自动化测试覆盖第二实例失败、首实例不受影响、销毁后重新创建三类生命周期场景，全部通过。
- **SC-002**: 会话复制相关自动化测试覆盖内存字段保留与持久化 UI-only 字段排除，全部通过。
- **SC-003**: `flush` 自动化测试能区分 idle、实际写入、失败和重试四种结果，不再以 `PREPARE` 表示 idle。
- **SC-004**: 持久化能力探针和 Worker 协议的代码说明、测试名称和诊断字段能够在不阅读实现细节的情况下区分职责。
- **SC-005**: ADR-0017 的两个冻结预算值与本次变更前完全一致，且性能记录明确保留模拟器 follow-up。
- **SC-006**: 项目 ArkTS 静态检查、相关自动化测试、命名检查、diff 检查和完整构建在可用环境中通过；若设备或 SDK 环境阻塞，验证报告必须明确记录阻塞原因。

## Assumptions

- 本次 remediation 基于当前本地 `develop` 已包含 #140/#141 的合并结果执行，不重写父 issue #118，也不重新拆分 #119–#124。
- 用户已确认五项审查发现全部纳入本次范围。
- 当前产品仍只支持一个 AgentFloatWindow/RenderTick 实例；多浮窗并发不在范围内。
- `messages` 仍是聊天历史唯一持久化真源，Document 渲染状态不进入持久化快照。
- ADR-0017 的模拟器性能偏差属于后续证据与优化跟进，不构成本次预算重算理由。
- 本次不要求新增真机性能采集；真机采集由 #139 follow-up 负责。

## Open Questions

- 无。用户已确认所有审查发现统一纳入本次 remediation，后续任务只在已批准范围内拆分与排序。

## Remediation Traceability Note

- ADR-0017 remains unchanged: `maxWebCreatesPerFrame=1` and `maxWebWorkMsPerFrame=16`.
- The DevEco emulator `T_finishToStable` evidence remains a performance follow-up; this remediation does not claim a performance pass and does not lower the initial 500ms target.
- #139 remains responsible for true-device evidence collection, recomputation, and any separately approved performance work.
- This record does not implement #142/#143/#144, introduce `StreamingReplyDocument`, or change the chat Markdown/LaTeX rendering entry.
