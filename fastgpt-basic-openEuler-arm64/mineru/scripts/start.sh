#!/usr/bin/env bash
###############################################################################
# start.sh — 启动 MinerU PDF 解析容器（服务器端）
#
# MinerU 以 CPU 模式运行（pipeline 后端），完全不依赖 NPU。
# 镜像在构建时已卸载 torch_npu，因此不需要挂载 NPU 驱动或设备节点。
#
# 模型已内置在镜像中，无需外部挂载。
#
# 用法: bash start.sh
#   可通过环境变量覆盖:
#     MINERU_BIND_ADDR (默认 172.16.2.198)
#     MINERU_PORT      (默认 8010)
###############################################################################
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE_NAME="mineru:latest"
CONTAINER_NAME="mineru"

# 读取 .env 中的绑定地址/端口（若存在）
if [ -f "${ROOT_DIR}/.env" ]; then
  set -a; . "${ROOT_DIR}/.env"; set +a
fi
MINERU_BIND_ADDR="${MINERU_BIND_ADDR:-172.16.2.198}"
MINERU_PORT="${MINERU_PORT:-8010}"

echo "============================================================"
echo " 启动 MinerU 容器（纯 CPU 模式）"
echo " 绑定: ${MINERU_BIND_ADDR}:${MINERU_PORT}"
echo "============================================================"
echo ""

command -v docker >/dev/null 2>&1 || { echo "[FATAL] Docker 未安装"; exit 1; }
docker info >/dev/null 2>&1 || { echo "[FATAL] docker daemon 不可达"; exit 1; }

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[FATAL] 镜像 ${IMAGE_NAME} 不存在"
  echo "       请先运行: bash $(dirname "$0")/load.sh"
  exit 1
fi
echo "[OK] 镜像存在"

# 清理旧容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[INFO] 移除旧容器 ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null
fi

# 确保 mineru.json 存在（指向容器内模型路径）
MINERU_JSON="${ROOT_DIR}/mineru/mineru.json"
if [ ! -f "${MINERU_JSON}" ]; then
  echo "[FATAL] ${MINERU_JSON} 不存在"
  echo "       请先创建并指向容器内 PDF-Extract-Kit-1.0 的父目录"
  echo "       排查方法: docker run --rm ${IMAGE_NAME} find / -iname 'PDF-Extract-Kit*' -type d 2>/dev/null"
  exit 1
fi
echo "[OK] mineru.json 存在"

echo "[INFO] 启动容器..."
docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  -p "${MINERU_BIND_ADDR}:${MINERU_PORT}:8010" \
  -v "${MINERU_JSON}:/root/mineru.json:ro" \
  -e PORT=8010 \
  -e HOST=0.0.0.0 \
  -e MINERU_MODEL_SOURCE=local \
  -e MINERU_BACKEND=pipeline \
  -e MINERU_LANG=ch \
  -e TABLE_OUTPUT_FORMAT=markdown \
  -e CPU=True \
  -e PROCESSES_PER_GPU=1 \
  --ipc host \
  --shm-size 8g \
  "${IMAGE_NAME}"

sleep 5
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo ""
  echo "[OK] 容器运行中"
  if docker logs "${CONTAINER_NAME}" 2>&1 | grep -qE "Traceback|ImportError|FATAL"; then
    echo "[WARN] 容器内已检测到异常，请运行: docker logs ${CONTAINER_NAME}"
  fi
else
  echo ""
  echo "[FATAL] 容器启动后立即退出，最后 50 行日志:"
  docker logs "${CONTAINER_NAME}" 2>&1 | tail -50
  echo ""
  echo "排查建议: docker logs ${CONTAINER_NAME} | grep -E 'Error|ImportError|Traceback'"
  exit 1
fi

echo ""
echo "============================================================"
echo " 容器 ${CONTAINER_NAME} 已启动"
echo " 端点: http://${MINERU_BIND_ADDR}:${MINERU_PORT}/v2/parse/file"
echo ""
echo " 查看日志:   docker logs -f ${CONTAINER_NAME}"
echo " 停止:       bash $(dirname "$0")/stop.sh"
echo " 验证:       bash $(dirname "$0")/verify.sh"
echo ""
echo " 首次启动模型加载需 1-2 分钟，看到 'Application startup' 即就绪"
echo "============================================================"
