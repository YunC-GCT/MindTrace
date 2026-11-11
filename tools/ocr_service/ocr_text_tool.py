import logging
import os
from pathlib import Path
from typing import List, Optional

import pytesseract
from PIL import Image

logger = logging.getLogger("mindtrace.ocr_text_tool")

_TESSERACT_EXE = os.environ.get("TESSERACT_EXE", r"C:\Program Files\Tesseract-OCR\tesseract.exe")
_TESSDATA_DIR = os.environ.get("TESSDATA_PREFIX", r"D:\Tesseract\tessdata")

if os.path.exists(_TESSERACT_EXE):
    pytesseract.pytesseract.tesseract_cmd = _TESSERACT_EXE
if os.path.isdir(_TESSDATA_DIR):
    os.environ["TESSDATA_PREFIX"] = _TESSDATA_DIR


class OcrTextTool:
    def __init__(self, lang: str = "chi_sim+eng"):
        self.lang = lang
        logger.info("Initializing Tesseract OCR fallback (lang=%s)", lang)

    def recognize(self, image_path: str) -> List[str]:
        logger.info("Fallback text OCR: %s", image_path)
        if not Path(image_path).exists():
            raise FileNotFoundError(f"Image does not exist: {image_path}")

        img = Image.open(image_path)
        text = pytesseract.image_to_string(img, lang=self.lang, config="--psm 6")
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        logger.info("Fallback text OCR recognized %d lines", len(lines))
        return lines

    def recognize_to_plain_text(self, image_path: str) -> str:
        return " ".join(self.recognize(image_path))


_default_ocr: Optional[OcrTextTool] = None


def recognize_text(image_path: str) -> List[str]:
    global _default_ocr
    if _default_ocr is None:
        _default_ocr = OcrTextTool()
    return _default_ocr.recognize(image_path)
