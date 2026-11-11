# MindTrace Embedding Service — CPU-only container
# 构建: docker compose build embedding
# 运行: docker compose up -d embedding
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models/hf \
    SENTENCE_TRANSFORMERS_HOME=/models/hf \
    HF_ENDPOINT=https://hf-mirror.com \
    MT_EMBED_MODEL=BAAI/bge-m3

# libgomp1 是 CPU 版 PyTorch 的运行依赖；其余依赖由 wheel 提供。
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# PyPI 默认镜像可覆盖；国内网络默认走清华镜像，避免依赖下载卡在几十 KB/s。
ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

COPY requirements.txt ./
# 先装 CPU 版 torch，避免 sentence-transformers 从 PyPI 拉入 CUDA 版本。
RUN python -m pip install --upgrade pip --index-url ${PIP_INDEX_URL} \
    && python -m pip install --index-url https://download.pytorch.org/whl/cpu torch \
    && python -m pip install --index-url ${PIP_INDEX_URL} -r requirements.txt

COPY server.py onnx_backend.py entrypoint.sh ./
RUN chmod +x /app/entrypoint.sh

EXPOSE 8001

# 启动时会先 warmup（bge-m3 首次下载/加载可达数分钟），因此 start-period 放宽到 15 分钟。
HEALTHCHECK --interval=30s --timeout=5s --start-period=900s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health', timeout=3)"]

CMD ["python", "server.py"]
ENTRYPOINT ["/app/entrypoint.sh"]
