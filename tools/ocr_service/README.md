# MathMind OCR Service

This directory is the companion OCR service shipped with the Math_Mind project.
It runs in Docker on the PC; the HarmonyOS App calls it over the local network.

## Docker（推荐）

前置：已启动 Docker Desktop（Linux 容器）。

```bash
docker compose build ocr
```

启动。复用本机已有 PaddleX 公式模型缓存：

```bash
# Git Bash
MT_PADDLEX_CACHE=C:/Users/<you>/.paddlex docker compose up -d ocr
```

```powershell
# PowerShell
$env:MT_PADDLEX_CACHE="C:/Users/<you>/.paddlex"
docker compose up -d ocr
```

不设置 `MT_PADDLEX_CACHE` 时，compose 会挂载仓库内 `.cache/paddlex`，首次识别仍会下载公式模型。

检查：

```bash
curl http://127.0.0.1:8000/api/v1/formula/health
docker compose logs -f ocr
```

镜像内置 `tesseract-ocr` + `tesseract-ocr-chi-sim`，Tesseract 不再依赖 Windows 的 `C:\Program Files\Tesseract-OCR`。

## 原生启动（已弃用）

`start-ocr-server.bat` / `tools\ocr_service\start.bat` 仅保留作应急；日常入口统一走 Docker。原生虚拟环境不再使用。

## Requirements

- Windows 10/11（Docker Desktop）
- 或 Python 3.10+（仅原生应急启动）

The first run may download OCR/model dependencies and can take several minutes.

App OCR setting: enter the PC LAN IPv4 only, for example `192.168.1.50`; the App normalizes it to:

```text
http://192.168.1.50:8000/api/v1/ocr/recognize
```

## Endpoints

- Combined OCR: `POST /api/v1/ocr/recognize`
- Formula OCR: `POST /api/v1/formula/recognize`
- Health check: `GET /api/v1/formula/health`
- API docs: `GET /docs`

Combined OCR accepts mode query parameters:

```text
/api/v1/ocr/recognize?mode=text
/api/v1/ocr/recognize?mode=formula&formula_timeout=30
/api/v1/ocr/recognize?mode=auto&formula_timeout=30
```

Use `text` for full pages and screenshots. Use `formula` only for cropped
single-formula or single-question images.

In `auto` and `formula` mode, the service first crops the bright document area
and detects a small number of formula-like blocks by projection. This is a
conservative first version, not full document layout analysis. Each request sends
at most 3 candidate blocks to FormulaNet.

## Network Note

Use the LAN IPv4 of the PC running this OCR service. Do not use the virtual
machine IP unless the OCR service itself is running inside that VM.
