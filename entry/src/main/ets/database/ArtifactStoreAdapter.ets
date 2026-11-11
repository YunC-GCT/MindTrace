/**
 * ArtifactStoreAdapter.ets — ArtifactStorePort 的 entry 侧实现（文件 + JSON 清单）
 *
 * 路径: entry/src/main/ets/database/ArtifactStoreAdapter.ets
 * 职责: 把产物字节落盘并维护清单（artifactId 幂等键、checksum、size、createdAt）；
 *       部分失败时回滚已写文件，保证「文件有则清单有」。
 * 依赖: common 的类型（type-only）+ 注入的 ArtifactFileIo（生产走 fileIo，测试走内存）。
 *
 * 数据流:
 *   put：artifactId + bytes → checksum → 写 {root}/{id}.bin → 写 artifacts-manifest.json
 *   get：读清单 → descriptor；remove：撤清单 → 删文件（失败回滚清单）
 *
 * 契约实现（#238）:
 *   - put：同 id 同 checksum = 幂等重放（duplicate=true，不写第二份）；同 id 不同 checksum = ARTIFACT_CONFLICT。
 *   - 清单写失败 → 删除刚写的文件再抛 ARTIFACT_WRITE_FAILED(retryable=true)。
 *   - get：清单里没有 → null；IO 读失败 → ARTIFACT_READ_FAILED(retryable=true)；
 *     清单 JSON 损坏 → ARTIFACT_READ_FAILED(retryable=false)（重放不会修好坏文件）。
 *   - remove：不存在 → false；先撤清单再删文件，文件删除失败时回滚清单，保证「描述存在 ⇔ 文件存在」；
 *     失败抛 ARTIFACT_DELETE_FAILED(retryable=true)。
 *   - 单写者假设：manifest 读-改-写没有事务，装配层保证同一时刻只有一个写者（应用内单进程）。
 *   - uri 由本层给出（rootDir/artifactId.bin），调用方只认 descriptor，不自己拼路径。
 */
import { NotePortError } from 'common';
import type { ArtifactDescriptor, ArtifactFileIo, ArtifactStorePort } from 'common';

// 清单条目：落盘 JSON 的形状，字段全部显式，避免解析出无类型对象。
interface ArtifactManifestEntry {
  artifactId: string;
  mediaType: string;
  uri: string;
  checksum: string;
  size: number;
  createdAt: number;
}

interface ArtifactManifest {
  items: ArtifactManifestEntry[];
}

export class ArtifactStoreAdapter implements ArtifactStorePort {
  private readonly rootDir: string;
  private readonly io: ArtifactFileIo;

  constructor(rootDir: string, io: ArtifactFileIo) {
    this.rootDir = rootDir;
    this.io = io;
  }

  async put(artifactId: string, mediaType: string, bytes: Uint8Array): Promise<ArtifactDescriptor> {
    if (!ArtifactStoreAdapter.isSafeId(artifactId)) {
      throw new NotePortError('INVALID_ARTIFACT_ID',
        'artifactId must be 1+ chars of [A-Za-z0-9._-] and must not be "." or ".."', false);
    }
    const checksum: string = ArtifactStoreAdapter.checksum(bytes);
    const manifest: ArtifactManifest = await this.readManifest();
    const existing: ArtifactManifestEntry | undefined = ArtifactStoreAdapter.find(manifest, artifactId);
    if (existing !== undefined) {
      if (existing.checksum === checksum) {
        return ArtifactStoreAdapter.toDescriptor(existing, true);
      }
      throw new NotePortError('ARTIFACT_CONFLICT',
        'artifact ' + artifactId + ' already exists with a different checksum', false);
    }
    const uri: string = this.bytesPath(artifactId);
    try {
      await this.io.writeBytes(uri, bytes);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('ARTIFACT_WRITE_FAILED', message, true);
    }
    const createdAt: number = Date.now();
    const entry: ArtifactManifestEntry = {
      artifactId: artifactId,
      mediaType: mediaType,
      uri: uri,
      checksum: checksum,
      size: bytes.length,
      createdAt: createdAt,
    };
    manifest.items.push(entry);
    try {
      await this.writeManifest(manifest);
    } catch (e) {
      await this.io.remove(uri);
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('ARTIFACT_WRITE_FAILED', message, true);
    }
    return ArtifactStoreAdapter.toDescriptor(entry, false);
  }

