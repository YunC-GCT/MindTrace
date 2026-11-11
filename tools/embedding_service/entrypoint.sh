#!/bin/sh
set -eu

# 已有 HuggingFace 缓存时，直接把 refs/main 对应的 snapshot 路径交给模型，
# 避免 transformers 重新解析 revision 或走网络。
resolve_snapshot() {
    model="$1"
    case "$model" in
        */*) ;;
        *) return 0 ;;
    esac
    org="${model%%/*}"
    name="${model#*/}"
    root="/models/hf/hub/models--${org}--${name}"
    if [ -f "$root/refs/main" ] && [ -d "$root/snapshots" ]; then
        snap="$(cat "$root/refs/main")"
        if [ -d "$root/snapshots/$snap" ]; then
            printf '%s' "$root/snapshots/$snap"
        fi
    fi
}

if [ -z "${MT_EMBED_MODEL_PATH:-}" ]; then
    resolved="$(resolve_snapshot "${MT_EMBED_MODEL:-BAAI/bge-m3}")"
    [ -n "$resolved" ] && export MT_EMBED_MODEL_PATH="$resolved"
fi

if [ -z "${MT_RERANK_MODEL_PATH:-}" ]; then
    resolved="$(resolve_snapshot "${MT_RERANK_MODEL:-BAAI/bge-reranker-base}")"
    [ -n "$resolved" ] && export MT_RERANK_MODEL_PATH="$resolved"
fi

exec "$@"
