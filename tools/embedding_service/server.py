"""MindTrace Embedding Service — OpenAI-compatible /v1/embeddings backed by BGE.

Run:  python server.py           (or use start.bat)
Env:  MT_EMBED_MODEL  model id, default BAAI/bge-large-zh-v1.5
      MT_EMBED_PORT   port,     default 8001

The phone app only needs:  endpoint http://<this-pc-lan-ip>:8001/v1  +  model name.
BGE 中文检索模型要求查询加指令前缀、文档不加；前缀由应用侧在查询时拼好，
这里按原文编码即可，不要在这里再加前缀。
"""

import os
import socket
import threading
import time
from typing import List, Optional, Union

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sentence_transformers import CrossEncoder, SentenceTransformer
import uvicorn

try:
    from onnx_backend import OnnxEmbedder, OnnxReranker
    ONNX_IMPORT_OK = True
except Exception as exc:  # onnxruntime 没装时退回 PyTorch
    ONNX_IMPORT_OK = False
    print(f"[onnx] unavailable, falling back to torch: {exc}", flush=True)

# 嵌入：ONNX 与 PyTorch 输出完全一致（实测同一文本余弦 1.0000）。
# 单进程基准 ONNX 快 3.5-4.3 倍（查询 42ms vs 145ms、笔记 231ms vs 990ms），
# 但在本服务里与 PyTorch 重排模型同住时反而更慢（实测 309ms vs 145ms），
# 疑似 3.4GB 常驻内存下的页缓存压力与 ORT/PyTorch 线程池争用。
# 因此默认仍用 PyTorch；确认值得后再用 MT_USE_ONNX_EMBED=1 打开。
USE_ONNX_EMBED = ONNX_IMPORT_OK and os.environ.get("MT_USE_ONNX_EMBED", "0") == "1"
# 重排：仓库里的 bge-reranker-base ONNX 与 safetensors 不是同一权重（同一对文档分数对不上），
#       默认仍走 PyTorch；确认权重一致后再用 MT_USE_ONNX_RERANK=1 打开。
USE_ONNX_RERANK = ONNX_IMPORT_OK and os.environ.get("MT_USE_ONNX_RERANK", "0") == "1"

MODEL_ID = os.environ.get("MT_EMBED_MODEL", "BAAI/bge-large-zh-v1.5")
RERANK_MODEL_ID = os.environ.get("MT_RERANK_MODEL", "BAAI/bge-reranker-base")
RERANK_ENABLED = os.environ.get("MT_ENABLE_RERANK", "1") != "0"
PORT = int(os.environ.get("MT_EMBED_PORT", "8001"))
MAX_BATCH = 32
MAX_RERANK_DOCS = 64

app = FastAPI(title="MindTrace Embedding Service")

_lock = threading.Lock()
_model: Optional[SentenceTransformer] = None
_rerank_lock = threading.Lock()
_reranker: Optional[CrossEncoder] = None
_onnx_embedder = None
_onnx_reranker = None


def get_onnx_embedder():
    global _onnx_embedder
    with _lock:
        if _onnx_embedder is None:
            print(f"[embedding] loading onnx {MODEL_ID} ...", flush=True)
            started = time.time()
            _onnx_embedder = OnnxEmbedder(MODEL_ID)
            print(f"[embedding] onnx loaded in {time.time() - started:.1f}s", flush=True)
    return _onnx_embedder


def get_onnx_reranker():
    global _onnx_reranker
    with _rerank_lock:
        if _onnx_reranker is None:
            print(f"[rerank] loading onnx {RERANK_MODEL_ID} ...", flush=True)
            started = time.time()
            _onnx_reranker = OnnxReranker(RERANK_MODEL_ID)
            print(f"[rerank] onnx loaded in {time.time() - started:.1f}s", flush=True)
    return _onnx_reranker


def embed_texts(texts: List[str]):
    if USE_ONNX_EMBED:
        return get_onnx_embedder().embed(texts)
    model = get_model()
    with _lock:
        return model.encode(texts, normalize_embeddings=True,
                            convert_to_numpy=True, show_progress_bar=False)


