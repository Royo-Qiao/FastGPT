#!/usr/bin/env bash
###############################################################################
# deploy-qwen.sh — Qwen3.6-27B 一键部署脚本
#
# 前置条件:
#   - models/ 目录已拷贝到 /data/ 下（/data/models/qwen3.6-27b/ 和 /data/models/deploy/）
#   - 当前用户 root 或有 docker 权限
#   - NPU 驱动已安装
#
# 用法:
#   TP_SIZE=1 NPU_DEVICE_ID=2 bash deploy-qwen.sh                  # 单卡
#   TP_SIZE=2 NPU_DEVICE_IDS=2,3 bash deploy-qwen.sh            # 双卡
#   TP_SIZE=2 NPU_DEVICE_IDS=2,3 bash deploy-qwen.sh /custom/path
###############################################################################
set -euo pipefail

BASE_DIR="${1:-/data/models}"
MODEL_DIR="${BASE_DIR}/qwen3.6-27b"
DEPLOY_DIR="${BASE_DIR}/deploy"
SCRIPT_DIR="${DEPLOY_DIR}/qwen3.6-27b-scripts"
IMAGE_TAR="${DEPLOY_DIR}/vllm-ascend-v0.18.0.tar"
IMAGE_NAME="quay.m.daocloud.io/ascend/vllm-ascend:v0.18.0"
TP_SIZE="${TP_SIZE:-1}"

# 校验设备参数与 start-qwen.sh 保持一致
if [ "${TP_SIZE}" -eq 1 ]; then
  NPU_DEVICE_ID="${NPU_DEVICE_ID:-}"
  NPU_DEVICE_IDS="${NPU_DEVICE_IDS:-${NPU_DEVICE_ID:-}}"

  if [ -z "${NPU_DEVICE_IDS}" ]; then
    echo "[FATAL] TP_SIZE=1 时必须指定 NPU_DEVICE_ID 或 NPU_DEVICE_IDS，例: NPU_DEVICE_ID=0 bash deploy-qwen.sh"
    exit 1
  fi
else
  NPU_DEVICE_IDS="${NPU_DEVICE_IDS:?TP_SIZE=${TP_SIZE} 时必须指定 NPU_DEVICE_IDS，例: NPU_DEVICE_IDS=0,1 bash deploy-qwen.sh}"
fi

