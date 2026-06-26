#!/usr/bin/env bash
###############################################################################
# start-qwen.sh — 启动 Qwen3.6-27B 推理服务
#
# 前置条件:
#   - docker 已安装且可运行
#   - 镜像 quay.m.daocloud.io/ascend/vllm-ascend:v0.18.0 已 load
#   - 模型已拷贝到 /data/models/qwen3.6-27b/
#   - NPU Driver 已安装，/dev/davinci* 设备节点存在
#
# 用法:
#   TP_SIZE=1 NPU_DEVICE_ID=0 bash start-qwen.sh                 # 单卡
#   TP_SIZE=2 NPU_DEVICE_IDS=0,1 bash start-qwen.sh            # 双卡（从 0 开始连续）
#   TP_SIZE=2 NPU_DEVICE_IDS=2,3 bash start-qwen.sh          # 双卡（从 2 开始连续）
###############################################################################
set -euo pipefail

MODEL_DIR="${MODEL_DIR:-/data/models/qwen3.6-27b}"
IMAGE=quay.m.daocloud.io/ascend/vllm-ascend:v0.18.0
CONTAINER_NAME=vllm-qwen
PORT=8901
TP_SIZE="${TP_SIZE:-2}"

# ─── 前置检查 ───────────────────────────────────────────────────────────────
echo "[CHECK] 验证环境..."

if ! command -v docker &>/dev/null; then
  echo "[FATAL] docker 未安装"; exit 1
fi

if ! docker image inspect "${IMAGE}" &>/dev/null; then
  echo "[FATAL] 镜像 ${IMAGE} 未加载，请先执行: docker load -i <tar文件路径>"; exit 1
fi

if [ ! -f "${MODEL_DIR}/config.json" ]; then
  echo "[FATAL] 模型目录不存在或不完整: ${MODEL_DIR}"; exit 1
fi

# 解析 NPU 设备列表
if [ "${TP_SIZE}" -eq 1 ]; then
  # 单卡模式：兼容旧环境变量
  NPU_DEVICE_ID="${NPU_DEVICE_ID:-}"
  NPU_DEVICE_IDS="${NPU_DEVICE_IDS:-${NPU_DEVICE_ID:-}}"

  if [ -z "${NPU_DEVICE_IDS}" ]; then
    echo "[FATAL] TP_SIZE=1 时必须指定 NPU_DEVICE_ID 或 NPU_DEVICE_IDS，例: NPU_DEVICE_ID=0 bash start-qwen.sh"
    exit 1
  fi

  NPU_DEVICES=(${NPU_DEVICE_IDS//,/ })
else
  # 多卡模式：必须指定 NPU_DEVICE_IDS
  NPU_DEVICE_IDS="${NPU_DEVICE_IDS:?TP_SIZE=${TP_SIZE} 时必须指定 NPU_DEVICE_IDS，例: NPU_DEVICE_IDS=0,1 bash start-qwen.sh}"
  NPU_DEVICES=(${NPU_DEVICE_IDS//,/ })
fi

# 校验设备数量与 TP_SIZE 一致
if [ ${#NPU_DEVICES[@]} -ne "${TP_SIZE}" ]; then
  echo "[FATAL] TP_SIZE=${TP_SIZE} 但指定了 ${#NPU_DEVICES[@]} 个设备 (${NPU_DEVICE_IDS})"
  exit 1
fi

# 检查所有设备是否存在
for dev_id in "${NPU_DEVICES[@]}"; do
  if [ ! -e "/dev/davinci${dev_id}" ]; then
    echo "[FATAL] NPU 设备 /dev/davinci${dev_id} 不存在"
    echo "        可用设备: $(ls /dev/davinci* 2>/dev/null | grep -E 'davinci[0-9]+$' | sed 's|/dev/davinci||' | sort | tr '\n' ' ')"
    exit 1
  fi
done

echo "[OK] NPU 设备: davinci${NPU_DEVICE_IDS//,/, davinci}"

for dev in davinci_manager devmm_svm hisi_hdc; do
  if [ ! -e "/dev/${dev}" ]; then
    echo "[FATAL] 缺少设备节点: /dev/${dev}"; exit 1
  fi
done

DRIVER_VER=$(cat /usr/local/Ascend/driver/version.info 2>/dev/null | grep "^Version" | cut -d= -f2 || echo "unknown")
echo "[OK] NPU Driver: ${DRIVER_VER}"

# 构建 --device 参数
DEVICE_ARGS=""
for dev_id in "${NPU_DEVICES[@]}"; do
  DEVICE_ARGS="${DEVICE_ARGS} --device /dev/davinci${dev_id}"
done
DEVICE_ARGS="${DEVICE_ARGS} --device /dev/davinci_manager --device /dev/devmm_svm --device /dev/hisi_hdc"

if [ ! -d "/usr/local/Ascend/driver" ]; then
  echo "[FATAL] NPU 驱动目录不存在: /usr/local/Ascend/driver"; exit 1
fi

echo "[CHECK] 环境验证通过"

# ─── 清理旧容器 ─────────────────────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[INFO] 停止并移除旧容器 ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}"
fi

# ─── 启动容器 ───────────────────────────────────────────────────────────────
echo "[INFO] 启动 Qwen3.6-27B 推理容器 (TP=${TP_SIZE})..."

docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  ${DEVICE_ARGS} \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver:ro \
  -v "${MODEL_DIR}":/models/qwen3.6-27b:ro \
  --shm-size=32g \
  --ulimit memlock=-1 \
  -p ${PORT}:${PORT} \
  -e OMP_PROC_BIND=false \
  -e OMP_NUM_THREADS=1 \
  -e PYTORCH_NPU_ALLOC_CONF=expandable_segments:True \
  -e TASK_QUEUE_ENABLE=1 \
  -e HCCL_BUFFSIZE=512 \
  -e ASCEND_VISIBLE_DEVICES=${NPU_DEVICE_IDS} \
  "${IMAGE}" \
  vllm serve /models/qwen3.6-27b \
    --host 0.0.0.0 \
    --port ${PORT} \
    --served-model-name qwen3.6-27b \
    --trust-remote-code \
    --seed 1024 \
    --data-parallel-size 1 \
    --tensor-parallel-size ${TP_SIZE} \
    --max-model-len 16384 \
    --max-num-seqs 16 \
    --max-num-batched-tokens 4096 \
    --gpu-memory-utilization 0.92 \
    --no-enable-prefix-caching \
    --speculative_config '{"method":"qwen3_5_mtp","num_speculative_tokens":3,"enforce_eager":true}' \
    --compilation-config '{"cudagraph_mode":"FULL_DECODE_ONLY"}' \
    --additional-config '{"enable_cpu_binding":true}' \
    --async-scheduling \
    --disable-log-requests

echo ""
echo "============================================"
echo " 容器 ${CONTAINER_NAME} 已启动"
echo " 模型: Qwen3.6-27B"
echo " 端口: ${PORT}"
echo " NPU:  davinci${NPU_DEVICE_IDS//,/, davinci}"
echo " TP:   ${TP_SIZE}"
echo " 日志: docker logs -f ${CONTAINER_NAME}"
echo ""
echo " 首次启动需要 5-10 分钟（模型加载 + NPU graph 编译）"
echo " 看到 'Application startup complete' 表示就绪"
echo "============================================"
