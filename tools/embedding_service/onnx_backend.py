"""ONNX 后端：直接用 onnxruntime 跑 bge-m3 与 bge-reranker，绕开 PyTorch 的解释器开销。

为什么：同一台 CPU 上，PyTorch fp32 单条查询约 600ms，ONNX Runtime 通常能压到 1/2–1/3。
模型不换、精度不变，只换推理引擎。

用法：
    emb = OnnxEmbedder("BAAI/bge-m3")
    vectors = emb.embed(["文本一", "文本二"])      # 已 L2 归一化
    rr  = OnnxReranker("BAAI/bge-reranker-base")
    scores = rr.score("问题", ["文档一", "文档二"])  # 与 CrossEncoder.predict 同尺度的 logits
"""

import os
from typing import Dict, List

import numpy as np
import onnxruntime as ort
from huggingface_hub import snapshot_download
from transformers import AutoTokenizer

_ALLOW = [
    "onnx/*",
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
    "sentencepiece.bpe.model",
]


def _session(model_dir: str) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    # 单条查询用不满全部核，限制线程数可以降低争用；批量重建时仍然是这几条线程在跑。
    options.intra_op_num_threads = int(os.environ.get("MT_ORT_THREADS", "8"))
    return ort.InferenceSession(os.path.join(model_dir, "onnx", "model.onnx"),
                                sess_options=options,
                                providers=["CPUExecutionProvider"])


def _feed(session: ort.InferenceSession, encoded: Dict[str, np.ndarray]) -> Dict[str, np.ndarray]:
    names = {item.name for item in session.get_inputs()}
    feed: Dict[str, np.ndarray] = {}
    for key in ("input_ids", "attention_mask", "token_type_ids"):
        if key in names and key in encoded:
            feed[key] = encoded[key].astype(np.int64)
    return feed


class OnnxEmbedder:
    def __init__(self, repo_id: str, max_length: int = 512):
        self.repo_id = repo_id
        path = snapshot_download(repo_id, allow_patterns=_ALLOW)
        self.tokenizer = AutoTokenizer.from_pretrained(path)
        self.session = _session(path)
        self.max_length = max_length

    def embed(self, texts: List[str]) -> np.ndarray:
        encoded = self.tokenizer(texts, padding=True, truncation=True,
                                 max_length=self.max_length, return_tensors="np")
        outputs = self.session.run(None, _feed(self.session, encoded))
        hidden = outputs[0]
        # 3 维 = last_hidden_state（取 CLS）；2 维 = 模型已自带池化。
        pooled = hidden[:, 0] if hidden.ndim == 3 else hidden
        norms = np.linalg.norm(pooled, axis=1, keepdims=True)
        return pooled / np.clip(norms, 1e-12, None)


class OnnxReranker:
    def __init__(self, repo_id: str, max_length: int = 512):
        self.repo_id = repo_id
        path = snapshot_download(repo_id, allow_patterns=_ALLOW)
        self.tokenizer = AutoTokenizer.from_pretrained(path)
        self.session = _session(path)
        self.max_length = max_length

    def score(self, query: str, documents: List[str]) -> List[float]:
        if not documents:
            return []
        pairs = [(query, doc) for doc in documents]
        encoded = self.tokenizer(pairs, padding=True, truncation=True,
                                 max_length=self.max_length, return_tensors="np")
        outputs = self.session.run(None, _feed(self.session, encoded))
        logits = np.asarray(outputs[0]).reshape(-1).astype(np.float64)
        # sentence-transformers 的 CrossEncoder 对单标签模型内部套了 sigmoid；
        # 这里必须保持一致，否则应用侧校准好的置信度阈值（0.2）会失效。
        return (1.0 / (1.0 + np.exp(-logits))).tolist()
