#!/usr/bin/env bash
###############################################################################
# clean.sh — 完全清理 MinerU 部署痕迹（服务器端）
#
# 用于在重新部署前清空旧状态：容器、镜像、合并产物、临时文件。
# 不会删除 parts/ 分片包本身。
#
# 用法: bash clean.sh
###############################################################################
set -euo pipefail

MINERU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "============================================================"
echo " 清理 MinerU 旧部署"
echo "============================================================"
echo ""

# 1. 清理所有 mineru 相关容器（包括 patch/fix 等历史临时容器）
echo "[1/5] 清理容器..."
CONTAINERS=$(docker ps -a --format '{{.Names}}' | grep -E '^mineru($|-)' || true)
if [ -n "${CONTAINERS}" ]; then
  echo "${CONTAINERS}" | while read -r name; do
    echo "  - 移除容器: ${name}"
    docker rm -f "${name}" >/dev/null 2>&1 || true
  done
else
  echo "  无 mineru 相关容器"
fi

# 2. 删除 mineru 镜像
echo ""
echo "[2/5] 删除镜像..."
if docker image inspect mineru:latest >/dev/null 2>&1; then
  docker rmi -f mineru:latest >/dev/null
  echo "  - 已删除 mineru:latest"
else
  echo "  无 mineru:latest 镜像"
fi

# 3. 清理 dangling / 悬空层（被 commit 覆盖的旧层）
echo ""
echo "[3/5] 清理 dangling 镜像层..."
DANGLING=$(docker images -f "dangling=true" -q | wc -l | tr -d ' ')
if [ "${DANGLING}" -gt 0 ]; then
  docker image prune -f >/dev/null
  echo "  - 已清理 ${DANGLING} 个悬空层"
else
  echo "  无悬空层"
fi

# 4. 删除合并产物（上次部署可能留下的 mineru.tar.gz）
echo ""
echo "[4/5] 清理合并产物..."
REMOVED=0
for f in "${MINERU_DIR}/mineru.tar.gz" "${MINERU_DIR}/mineru.tar.gz.sha256"; do
  if [ -f "${f}" ]; then
    rm -f "${f}"
    echo "  - 已删除: ${f}"
    REMOVED=1
  fi
done
[ "${REMOVED}" = 0 ] && echo "  无合并产物"

# 5. 清理临时 Dockerfile（修复时可能产生）
echo ""
echo "[5/5] 清理临时文件..."
REMOVED=0
for f in /tmp/Dockerfile.mineru-fix /tmp/Dockerfile.fix; do
  if [ -f "${f}" ]; then
    rm -f "${f}"
    echo "  - 已删除: ${f}"
    REMOVED=1
  fi
done
[ "${REMOVED}" = 0 ] && echo "  无临时文件"

echo ""
echo "============================================================"
echo " 清理完成"
echo ""
echo " 剩余:"
echo "   parts/  : $(ls "${MINERU_DIR}/parts/mineru.part."* 2>/dev/null | wc -l | tr -d ' ') 个分片"
echo ""
echo " 下一步: bash $(dirname "$0")/deploy.sh"
echo "============================================================"
