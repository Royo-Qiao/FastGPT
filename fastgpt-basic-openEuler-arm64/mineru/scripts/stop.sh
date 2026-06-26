#!/usr/bin/env bash
###############################################################################
# stop.sh — 停止并移除 MinerU 容器
###############################################################################
set -euo pipefail

CONTAINER_NAME="mineru"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[INFO] 停止并移除容器 ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
  echo "[OK] 已移除"
else
  echo "[INFO] 容器 ${CONTAINER_NAME} 不存在，无需操作"
fi