def rerank_scores(query: str, documents: List[str]) -> List[float]:
    if USE_ONNX_RERANK:
        return get_onnx_reranker().score(query, documents)
    model = get_reranker()
    with _rerank_lock:
        return [float(value) for value in model.predict([(query, d) for d in documents])]


def get_reranker() -> CrossEncoder:
    global _reranker
    with _rerank_lock:
        if _reranker is None:
            print(f"[rerank] loading {RERANK_MODEL_ID} ...", flush=True)
            started = time.time()
            _reranker = CrossEncoder(RERANK_MODEL_ID)
            print(f"[rerank] loaded in {time.time() - started:.1f}s", flush=True)
    return _reranker


def get_model() -> SentenceTransformer:
    global _model
    with _lock:
        if _model is None:
            print(f"[embedding] loading {MODEL_ID} ...", flush=True)
            started = time.time()
            _model = SentenceTransformer(MODEL_ID)
            dim = _model.get_sentence_embedding_dimension()
            print(f"[embedding] loaded in {time.time() - started:.1f}s, dim={dim}", flush=True)
    return _model


class EmbeddingRequest(BaseModel):
    model: Optional[str] = None
    input: Union[str, List[str]]
    encoding_format: Optional[str] = None


class RerankRequest(BaseModel):
    model: Optional[str] = None
    query: str
    documents: List[str]
    top_n: Optional[int] = None


@app.get("/health")
def health() -> dict:
    return {"ok": True, "model": MODEL_ID}


@app.post("/v1/embeddings")
def embeddings(request: EmbeddingRequest) -> dict:
    texts = [request.input] if isinstance(request.input, str) else list(request.input)
    texts = [t for t in texts if isinstance(t, str)][:MAX_BATCH]
    if not texts:
        return {"object": "list", "data": [], "model": MODEL_ID,
                "usage": {"prompt_tokens": 0, "total_tokens": 0}}

    vectors = embed_texts(texts)

    data = [
        {
            "object": "embedding",
            "index": index,
            "embedding": [float(value) for value in vector],
        }
        for index, vector in enumerate(vectors)
    ]
    return {
        "object": "list",
        "data": data,
        "model": MODEL_ID,
        "usage": {"prompt_tokens": 0, "total_tokens": 0},
    }


@app.post("/v1/rerank")
def rerank(request: "RerankRequest") -> dict:
    if not RERANK_ENABLED:
        raise HTTPException(status_code=503, detail="rerank disabled")
    documents = [d for d in request.documents if isinstance(d, str)][:MAX_RERANK_DOCS]
    if not documents:
        return {"results": [], "model": RERANK_MODEL_ID}
    scores = rerank_scores(request.query, documents)
    results = [
        {"index": index, "relevance_score": float(score)}
        for index, score in enumerate(scores)
    ]
    results.sort(key=lambda item: item["relevance_score"], reverse=True)
    if request.top_n:
        results = results[: request.top_n]
    return {"results": results, "model": RERANK_MODEL_ID}


def lan_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


if __name__ == "__main__":
    print("=" * 56, flush=True)
    print(f"  MindTrace Embedding Service  model={MODEL_ID}", flush=True)
    print(f"  Embed backend: {'onnxruntime' if USE_ONNX_EMBED else 'pytorch'}", flush=True)
    print(f"  Rerank: {'off' if not RERANK_ENABLED else RERANK_MODEL_ID + ' (' + ('onnx' if USE_ONNX_RERANK else 'pytorch') + ')'}", flush=True)
    print(f"  App Embedding Endpoint: http://{lan_ip()}:{PORT}/v1", flush=True)
    print("  手机需与电脑在同一局域网; 首次启动会下载模型（约 1.3GB）", flush=True)
    print("=" * 56, flush=True)
    # 启动即加载：冷加载放在首次请求里会超过客户端读超时，导致第一次调用必然失败。
    print("[embedding] warming up, please wait ...", flush=True)
    embed_texts(["warmup"])
    if RERANK_ENABLED:
        rerank_scores("warmup", ["warmup"])
    print("[embedding] ready", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
