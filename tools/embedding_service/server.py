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

    model = get_model()
    with _lock:
        vectors = model.encode(
            texts,
            normalize_embeddings=True,
            convert_to_numpy=True,
            show_progress_bar=False,
        )

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
    model = get_reranker()
    with _rerank_lock:
        scores = model.predict([(request.query, d) for d in documents])
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
    print(f"  Rerank: {'on, ' + RERANK_MODEL_ID if RERANK_ENABLED else 'off'}", flush=True)
    print(f"  App Embedding Endpoint: http://{lan_ip()}:{PORT}/v1", flush=True)
    print("  手机需与电脑在同一局域网; 首次启动会下载模型（约 1.3GB）", flush=True)
    print("=" * 56, flush=True)
    # 启动即加载：冷加载放在首次请求里会超过客户端读超时，导致第一次调用必然失败。
    print("[embedding] warming up, please wait ...", flush=True)
    get_model()
    if RERANK_ENABLED:
        get_reranker()
    print("[embedding] ready", flush=True)
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="info")
