#!/usr/bin/env bash
###############################################################################
# deploy-bge.sh — BGE-M3 + BGE-Reranker 一键部署脚本
#
# 启动 embedding 与 reranker 两个服务（默认都绑定到 NPU 0）。
# 两个服务很小（~2GB HBM 各），单卡足够。
#
# 用法:
#   bash /data/models/deploy/bge-scripts/deploy-bge.sh
#   bash /data/models/deploy/bge-scripts/deploy-bge.sh /custom/path
#   NPU_ID=1 bash /data/models/deploy/bge-scripts/deploy-bge.sh  # 指定 NPU
###############################################################################
set -euo pipefail

BASE_DIR="${1:-/data/models}"
DEPLOY_DIR="${BASE_DIR}/deploy"
M3_DIR="${BASE_DIR}/bge-m3"
RER_DIR="${BASE_DIR}/bge-reranker-v2-m3"
IMAGE_TAR="${DEPLOY_DIR}/vllm-ascend-v0.13.0rc3.tar"
IMAGE_NAME="quay.m.daocloud.io/ascend/vllm-ascend:v0.13.0rc3"
if [ -z "${NPU_ID:-}" ]; then
  echo "[FATAL] 必须指定 NPU_ID，例: NPU_ID=1 bash deploy-bge.sh"; exit 1
fi

echo "============================================================"
echo " BGE-M3 + BGE-Reranker 服务器部署"
echo " 部署目录: ${BASE_DIR}"
echo " NPU:      davinci${NPU_ID}"
echo "============================================================"
echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 1: 环境检查
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 1/4: 环境检查                                          │"
echo "└─────────────────────────────────────────────────────────────┘"

command -v docker &>/dev/null || { echo "[FATAL] docker 未安装"; exit 1; }
echo "[OK] docker: $(docker --version)"

[ -d "${BASE_DIR}" ] || { echo "[FATAL] 部署目录不存在: ${BASE_DIR}"; exit 1; }
[ -f "${IMAGE_TAR}" ] || { echo "[FATAL] 镜像文件不存在: ${IMAGE_TAR}"; exit 1; }
[ -f "${M3_DIR}/config.json" ] || { echo "[FATAL] bge-m3 模型目录不完整: ${M3_DIR}"; exit 1; }
[ -f "${RER_DIR}/config.json" ] || { echo "[FATAL] bge-reranker 模型目录不完整: ${RER_DIR}"; exit 1; }
echo "[OK] 镜像 + bge-m3 + bge-reranker-v2-m3 完整"

[ -e "/dev/davinci${NPU_ID}" ] || { echo "[FATAL] NPU 设备不存在: /dev/davinci${NPU_ID}"; exit 1; }
[ -d "/usr/local/Ascend/driver" ] || { echo "[FATAL] 驱动目录不存在"; exit 1; }
echo "[OK] NPU /dev/davinci${NPU_ID} + 驱动 OK"

echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 2: 加载 Docker 镜像
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 2/4: 加载 Docker 镜像                                  │"
echo "└─────────────────────────────────────────────────────────────┘"

if docker image inspect "${IMAGE_NAME}" &>/dev/null; then
  echo "[SKIP] 镜像已存在"
else
  echo "[INFO] 加载镜像中..."
  docker load -i "${IMAGE_TAR}"
fi
docker image inspect "${IMAGE_NAME}" &>/dev/null || { echo "[FATAL] 镜像加载失败"; exit 1; }
echo "[OK] 镜像就绪: ${IMAGE_NAME}"
echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 3: 启动两个服务
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 3/4: 启动 BGE-M3 + BGE-Reranker                        │"
echo "└─────────────────────────────────────────────────────────────┘"

MODEL_DIR="${M3_DIR}"  NPU_ID="${NPU_ID}" bash "${DEPLOY_DIR}/bge-scripts/start-bge-m3.sh"
echo ""
MODEL_DIR="${RER_DIR}" NPU_ID="${NPU_ID}" bash "${DEPLOY_DIR}/bge-scripts/start-bge-reranker.sh"
echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 4: 等待就绪并验证
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 4/4: 等待服务就绪                                      │"
echo "└─────────────────────────────────────────────────────────────┘"

echo "[INFO] 等待两个服务就绪（约 1-3 分钟）..."
echo "[INFO] 跟踪日志：docker logs -f vllm-bge-m3   或   docker logs -f vllm-bge-reranker"
echo ""

MAX_WAIT=600
WAITED=0
INTERVAL=10
M3_READY=0
RER_READY=0

while [ ${WAITED} -lt ${MAX_WAIT} ]; do
  if [ ${M3_READY} -eq 0 ] && curl -sf --max-time 5 http://127.0.0.1:8904/health >/dev/null 2>&1; then
    M3_READY=1
    echo ""
    echo "[OK] BGE-M3 就绪 (${WAITED}s)"
  fi
  if [ ${RER_READY} -eq 0 ] && curl -sf --max-time 5 http://127.0.0.1:8905/health >/dev/null 2>&1; then
    RER_READY=1
    echo ""
    echo "[OK] BGE-Reranker 就绪 (${WAITED}s)"
  fi
  if [ ${M3_READY} -eq 1 ] && [ ${RER_READY} -eq 1 ]; then
    break
  fi

  # 容器健康检查
  for name in vllm-bge-m3 vllm-bge-reranker; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
      echo ""
      echo "[FATAL] 容器 ${name} 已退出"
      docker logs --tail 30 ${name}
      exit 1
    fi
  done

  printf "\r[WAIT] 已等待 %d/%d 秒  m3=%d reranker=%d" ${WAITED} ${MAX_WAIT} ${M3_READY} ${RER_READY}
  sleep ${INTERVAL}
  WAITED=$((WAITED + INTERVAL))
done

if [ ${M3_READY} -eq 0 ] || [ ${RER_READY} -eq 0 ]; then
  echo ""
  echo "[FATAL] 等待超时. m3=${M3_READY} reranker=${RER_READY}"
  echo "        手动查日志:"
  echo "        docker logs --tail 50 vllm-bge-m3"
  echo "        docker logs --tail 50 vllm-bge-reranker"
  exit 1
fi

echo ""
echo "[INFO] 运行验证..."
bash "${DEPLOY_DIR}/bge-scripts/verify-bge.sh"
echo ""
echo "============================================================"
echo " 部署完成！"
echo ""
echo " BGE-M3 (Embedding):   POST http://127.0.0.1:8904/v1/embeddings"
echo " BGE-Reranker:         POST http://127.0.0.1:8905/v1/rerank"
echo "                       POST http://127.0.0.1:8905/v1/score"
echo ""
echo " 管理:"
echo "   docker logs -f vllm-bge-m3        # 日志（embedding）"
echo "   docker logs -f vllm-bge-reranker  # 日志（reranker）"
echo "   bash ${DEPLOY_DIR}/bge-scripts/stop-bge.sh   # 停止两个"
echo "============================================================"
