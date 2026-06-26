#!/usr/bin/env bash
###############################################################################
# deploy.sh — MinerU 一键部署（服务器端，离线）
#
# 自动检测分片场景：
#   - 若仅有 parts/ 分片，先合并再加载
#   - 若 mineru.tar.gz 已存在，直接加载
#
# 用法: bash deploy.sh
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINERU_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================================"
echo " MinerU 一键部署"
echo "============================================================"
echo ""

# 步骤 0: 若是分片包则先合并
if [ ! -f "${MINERU_DIR}/mineru.tar.gz" ] && [ -d "${MINERU_DIR}/parts" ]; then
  if ls "${MINERU_DIR}/parts/mineru.part."* >/dev/null 2>&1; then
    echo "[0/3] 检测到分片包，先合并..."
    bash "${MINERU_DIR}/parts/merge.sh"
    echo ""
  fi
fi

echo "[1/3] 加载镜像..."
bash "${SCRIPT_DIR}/load.sh"
echo ""

echo "[2/3] 启动容器..."
bash "${SCRIPT_DIR}/start.sh"
echo ""

echo "[3/3] 验证服务..."
bash "${SCRIPT_DIR}/verify.sh"
echo ""

echo "============================================================"
echo " 部署完成"
echo "============================================================"
