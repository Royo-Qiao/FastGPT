#!/usr/bin/env bash
###############################################################################
# stop-bge.sh — 停止并移除 BGE 推理容器（两个）
###############################################################################
set -euo pipefail

for name in vllm-bge-m3 vllm-bge-reranker; do
  if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
    docker stop "${name}" && docker rm "${name}"
    echo "[OK] 容器 ${name} 已停止并移除"
  else
    echo "[INFO] 容器 ${name} 不存在"
  fi
done
