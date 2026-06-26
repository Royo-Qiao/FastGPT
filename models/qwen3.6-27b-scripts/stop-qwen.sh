#!/usr/bin/env bash
###############################################################################
# stop-qwen.sh — 停止并移除 Qwen3.6-27B 推理容器
###############################################################################
set -euo pipefail

CONTAINER_NAME=vllm-qwen

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  docker stop "${CONTAINER_NAME}" && docker rm "${CONTAINER_NAME}"
  echo "[OK] 容器 ${CONTAINER_NAME} 已停止并移除"
else
  echo "[INFO] 容器 ${CONTAINER_NAME} 不存在"
fi
