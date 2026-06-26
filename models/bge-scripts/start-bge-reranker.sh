#!/usr/bin/env bash
###############################################################################
# start-bge-reranker.sh — 启动 BGE-Reranker-v2-m3 Score/Rerank 推理服务
#
# API: POST http://127.0.0.1:8903/v1/rerank
#      POST http://127.0.0.1:8903/v1/score
#
# 前置条件:
#   - docker 已安装且可运行
#   - 镜像 quay.m.daocloud.io/ascend/vllm-ascend:v0.13.0rc3 已 load
#   - 模型已拷贝到 /data/models/bge-reranker-v2-m3/
#   - NPU Driver 已安装，/dev/davinci* 设备节点存在
###############################################################################
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/data/models/bge-reranker-v2-m3}"
IMAGE=quay.m.daocloud.io/ascend/vllm-ascend:v0.13.0rc3
CONTAINER_NAME=vllm-bge-reranker
PORT=8905
if [ -z "${NPU_ID:-}" ]; then
  echo "[FATAL] 必须指定 NPU_ID，例: NPU_ID=1 bash start-bge-reranker.sh"; exit 1
fi

echo "[CHECK] 验证环境..."

if ! command -v docker &>/dev/null; then
  echo "[FATAL] docker 未安装"; exit 1
fi

if ! docker image inspect "${IMAGE}" &>/dev/null; then
  echo "[FATAL] 镜像 ${IMAGE} 未加载"; exit 1
fi

if [ ! -f "${MODEL_DIR}/config.json" ]; then
  echo "[FATAL] 模型目录不存在: ${MODEL_DIR}"; exit 1
fi

if [ ! -e "/dev/davinci${NPU_ID}" ]; then
  echo "[FATAL] NPU 设备不存在: /dev/davinci${NPU_ID}"
  echo "        现有设备: $(ls /dev/davinci* 2>/dev/null | tr '\n' ' ')"
  exit 1
fi
echo "[OK] NPU 设备: /dev/davinci${NPU_ID}"

for dev in davinci_manager devmm_svm hisi_hdc; do
  [ -e "/dev/${dev}" ] || { echo "[FATAL] 缺少设备节点: /dev/${dev}"; exit 1; }
done

if [ ! -d "/usr/local/Ascend/driver" ]; then
  echo "[FATAL] NPU 驱动目录不存在: /usr/local/Ascend/driver"; exit 1
fi

echo "[CHECK] 环境验证通过"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[INFO] 移除旧容器 ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}"
fi

echo "[INFO] 启动 BGE-Reranker 容器..."

docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  --device "/dev/davinci${NPU_ID}" \
  --device /dev/davinci_manager \
  --device /dev/devmm_svm \
  --device /dev/hisi_hdc \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v "${MODEL_DIR}":/models/bge-reranker-v2-m3:ro \
  --shm-size=8g \
  --ulimit memlock=-1 \
  -p ${PORT}:${PORT} \
  -e OMP_PROC_BIND=false \
  -e OMP_NUM_THREADS=4 \
  -e PYTORCH_NPU_ALLOC_CONF=expandable_segments:True \
  -e TASK_QUEUE_ENABLE=1 \
  "${IMAGE}" \
  vllm serve /models/bge-reranker-v2-m3 \
    --runner pooling \
    --convert classify \
    --max-model-len 8192 \
    --served-model-name bge-reranker-v2-m3 \
    --gpu-memory-utilization 0.05 \
    --max-num-seqs 64 \
    --tensor-parallel-size 1 \
    --dtype float16 \
    --port ${PORT}

echo ""
echo "============================================"
echo " 容器 ${CONTAINER_NAME} 已启动"
echo " 模型: BAAI/bge-reranker-v2-m3 (Reranker)"
echo " 端口: ${PORT}    NPU: davinci${NPU_ID}"
echo " API:  POST http://127.0.0.1:${PORT}/v1/rerank"
echo "       POST http://127.0.0.1:${PORT}/v1/score"
echo " 日志: docker logs -f ${CONTAINER_NAME}"
echo " 首次启动约 1-3 分钟"
echo "============================================"
