# MathMind OCR Service

This directory is the companion OCR service shipped with the Math_Mind project.
It is not executed inside the HarmonyOS HAP. Run it on a Windows PC, then let the
App call the PC over the local network.

## Requirements

- Windows 10/11
- Python 3.10 or later
- Optional for text OCR: Tesseract installed at `C:\Program Files\Tesseract-OCR\`

The first run may download OCR/model dependencies and can take several minutes.

## Start

From the project root:

```bat
start-ocr-server.bat
```

Or from this directory:

```bat
start.bat
```

When the script starts successfully, copy the value printed under:

```text
Enter this in the app OCR setting:
```

In the App OCR setting, entering only the IP is enough, for example:

```text
192.168.1.50
```

The App normalizes it to:

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
