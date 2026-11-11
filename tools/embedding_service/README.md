# Embedding Service

本机 BGE embedding + rerank 服务，OpenAI 兼容 `/v1`，默认端口 **8001**。

## Docker

前置：已启动 Docker Desktop（Linux 容器）。

首次构建：

```bash
docker compose build embedding
```

Docker Desktop 的 registry mirror 已配置为 `docker.m.daocloud.io` / `docker.1ms.run` / `docker.1panel.live`；原配置备份在 `~/.docker/daemon.json.bak-20261111`。如果拉取基础镜像仍失败，恢复该备份并检查网络。

国内网络默认走清华 PyPI 镜像；海外网络可覆盖为官方源：

```bash
PIP_INDEX_URL=https://pypi.org/simple docker compose build embedding
```

启动。复用本机已有的 HuggingFace 模型缓存，避免在容器里重新下载约 8GB：

```bash
# Git Bash
MT_HF_CACHE=C:/Users/<you>/.cache/huggingface docker compose up -d embedding
```

```powershell
# PowerShell
$env:MT_HF_CACHE="C:/Users/<you>/.cache/huggingface"
docker compose up -d embedding
```

不设置 `MT_HF_CACHE` 时，compose 会把仓库内 `.cache/huggingface` 挂进容器；首次启动仍会下载模型。

容器启动时 `entrypoint.sh` 会把 `refs/main` 对应的 snapshot 路径直接交给模型，避免 HF Hub 重新解析版本。已有缓存且不想联网时可加：

```bash
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
MT_HF_CACHE=C:/Users/<you>/.cache/huggingface \
docker compose up -d embedding
```

检查（Git Bash 下用 `--data-binary`，避免 `-d` 被 shell 改写）：

```bash
curl http://127.0.0.1:8001/health
curl -X POST http://127.0.0.1:8001/v1/embeddings \
  -H "Content-Type: application/json" \
  --data-binary '{"input":"矩阵的秩"}'
```

日志、停止、重启：

```bash
docker compose logs -f embedding
docker compose stop embedding
docker compose up -d embedding
```

手机/小艺访问：`http://<PC 局域网 IP>:8001/v1`，或继续用 `hdc rport tcp:8001 tcp:8001` 后填 `http://127.0.0.1:8001/v1`。

模型缓存卷/目录：

- `MT_HF_CACHE` 指向宿主机缓存目录时，容器内 `/models/hf` 直接复用；entrypoint 会优先用 `refs/main` 的 snapshot。
- 已保留 `bge-m3` + `bge-reranker-base`；旧的 `bge-large-zh-v1.5` 缓存已删除。
- 首次加载 `BAAI/bge-m3` + `BAAI/bge-reranker-base` 可能需要数分钟；`HEALTHCHECK` 的 `start_period` 已放宽到 15 分钟。
- 容器内使用 CPU 版 PyTorch；镜像首次构建会下载 torch wheel，耗时取决于网络。

## 原生启动（已弃用）

`tools\embedding_service\start.bat` 仅保留作应急；日常入口统一走 Docker。原生 `.venv` 已删除，必要时脚本会自行重建。

## 注意

- 容器与原生服务不能同时占用 8001；切换前先停止另一个。
- App 的 embedding model 必须与服务端 `MT_EMBED_MODEL` 一致（默认 `BAAI/bge-m3`），否则向量会按旧模型标记。
- 模型权重不进镜像；不要把 `.cache/huggingface` 或 `.venv` 提交到仓库。
