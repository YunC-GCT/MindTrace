# MindTrace OCR Service — CPU-only container
# 构建: docker compose build ocr
# 运行: docker compose up -d ocr
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HOME=/root \
    TESSERACT_EXE=/usr/bin/tesseract \
    TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata

# PaddleOCR/OpenCV 运行依赖 + Tesseract 中文数据。
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        tesseract-ocr-chi-sim \
        libgl1 \
        libglib2.0-0 \
        libgomp1 \
        libsm6 \
        libxext6 \
        libxrender1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

COPY requirements.txt ./
RUN python -m pip install --upgrade pip --index-url ${PIP_INDEX_URL} \
    && python -m pip install --index-url ${PIP_INDEX_URL} -r requirements.txt

COPY app.py formula_api.py formula_tool.py ocr_text_tool.py ./

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/formula/health', timeout=3)"]

CMD ["python", "app.py"]
