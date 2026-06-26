#!/usr/bin/env bash
###############################################################################
# verify.sh — 验证 MinerU 服务可用性
###############################################################################
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${ROOT_DIR}/.env" ]; then
  set -a; . "${ROOT_DIR}/.env"; set +a
fi
MINERU_BIND_ADDR="${MINERU_BIND_ADDR:-172.16.2.198}"
MINERU_PORT="${MINERU_PORT:-8010}"
BASE_URL="http://${MINERU_BIND_ADDR}:${MINERU_PORT}"

echo "============================================================"
echo " MinerU 服务验证"
echo " 端点: ${BASE_URL}"
echo "============================================================"
echo ""

# 1. 容器状态
echo "1. 容器状态..."
if ! docker ps --format '{{.Names}}' | grep -q "^mineru$"; then
  echo "[FATAL] 容器 mineru 未运行"
  echo "       运行: bash $(dirname "$0")/start.sh"
  exit 1
fi
echo "[OK] 容器运行中"

# 2. API 可达性
echo ""
echo "2. API 可达性..."
ok=0
if curl -sf --max-time 10 "${BASE_URL}/docs" >/dev/null 2>&1; then
  echo "[OK] FastAPI /docs 可访问"
  ok=1
elif curl -sf --max-time 10 -X OPTIONS "${BASE_URL}/v2/parse/file" >/dev/null 2>&1; then
  echo "[OK] /v2/parse/file 端点响应"
  ok=1
else
  echo "[WARN] API 暂不可达（模型可能仍在加载）"
  echo "       查看日志: docker logs -f mineru"
fi

echo ""
echo "============================================================"
if [ "$ok" = 1 ]; then
  echo " [OK] MinerU 服务就绪"
else
  echo " [WARN] 服务尚未就绪，等待 1-2 分钟后重试"
fi
echo ""
echo " 解析测试:"
echo "   curl -X POST '${BASE_URL}/v2/parse/file' -F 'file=@test.pdf'"
echo ""
echo " FastGPT 集成（config.json 已预配置）:"
echo "   customPdfParse.url = ${BASE_URL}/v2/parse/file"
echo "============================================================"
