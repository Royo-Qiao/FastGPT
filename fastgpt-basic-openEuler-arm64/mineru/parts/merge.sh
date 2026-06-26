#!/usr/bin/env bash
###############################################################################
# merge.sh — 服务器端合并 mineru.part.* 分片为 mineru.tar.gz 并校验
#
# 推荐流程：
#   1. 从 U 盘把 parts/ 目录整体拷到服务器本地磁盘（不要在 U 盘上合并）
#   2. 在服务器本地目录运行: bash merge.sh
#
# 用法:
#   bash merge.sh                 # 默认输出到 ../mineru.tar.gz
#   bash merge.sh /path/to/output.tar.gz
###############################################################################
set -euo pipefail

PARTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="${1:-${PARTS_DIR}/../mineru.tar.gz}"

echo "============================================================"
echo " 合并 MinerU 镜像分片"
echo " 分片目录: ${PARTS_DIR}"
echo " 输出文件: ${OUT_FILE}"
echo "============================================================"
echo ""

cd "${PARTS_DIR}"

# 1. 检查分片完整性
echo "[1/3] 校验各分片 SHA256..."
[ -f mineru.parts.sha256 ] || { echo "[FATAL] 缺少 mineru.parts.sha256"; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c mineru.parts.sha256
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c mineru.parts.sha256
else
  echo "[FATAL] 未找到 sha256sum 或 shasum"; exit 1
fi
echo "[OK] 所有分片完整"
echo ""

# 2. 合并
echo "[2/3] 合并分片（约 1-2 分钟）..."
PARTS=$(ls mineru.part.* | sort)
echo "      分片数: $(echo "${PARTS}" | wc -l | tr -d ' ')"
cat ${PARTS} > "${OUT_FILE}"
echo "[OK] 合并完成: $(du -h "${OUT_FILE}" | cut -f1)"
echo ""

# 3. 校验合并后的整体文件
echo "[3/3] 校验合并后的整体 SHA256..."
[ -f mineru.full.sha256 ] || { echo "[FATAL] 缺少 mineru.full.sha256"; exit 1; }
OUT_DIR="$(cd "$(dirname "${OUT_FILE}")" && pwd)"
OUT_NAME="$(basename "${OUT_FILE}")"
EXPECTED=$(awk '{print $1}' mineru.full.sha256)

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL=$(sha256sum "${OUT_FILE}" | awk '{print $1}')
else
  ACTUAL=$(shasum -a 256 "${OUT_FILE}" | awk '{print $1}')
fi

if [ "${EXPECTED}" = "${ACTUAL}" ]; then
  echo "[OK] SHA256 一致: ${ACTUAL}"
else
  echo "[FATAL] SHA256 不匹配"
  echo "  期望: ${EXPECTED}"
  echo "  实际: ${ACTUAL}"
  exit 1
fi

# 同步生成同级 .sha256 供 load.sh 使用
echo "${EXPECTED}  ${OUT_NAME}" > "${OUT_FILE}.sha256"

echo ""
echo "============================================================"
echo " 合并完成，镜像包可用"
echo " 文件: ${OUT_FILE}"
echo " 大小: $(du -h "${OUT_FILE}" | cut -f1)"
echo ""
echo " 下一步: cd $(dirname "${OUT_FILE}") && bash scripts/load.sh"
echo "============================================================"
