#!/usr/bin/env bash
###############################################################################
# build.sh — 在有网络的 macOS 上构建 MinerU Docker 镜像
#
# 前置: 需要重新获取 MinerU 源码与模型（见 README.md "重建镜像"）
#       目录结构（相对于本文件上级的上级，即包根的同级）:
#         <work>/mineru/MinerU          (MinerU 源码)
#         <work>/mineru/MinerU_fastgpt  (FastGPT API 适配)
#         <work>/mineru/huggingface     (预下载的模型)
#
# 用法: WORK_DIR=/path/to/work bash build.sh
###############################################################################
set -euo pipefail

MINERU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$(dirname "$(dirname "${MINERU_DIR}")")/models}"

DOCKERFILE="${MINERU_DIR}/Dockerfile"
IMAGE_NAME="mineru:latest"

echo "============================================================"
echo " 构建 MinerU Docker 镜像"
echo " 工作目录: ${WORK_DIR}"
echo "============================================================"
echo ""

command -v docker >/dev/null 2>&1 || { echo "[FATAL] Docker 未安装"; exit 1; }

[ -d "${WORK_DIR}/mineru/MinerU" ] || { echo "[FATAL] 缺少源码: ${WORK_DIR}/mineru/MinerU"; exit 1; }
[ -d "${WORK_DIR}/mineru/MinerU_fastgpt" ] || { echo "[FATAL] 缺少: ${WORK_DIR}/mineru/MinerU_fastgpt"; exit 1; }
[ -d "${WORK_DIR}/mineru/huggingface" ] || { echo "[FATAL] 缺少模型: ${WORK_DIR}/mineru/huggingface"; exit 1; }

# 清理 macOS 元数据文件（._* 会破坏 Docker 构建上下文）
find "${WORK_DIR}/mineru" -name '._*' -type f -delete 2>/dev/null || true

echo "[INFO] 开始构建（10-30 分钟）..."
docker build -t "${IMAGE_NAME}" -f "${DOCKERFILE}" "${WORK_DIR}"

echo ""
echo "============================================================"
echo " 构建完成"
docker images "${IMAGE_NAME}"
echo ""
echo " 下一步: bash $(dirname "$0")/export.sh"
echo "============================================================"
