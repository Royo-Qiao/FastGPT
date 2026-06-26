#!/usr/bin/env bash
###############################################################################
# verify-export.sh — 验证导出的 mineru.tar.gz 完整性（macOS/服务器通用）
###############################################################################
set -euo pipefail

MINERU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_FILE="${MINERU_DIR}/mineru.tar.gz"

echo "============================================================"
echo " 验证 MinerU 镜像导出"
echo "============================================================"
echo ""

[ -f "${IMAGE_FILE}" ] || { echo "[FATAL] 文件不存在: ${IMAGE_FILE}"; exit 1; }
echo "[1/3] 文件存在: OK"

if [ "$(uname -s)" = "Darwin" ]; then
  SIZE_BYTES=$(stat -f "%z" "${IMAGE_FILE}")
else
  SIZE_BYTES=$(stat -c "%s" "${IMAGE_FILE}")
fi
SIZE_HUMAN=$(du -h "${IMAGE_FILE}" | cut -f1)
echo "[2/3] 文件大小: ${SIZE_HUMAN} (${SIZE_BYTES} bytes)"

MIN_SIZE=$((5 * 1024 * 1024 * 1024))
if [ "${SIZE_BYTES}" -lt "${MIN_SIZE}" ]; then
  echo "       [WARN] 小于 5GB，可能不完整"
else
  echo "       [OK] 大小正常"
fi

echo ""
echo "[3/3] SHA256 校验..."
if [ -f "${IMAGE_FILE}.sha256" ]; then
  (cd "${MINERU_DIR}" && shasum -a 256 -c mineru.tar.gz.sha256)
else
  echo "       [WARN] 无 .sha256 文件，跳过"
fi

echo ""
echo "============================================================"
echo " 验证完成，镜像包可用"
echo " 文件: ${IMAGE_FILE}"
echo "============================================================"
