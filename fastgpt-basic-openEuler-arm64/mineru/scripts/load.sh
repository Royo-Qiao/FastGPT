#!/usr/bin/env bash
###############################################################################
# load.sh — 服务器端加载 MinerU Docker 镜像（离线）
#
# 自动处理两种情况：
#   1. mineru.tar.gz 已存在 → 直接校验并加载
#   2. 仅有 parts/ 分片 → 提示先运行 parts/merge.sh
#
# 用法: bash load.sh
###############################################################################
set -euo pipefail

MINERU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_FILE="${MINERU_DIR}/mineru.tar.gz"
IMAGE_NAME="mineru:latest"

echo "============================================================"
echo " 加载 MinerU Docker 镜像"
echo "============================================================"
echo ""

command -v docker >/dev/null 2>&1 || { echo "[FATAL] Docker 未安装"; exit 1; }
docker info >/dev/null 2>&1 || { echo "[FATAL] docker daemon 不可达"; exit 1; }

# 如果整体 tar.gz 不存在但分片存在，提示先合并
if [ ! -f "${IMAGE_FILE}" ]; then
  if [ -d "${MINERU_DIR}/parts" ] && ls "${MINERU_DIR}/parts/mineru.part."* >/dev/null 2>&1; then
    echo "[INFO] 检测到分片包，未合并"
    echo "       请先运行: bash ${MINERU_DIR}/parts/merge.sh"
    echo "       合并完成后再运行: bash $0"
    exit 1
  else
    echo "[FATAL] 镜像文件不存在: ${IMAGE_FILE}"
    echo "       也未检测到 parts/ 分片"
    exit 1
  fi
fi

echo "[OK] 找到镜像文件 ($(du -h "${IMAGE_FILE}" | cut -f1))"

# SHA256 校验（支持 sha256sum / shasum）
if [ -f "${IMAGE_FILE}.sha256" ]; then
  echo "[INFO] 校验 SHA256..."
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "${MINERU_DIR}" && sha256sum -c mineru.tar.gz.sha256) || { echo "[FATAL] SHA256 校验失败，文件可能损坏"; exit 1; }
  else
    (cd "${MINERU_DIR}" && shasum -a 256 -c mineru.tar.gz.sha256) || { echo "[FATAL] SHA256 校验失败，文件可能损坏"; exit 1; }
  fi
  echo "[OK] SHA256 校验通过"
else
  echo "[WARN] 未找到 .sha256 文件，跳过校验"
fi

if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[WARN] 镜像 ${IMAGE_NAME} 已存在，跳过加载"
  echo "       如需强制重新加载: docker rmi ${IMAGE_NAME} && bash $0"
else
  echo "[INFO] 加载镜像（约 1-3 分钟）..."
  gunzip -c "${IMAGE_FILE}" | docker load
fi

echo ""
echo "[OK] 镜像加载完成"
docker images "${IMAGE_NAME}"
echo ""
echo "============================================================"
echo " 下一步: bash $(dirname "$0")/start.sh"
echo "============================================================"
