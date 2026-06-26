#!/usr/bin/env bash
###############################################################################
# export.sh — 导出 MinerU 镜像并切分为 500MB 分片（macOS 端）
#
# 输出:
#   parts/mineru.part.aa ~ parts/mineru.part.ao  (~15 个分片)
#   parts/mineru.parts.sha256                    (各分片校验和)
#   parts/mineru.full.sha256                     (合并后整体校验和)
#
# 切分原因: exFAT/NTFS 在 U 盘传输 4GB+ 单文件时偶发截断/损坏
###############################################################################
set -euo pipefail

MINERU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="mineru:latest"
TMP_FILE="${MINERU_DIR}/mineru.tar.gz"
PARTS_DIR="${MINERU_DIR}/parts"
SPLIT_SIZE="${SPLIT_SIZE:-500m}"

echo "============================================================"
echo " 导出 MinerU 镜像（分片模式）"
echo " 分片大小: ${SPLIT_SIZE}"
echo " 输出目录: ${PARTS_DIR}"
echo "============================================================"
echo ""

command -v docker >/dev/null 2>&1 || { echo "[FATAL] Docker 未安装"; exit 1; }
docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1 || { echo "[FATAL] 镜像 ${IMAGE_NAME} 不存在"; exit 1; }

echo "[INFO] 镜像大小: $(docker image inspect "${IMAGE_NAME}" --format '{{.Size}}' | awk '{printf "%.1f GB", $1/1024/1024/1024}')"

# 步骤 1: 导出整体 tar.gz
echo "[1/3] 导出镜像（5-15 分钟）..."
docker save "${IMAGE_NAME}" | gzip -6 > "${TMP_FILE}"
echo "[OK] 整体大小: $(du -h "${TMP_FILE}" | cut -f1)"

# 整体 SHA256
echo ""
echo "[2/3] 生成整体 SHA256..."
(cd "${MINERU_DIR}" && shasum -a 256 mineru.tar.gz > mineru.tar.gz.sha256)
cat "${TMP_FILE}.sha256"

# 步骤 3: 切分
echo ""
echo "[3/3] 切分为 ${SPLIT_SIZE} 分片..."
mkdir -p "${PARTS_DIR}"
rm -f "${PARTS_DIR}/mineru.part."* "${PARTS_DIR}/mineru.parts.sha256" "${PARTS_DIR}/mineru.full.sha256" 2>/dev/null || true
split -b "${SPLIT_SIZE}" -a 2 "${TMP_FILE}" "${PARTS_DIR}/mineru.part."

# 分片 SHA256
(cd "${PARTS_DIR}" && shasum -a 256 mineru.part.* > mineru.parts.sha256)
cp "${TMP_FILE}.sha256" "${PARTS_DIR}/mineru.full.sha256"

PART_COUNT=$(ls "${PARTS_DIR}/mineru.part."* | wc -l | tr -d ' ')
echo "[OK] 切分完成: ${PART_COUNT} 个分片"

# 清理临时整体文件（已分片，避免重复占空间）
echo ""
echo "[INFO] 删除临时整体文件（已分片）..."
rm -f "${TMP_FILE}" "${TMP_FILE}.sha256"

# 复制 merge.sh 模板到 parts/（若不存在）
if [ ! -f "${PARTS_DIR}/merge.sh" ]; then
  echo "[WARN] ${PARTS_DIR}/merge.sh 不存在，请手动从 git 恢复"
fi

echo ""
echo "============================================================"
echo " 导出完成"
echo ""
ls -lh "${PARTS_DIR}/" | head -20
echo ""
echo " 分片总大小: $(du -sh "${PARTS_DIR}" | cut -f1)"
echo " 分片数量:   ${PART_COUNT}"
echo ""
echo " 服务器端合并: bash parts/merge.sh"
echo "============================================================"
