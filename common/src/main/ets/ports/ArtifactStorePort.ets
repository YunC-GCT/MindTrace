/**
 * ArtifactStorePort.ets — Artifact 产物存储端口契约（#238 / §17.5）
 *
 * 路径: common/src/main/ets/ports/ArtifactStorePort.ets
 * 职责: 声明产物描述、put / get / remove 语义，以及落地需要的文件缝 ArtifactFileIo；
 *       不含 fileIo、Kit 或任何实现。
 * 依赖: 无（纯契约；错误类型由适配器从 common barrel 引入）
 * 数据流:
 *   NoteAgent / CaptureGraph → ArtifactStorePort.put → entry 适配器 → fileIo + 清单 JSON
 *   UI / 卡片 → ArtifactStorePort.get → 描述（uri / checksum / size）→ 打开或引用原图
 *
 * 契约（#238 / §17.5）:
 *   - artifactId 是幂等键：同 id 同校验和重放返回首次描述（duplicate=true），不产生第二份文件。
 *   - 同 id 不同校验和 → ARTIFACT_CONFLICT(retryable=false)，正确动作是换 id 或先删旧产物。
 *   - get：不存在返回 null；IO 读失败 → ARTIFACT_READ_FAILED(retryable=true)，
 *     清单 JSON 损坏 → ARTIFACT_READ_FAILED(retryable=false)。
 *   - remove：不存在返回 false；成功返回 true；失败抛 ARTIFACT_DELETE_FAILED(retryable=true)。
 *   - 部分失败清理：先写文件再写清单；清单写失败必须回滚已写文件（适配器负责，契约要求最终态一致）。
 *   - 描述里保留 mediaType / uri / checksum / size / createdAt，供卡片与溯源引用。
 *   - **为什么没有 expectedVersion / CAS**：artifactId 是内容寻址键，产物不可变；要换内容必须
 *     remove 后重 put。业务写契约（审批哈希、提交版本）由 NoteWritePort 承担，产物存储不重复定义。
 *   - **并发假设**：manifest 是读-改-写，本端口按单写者使用（应用内单进程装配）；
 *     多写者并发 put 会互相覆盖，需要时由调用方串行化，不要在端口里假装有事务。
 *
 * ArkTS 1.1 strict 适配:
 *   - 字节用 Uint8Array；不使用 any / unknown；可选字段显式声明。
 */

// 产物的可引用描述。
export interface ArtifactDescriptor {
  artifactId: string;
  mediaType: string;
  uri: string;
  checksum: string;
  size: number;
  createdAt: number;
  duplicate: boolean;
}

// 文件缝：生产实现走 fileIo，测试实现走内存 Map；端口层不 import 任何 Kit。
// 只保留适配器实际用到的能力，避免 speculative 接口面。
export interface ArtifactFileIo {
  writeBytes(path: string, bytes: Uint8Array): Promise<void>;
  readText(path: string): Promise<string | null>;
  writeText(path: string, text: string): Promise<void>;
  remove(path: string): Promise<boolean>;
}

// 产物存储端口。实现由 entry 侧适配器提供（ArtifactStoreAdapter）。
export interface ArtifactStorePort {
  put(artifactId: string, mediaType: string, bytes: Uint8Array): Promise<ArtifactDescriptor>;
  get(artifactId: string): Promise<ArtifactDescriptor | null>;
  remove(artifactId: string): Promise<boolean>;
}