NPU_DEVICES=(${NPU_DEVICE_IDS//,/ })
echo "============================================================"
echo " Qwen3.6-27B 服务器部署"
echo " 部署目录: ${BASE_DIR}"
echo " NPU: davinci${NPU_DEVICE_IDS//,/, davinci}"
echo " TP:  ${TP_SIZE}"
echo "============================================================"
echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 1: 环境检查
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 1/4: 环境检查                                          │"
echo "└─────────────────────────────────────────────────────────────┘"

if ! command -v docker &>/dev/null; then
  echo "[FATAL] docker 未安装"; exit 1
fi
echo "[OK] docker: $(docker --version)"

if [ ! -d "${BASE_DIR}" ]; then
  echo "[FATAL] 部署目录不存在: ${BASE_DIR}"; exit 1
fi
echo "[OK] 部署目录: ${BASE_DIR}"

if [ ! -f "${IMAGE_TAR}" ]; then
  echo "[FATAL] 镜像文件不存在: ${IMAGE_TAR}"; exit 1
fi
echo "[OK] 镜像文件: $(du -h "${IMAGE_TAR}" | cut -f1)"

if [ ! -f "${MODEL_DIR}/config.json" ]; then
  echo "[FATAL] 模型目录不完整: ${MODEL_DIR}"; exit 1
fi
echo "[OK] 模型目录: ${MODEL_DIR}"

# 检查所有指定设备是否存在
for dev_id in "${NPU_DEVICES[@]}"; do
  if [ ! -e "/dev/davinci${dev_id}" ]; then
    echo "[FATAL] NPU 设备 /dev/davinci${dev_id} 不存在"
    echo "        可用设备: $(ls /dev/davinci* 2>/dev/null | grep -E 'davinci[0-9]+$' | sed 's|/dev/davinci||' | sort | tr '\n' ' ')"
    exit 1
  fi
done

AVAILABLE_NPUS=$(ls /dev/davinci* 2>/dev/null | grep -E 'davinci[0-9]+$' | wc -l)
echo "[OK] NPU 设备: ${AVAILABLE_NPUS} 张"

if [ ! -d "/usr/local/Ascend/driver" ]; then
  echo "[FATAL] 驱动目录不存在: /usr/local/Ascend/driver"; exit 1
fi
echo "[OK] NPU 驱动目录存在"

ROOT_AVAIL_KB=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
ROOT_AVAIL_GB=$((ROOT_AVAIL_KB / 1024 / 1024))
echo "[INFO] 根分区可用空间: ${ROOT_AVAIL_GB}GB"
if [ ${ROOT_AVAIL_GB} -lt 20 ]; then
  echo "[FATAL] 可用空间不足 20GB"; exit 1
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 2: 加载 Docker 镜像
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 2/4: 加载 Docker 镜像                                  │"
echo "└─────────────────────────────────────────────────────────────┘"

if docker image inspect "${IMAGE_NAME}" &>/dev/null; then
  echo "[SKIP] 镜像已存在，跳过加载"
else
  echo "[INFO] 加载镜像中..."
  docker load -i "${IMAGE_TAR}"
  echo "[OK] 镜像加载完成"
fi

docker image inspect "${IMAGE_NAME}" &>/dev/null || { echo "[FATAL] 镜像加载后验证失败"; exit 1; }
echo "[OK] 镜像验证通过: ${IMAGE_NAME}"
echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 3: 启动推理服务
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 3/4: 启动推理服务                                      │"
echo "└─────────────────────────────────────────────────────────────┘"

MODEL_DIR="${MODEL_DIR}" \
  TP_SIZE="${TP_SIZE}" \
  NPU_DEVICE_IDS="${NPU_DEVICE_IDS}" \
  bash "${SCRIPT_DIR}/start-qwen.sh"
echo ""

# ═══════════════════════════════════════════════════════════════════
# STEP 4: 等待服务就绪并验证
# ═══════════════════════════════════════════════════════════════════
echo "┌─────────────────────────────────────────────────────────────┐"
echo "│ STEP 4/4: 等待服务就绪                                      │"
echo "└─────────────────────────────────────────────────────────────┘"

echo "[INFO] 等待 vLLM 服务就绪（首次约 5-10 分钟）..."
echo "[INFO] 另开终端运行 'docker logs -f vllm-qwen' 查看进度"
echo ""

MAX_WAIT=1200
WAITED=0
INTERVAL=30

while [ ${WAITED} -lt ${MAX_WAIT} ]; do
  if curl -sf --max-time 5 http://127.0.0.1:8901/health >/dev/null 2>&1; then
    echo ""
    echo "[OK] 服务已就绪！(等待了 ${WAITED} 秒)"
    echo ""
    echo "[INFO] 运行验证..."
    bash "${SCRIPT_DIR}/verify-qwen.sh"
    echo ""
    echo "============================================================"
    echo " 部署完成！"
    echo ""
    echo " API 端点:    http://127.0.0.1:8901/v1"
    echo " 模型名称:    qwen3.6-27b"
    echo ""
    echo " 管理命令:"
    echo "   docker logs -f vllm-qwen     # 查看日志"
    echo "   docker restart vllm-qwen     # 重启服务"
    echo "   docker stop vllm-qwen        # 停止服务"
    echo ""
    echo " 测试请求:"
    echo "   curl http://127.0.0.1:8901/v1/chat/completions \\"
    echo "     -H \"Content-Type: application/json\" \\"
    echo "     -d '{\"model\":\"qwen3.6-27b\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}],\"max_tokens\":100}'"
    echo "============================================================"
    exit 0
  fi

  if ! docker ps --format '{{.Names}}' | grep -q "^vllm-qwen$"; then
    echo ""
    echo "[FATAL] 容器已退出！查看日志:"
    docker logs --tail 30 vllm-qwen
    exit 1
  fi

  printf "\r[WAIT] 已等待 %d/%d 秒..." ${WAITED} ${MAX_WAIT}
  sleep ${INTERVAL}
  WAITED=$((WAITED + INTERVAL))
done

echo ""
echo "[FATAL] 等待超时 (${MAX_WAIT}s)。请手动检查:"
echo "        docker logs --tail 50 vllm-qwen"
exit 1
