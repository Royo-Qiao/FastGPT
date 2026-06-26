#!/usr/bin/env bash
###############################################################################
# verify-bge.sh — 验证 BGE-M3 (embedding) + BGE-Reranker (rerank) 服务
###############################################################################
set -euo pipefail

EMB=http://127.0.0.1:8904
RER=http://127.0.0.1:8905
PASS=0
FAIL=0

pass() { echo -e "\033[32m[PASS]\033[0m $1"; PASS=$((PASS+1)); }
fail() { echo -e "\033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo " BGE 服务验证"
echo "========================================"

# ─── 容器状态 ─────────────────────────────────────
for name in vllm-bge-m3 vllm-bge-reranker; do
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    pass "容器 ${name} 正在运行"
  else
    fail "容器 ${name} 未运行"
  fi
done

# ─── BGE-M3 健康 + embedding 测试 ─────────────────
echo ""
echo "--- BGE-M3 Embedding (${EMB}) ---"
if curl -sf --max-time 5 "${EMB}/health" >/dev/null 2>&1; then
  pass "health 端点响应"
else
  fail "health 端点不可达"
fi

EMB_RESP=$(curl -sf --max-time 30 "${EMB}/v1/embeddings" \
  -H "Content-Type: application/json" \
  -d '{"model":"bge-m3","input":"hello world"}' 2>/dev/null || echo "")

if [ -n "$EMB_RESP" ]; then
  DIM=$(echo "$EMB_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['data'][0]['embedding']))" 2>/dev/null || echo "0")
  if [ "$DIM" = "1024" ]; then
    pass "embedding 返回 1024 维向量"
  else
    fail "embedding 维度异常: $DIM (期望 1024)"
  fi
else
  fail "embedding 请求失败"
fi

# ─── BGE-Reranker 健康 + rerank 测试 ──────────────
echo ""
echo "--- BGE-Reranker (${RER}) ---"
if curl -sf --max-time 5 "${RER}/health" >/dev/null 2>&1; then
  pass "health 端点响应"
else
  fail "health 端点不可达"
fi

RER_RESP=$(curl -sf --max-time 30 "${RER}/v1/rerank" \
  -H "Content-Type: application/json" \
  -d '{"model":"bge-reranker-v2-m3","query":"What is AI?","documents":["AI is artificial intelligence","The sky is blue","Machine learning is a subset of AI"]}' 2>/dev/null || echo "")

if [ -n "$RER_RESP" ]; then
  N=$(echo "$RER_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d['results']))" 2>/dev/null || echo "0")
  TOP_IDX=$(echo "$RER_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['results'][0]['index'])" 2>/dev/null || echo "?")
  if [ "$N" = "3" ]; then
    pass "rerank 返回 3 条结果，top=${TOP_IDX} (期望 0 或 2)"
  else
    fail "rerank 结果数量异常: $N"
  fi
else
  fail "rerank 请求失败"
fi

echo ""
echo "========================================"
echo " 结果: ${PASS} 通过 / ${FAIL} 失败"
echo "========================================"
[ ${FAIL} -gt 0 ] && exit 1 || exit 0
