// MindTrace - API key 凭据 vault(@kit.AssetStoreKit, TEE + AES256-GCM 加密)
// 位置: common/src/main/ets/security/ApiKeyVault.ets
// 责任: PR1 — API key 从明文 preferences 升级到 AssetStoreKit(系统级硬件加密)
//
// 设计:
//   -  写入: 只走 AssetStoreKit(asset.add + Map<Tag, Value>)
//   -  读取: 优先 AssetStoreKit(asset.query + tag ALIAS);空时 fallback preferences 旧 key 并自动写回
//   -  删除: asset.remove(忽略错误)
//   -  accessibility: API 9 默认行为(DEVICE_POWERED_ON),因为 DEVICE_UNLOCKED 需要 API 12+
//
// 兼容读取(Q13=C): 用户从旧版本升级时,preferences 里已存的 api_key 自动迁移到 AssetStoreKit,
// UI 无感知。
//
// ArkTS 1.1 严格语法:
//   -  无 any / unknown
//   -  显式类型
//   -  string <-> Uint8Array 用 helper 函数(util.TextEncoder / TextDecoder)
//
// 一手信源:
//   D:\HarmoNova\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.security.asset.d.ts
//   docs/specs/016-llm-settings-redesign.md §公共接口变更 (ApiKeyVault)
//   docs/adr/0014-asset-store-kit-migration.md

import { asset } from '@kit.AssetStoreKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

const ASSET_NAME: string = 'llm_api_key';
const LEGACY_STORE_NAME: string = 'mindtrace_llm';
const LEGACY_KEY_API_KEY: string = 'api_key';

export class ApiKeyVault {
  /**
   * 读取 API key
   * - 优先 AssetStoreKit(加密存储)
   * - 空时 fallback Preferences 旧 key,自动写回 AssetStoreKit(迁移透明)
   *
   * @returns string | null — API key 字符串,或未配置时 null
   */
  public static async get(): Promise<string | null> {
    try {
      const queryMap: asset.AssetMap = new Map();
      queryMap.set(asset.Tag.ALIAS, ApiKeyVault.strToBytes(ASSET_NAME));
      const results: asset.AssetMap[] = await asset.query(queryMap);
      if (results.length > 0) {
        const result: asset.AssetMap = results[0];
        const secretBytes: Uint8Array = result.get(asset.Tag.SECRET) as Uint8Array;
        if (secretBytes !== undefined && secretBytes !== null) {
          return ApiKeyVault.bytesToStr(secretBytes);
        }
      }
    } catch (_e) {
      // 继续 fallback 路径(AssetStoreKit 不可用时)
    }

    // Fallback: 从 preferences 读旧 key(Q13=C 兼容读取)
    const legacy: string | null = await ApiKeyVault.readLegacyPreferences();
    if (legacy !== null) {
      // 自动写入 AssetStoreKit(迁移透明,UI 无感知)
      await ApiKeyVault.put(legacy);
    }
    return legacy;
  }

  /**
   * 写入 API key 到 AssetStoreKit
   * - 如果 asset 不存在 → asset.add()
   * - 如果 asset 已存在(BusinessError 24000003)→ asset.update()(覆盖旧值)
   *
   * @param key — API key 字符串(trim 由调用方负责)
   */
  public static async put(key: string): Promise<void> {
    const queryMap: asset.AssetMap = new Map();
    queryMap.set(asset.Tag.ALIAS, ApiKeyVault.strToBytes(ASSET_NAME));

    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, ApiKeyVault.strToBytes(ASSET_NAME));
    attributes.set(asset.Tag.SECRET, ApiKeyVault.strToBytes(key));
    // API 9 不支持 DEVICE_UNLOCKED,使用默认行为(DEVICE_POWERED_ON)
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);

    try {
      await asset.add(attributes);
    } catch (e) {
      // BusinessError 24000003: asset already exists — fallback 到 update
      const err: Error = e as Error;
      const errCode: number = (e as Record<string, Object>)['code'] as number;
      if (errCode === 24000003) {
        // 用 ALIAS 查询,覆盖 SECRET + ACCESSIBILITY
        await asset.update(queryMap, attributes);
        return;
      }
      throw err;
    }
  }

  /**
   * 删除 AssetStoreKit 中的 API key
   * 静默失败(不影响 UI 状态)
   */
  public static async clear(): Promise<void> {
    try {
      const queryMap: asset.AssetMap = new Map();
      queryMap.set(asset.Tag.ALIAS, ApiKeyVault.strToBytes(ASSET_NAME));
      await asset.remove(queryMap);
    } catch (_e) {
      // 静默失败
    }
  }

  /**
   * 读旧版本 preferences 中的 api_key(迁移兼容)
   * @returns string | null — 旧 key,或不存在/空时 null
   */
  private static async readLegacyPreferences(): Promise<string | null> {
    try {
      const p: preferences.Preferences = await preferences.getPreferences(getContext(), LEGACY_STORE_NAME);
      const k: string = await p.get(LEGACY_KEY_API_KEY, '') as string;
      return k.length > 0 ? k : null;
    } catch (_e) {
      return null;
    }
  }

  /**
   * string <-> Uint8Array (UTF-8) helper
   * AssetStoreKit Value 类型只接受 Uint8Array
   */
  private static strToBytes(s: string): Uint8Array {
    const encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
    return encoder.encodeInto(s);
  }

  private static bytesToStr(bytes: Uint8Array): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(bytes);
  }
}