  async get(artifactId: string): Promise<ArtifactDescriptor | null> {
    const manifest: ArtifactManifest = await this.readManifest();
    const entry: ArtifactManifestEntry | undefined = ArtifactStoreAdapter.find(manifest, artifactId);
    if (entry === undefined) {
      return null;
    }
    return ArtifactStoreAdapter.toDescriptor(entry, false);
  }

  async remove(artifactId: string): Promise<boolean> {
    const manifest: ArtifactManifest = await this.readManifest();
    const entry: ArtifactManifestEntry | undefined = ArtifactStoreAdapter.find(manifest, artifactId);
    if (entry === undefined) {
      return false;
    }
    // 先撤清单、再删文件：中间失败时 get() 不会返回「文件已没了」的悬空描述。
    const kept: ArtifactManifestEntry[] = manifest.items.filter((item: ArtifactManifestEntry): boolean => {
      return item.artifactId !== artifactId;
    });
    const next: ArtifactManifest = { items: kept };
    try {
      await this.writeManifest(next);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('ARTIFACT_DELETE_FAILED', message, true);
    }
    try {
      await this.io.remove(entry.uri);
    } catch (e) {
      // 文件没删掉：把清单写回去，保证「描述存在 ⇔ 文件存在」。
      try {
        await this.writeManifest(manifest);
      } catch (restoreError) {
        const restoreMessage: string = restoreError instanceof Error ? restoreError.message : String(restoreError);
        throw new NotePortError('ARTIFACT_DELETE_FAILED',
          'file removal failed and manifest restore failed: ' + restoreMessage, true);
      }
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('ARTIFACT_DELETE_FAILED', message, true);
    }
    return true;
  }

  private async readManifest(): Promise<ArtifactManifest> {
    const path: string = this.manifestPath();
    let text: string | null = null;
    try {
      text = await this.io.readText(path);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('ARTIFACT_READ_FAILED', message, true);
    }
    if (text === null || text.length === 0) {
      const empty: ArtifactManifest = { items: [] };
      return empty;
    }
    try {
      const parsed: ArtifactManifest = JSON.parse(text) as ArtifactManifest;
      if (parsed.items === undefined || parsed.items === null) {
        const empty: ArtifactManifest = { items: [] };
        return empty;
      }
      return parsed;
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      throw new NotePortError('ARTIFACT_READ_FAILED', 'manifest is not valid JSON: ' + message, false);
    }
  }

  private async writeManifest(manifest: ArtifactManifest): Promise<void> {
    await this.io.writeText(this.manifestPath(), JSON.stringify(manifest));
  }

  private manifestPath(): string {
    return this.rootDir + '/artifacts-manifest.json';
  }

  private bytesPath(artifactId: string): string {
    return this.rootDir + '/' + artifactId + '.bin';
  }

  // artifactId 会拼进路径：只允许 [A-Za-z0-9._-]，并排除 "." / ".."，防止路径穿越。
  private static isSafeId(artifactId: string): boolean {
    if (artifactId.length === 0 || artifactId === '.' || artifactId === '..') {
      return false;
    }
    for (let i = 0; i < artifactId.length; i++) {
      const ch: string = artifactId.charAt(i);
      const isDigit: boolean = ch >= '0' && ch <= '9';
      const isLower: boolean = ch >= 'a' && ch <= 'z';
      const isUpper: boolean = ch >= 'A' && ch <= 'Z';
      if (!isDigit && !isLower && !isUpper && ch !== '.' && ch !== '_' && ch !== '-') {
        return false;
      }
    }
    return true;
  }

  private static find(manifest: ArtifactManifest, artifactId: string): ArtifactManifestEntry | undefined {
    for (const entry of manifest.items) {
      if (entry.artifactId === artifactId) {
        return entry;
      }
    }
    return undefined;
  }

  private static toDescriptor(entry: ArtifactManifestEntry, duplicate: boolean): ArtifactDescriptor {
    const descriptor: ArtifactDescriptor = {
      artifactId: entry.artifactId,
      mediaType: entry.mediaType,
      uri: entry.uri,
      checksum: entry.checksum,
      size: entry.size,
      createdAt: entry.createdAt,
      duplicate: duplicate,
    };
    return descriptor;
  }

  // FNV-1a 32-bit：跨进程稳定、无依赖；用于幂等与冲突判定。
  private static checksum(bytes: Uint8Array): string {
    let hash: number = 0x811c9dc5;
    for (let i = 0; i < bytes.length; i++) {
      hash = (hash ^ bytes[i]) >>> 0;
      hash = (hash * 0x01000193) >>> 0;
    }
    return hash.toString(16).padStart(8, '0');
  }
}
