#!/usr/bin/env bash
###############################################################################
# seed-models.sh — 往 FastGPT 的 system_models 集合写入自定义模型
#
# 行为：
#   通过 docker exec 进入 fgbasic-mongo 容器，对 system_models 集合做 upsert。
#   - 已激活（isActive=true）+ 已配置 URL/Key
#   - 重复执行幂等（upsert by model id）
#   - 删除 mongo 卷后需重跑
#
# 注意：URL 是从 fastgpt-app 容器内部视角看的地址。
#   容器内的 127.0.0.1 指容器自身，不是宿主机。
#   如果模型服务跑在宿主机上而不是容器网络中，请用以下任一方式：
#     - 设置 INFER_HOST=host.docker.internal 并在 fastgpt-app 中加 extra_hosts
#     - 设置 INFER_HOST=<宿主机内网 IP>（如 172.16.2.198）
#
# 用法：
#   bash scripts/seed-models.sh
#   INFER_HOST=host.docker.internal bash scripts/seed-models.sh
#   INFER_HOST=172.16.2.198 bash scripts/seed-models.sh
###############################################################################
set -euo pipefail

INFER_HOST="${INFER_HOST:-127.0.0.1}"
API_KEY="${LOCAL_API_KEY:-local-npu}"
MONGO_CONTAINER="${MONGO_CONTAINER:-fgbasic-mongo}"

# 检查容器在线
if ! docker ps --filter "name=${MONGO_CONTAINER}" --format '{{.Names}}' | grep -q "^${MONGO_CONTAINER}$"; then
  echo "[FATAL] container ${MONGO_CONTAINER} is not running" >&2
  exit 1
fi

echo "[seed-models] INFER_HOST=${INFER_HOST}"
echo "[seed-models] upserting to ${MONGO_CONTAINER}:fastgpt.system_models..."

docker exec -i "${MONGO_CONTAINER}" mongo --quiet \
  -u myusername -p mypassword --authenticationDatabase admin fastgpt <<EOF
var models = [
  {
    model: "qwen3.6-27b",
    metadata: {
      type: "llm",
      provider: "Qwen",
      model: "qwen3.6-27b",
      name: "Qwen3.6-27B",
      isActive: true,
      isCustom: true,
      requestUrl: "http://${INFER_HOST}:8901/v1/chat/completions",
      requestAuth: "${API_KEY}",
      maxContext: 32768,
      maxResponse: 8192,
      quoteMaxToken: 28000,
      maxTemperature: 1.5,
      showTopP: true,
      showStopSign: true,
      functionCall: true,
      toolChoice: true,
      vision: true,
      reasoning: false,
      datasetProcess: true,
      usedInClassify: true,
      usedInExtractFields: true,
      usedInToolCall: true,
      charsPointsPrice: 0,
      defaultConfig: {
        chat_template_kwargs: { thinking: false, enable_thinking: false }
      }
    }
  },
  {
    model: "BAAI/bge-m3",
    metadata: {
      type: "embedding",
      provider: "BAAI",
      model: "bge-m3",
      name: "bge-m3",
      isActive: true,
      isCustom: true,
      requestUrl: "http://${INFER_HOST}:8904/v1/embeddings",
      requestAuth: "${API_KEY}",
      defaultToken: 512,
      maxToken: 8192,
      weight: 100,
      normalization: true,
      batchSize: 16,
      charsPointsPrice: 0
    }
  },
  {
    model: "Qwen3-Embedding-4B",
    metadata: {
      type: "embedding",
      provider: "Qwen",
      model: "qwen3-embedding-4b",
      name: "Qwen3-Embedding-4B",
      isActive: true,
      isCustom: true,
      requestUrl: "http://${INFER_HOST}:8902/v1/embeddings",
      requestAuth: "${API_KEY}",
      defaultToken: 512,
      maxToken: 8192,
      weight: 90,
      normalization: true,
      batchSize: 16,
      charsPointsPrice: 0
    }
  },
  {
    model: "Qwen3-Embedding-8B",
    metadata: {
      type: "embedding",
      provider: "Qwen",
      model: "qwen3-embedding-8b",
      name: "Qwen3-Embedding-8B",
      isActive: true,
      isCustom: true,
      requestUrl: "http://${INFER_HOST}:8903/v1/embeddings",
      requestAuth: "${API_KEY}",
      defaultToken: 512,
      maxToken: 8192,
      weight: 95,
      normalization: true,
      batchSize: 16,
      charsPointsPrice: 0
    }
  }
];

models.forEach(function(m) {
  db.system_models.updateOne(
    { model: m.model },
    { \$set: { model: m.model, metadata: m.metadata } },
    { upsert: true }
  );
  print("upsert: " + m.model + " (" + m.metadata.type + ")");
});

print("total in collection: " + db.system_models.find().count());
EOF

echo "[seed-models] done."
echo
echo "下一步:"
echo "  1. 登录 FastGPT (root/123456): http://172.16.2.198:13000"
echo "  2. 账号 -> 模型提供商 -> 模型配置，应看到 Qwen3.6-27B + bge-m3 + Qwen3-Embedding-4B/8B"
echo "  3. 默认模型 Modal 中选择对应默认 LLM 和 Embedding"
