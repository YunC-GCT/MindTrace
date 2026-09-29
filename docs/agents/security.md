# 安全 / 签名 / Secrets

## Secrets (绝不入 git)

- `.env` / `local.properties` 已在 `.gitignore`
- **API Key**: 用户在 App 内 "我的 → AI 模型配置" 设置, 持久化到 `@kit.AssetStoreKit`(TEE + AES256-GCM 加密, PR1 2026-09-06), 兼容读取: 启动时若 AssetStoreKit 空, fallback 旧 preferences key 并自动写回 AssetStoreKit(迁移透明, UI 无感知), **不入 git**
- **OCR 服务地址**: 默认 `localhost`, 部署到真机时改 IP

## 网络权限

- 已声明 `ohos.permission.INTERNET`

## 签名 (DevEco Studio 必须)

- 根 `build-profile.json5` 的 `signingConfigs` 必须显式共享给所有 HAP
- 否则不同 HAP 签名不一致, 安装失败

## 配置静默覆盖 (已知问题, 已修复)

⚠️ `LlmConfig.normalizeModel` / `normalizeEndpoint` 静默覆盖用户配置 (含 `siliconflow` / `v3` / `flash` / `r1` 等关键词)

**状态**: ✅ **已修复** (ticket #9, TDD: commits `acb1a1c` RED, `1a53a82` GREEN)

**新行为**: 命中 reserved keyword 时 `throw new LlmError(..., 'NORMALIZE_KEYWORD_REJECTED')`,带原始输入和 reserved-keyword 列表

**禁止**: 不要扩展 keyword 列表或恢复静默 fallback — 如需跳过 normalization, 在调用方做