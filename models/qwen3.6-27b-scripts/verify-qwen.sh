#!/usr/bin/env bash
###############################################################################
# verify-qwen.sh — 验证 Qwen3.6-27B 推理服务
#
# 用法: bash verify-qwen.sh
# 前置: vllm-qwen 容器已启动并就绪
###############################################################################
set -euo pipefail

BASE=http://127.0.0.1:8901
PASS=0
FAIL=0

pass() { echo -e "\033[32m[PASS]\033[0m $1"; PASS=$((PASS+1)); }
fail() { echo -e "\033[31m[FAIL]\033[0m $1"; FAIL=$((FAIL+1)); }

echo "========================================"
echo " Qwen3.6-27B 部署验证"
echo "========================================"
echo ""

# ─── 1. 容器状态 ─────────────────────────────────────────────────────────────
echo "--- 容器状态 ---"
if docker ps --format '{{.Names}}' | grep -q "^vllm-qwen$"; then
  pass "容器 vllm-qwen 正在运行"
else
  fail "容器 vllm-qwen 未运行"
fi

# ─── 2. 健康检查 ─────────────────────────────────────────────────────────────
echo ""
echo "--- API 健康检查 ---"
if curl -sf --max-time 5 "${BASE}/health" >/dev/null 2>&1; then
  pass "健康端点响应正常"
else
  fail "健康端点不可达 (${BASE}/health)"
  echo "     模型可能仍在加载中，等待后重试"
fi

# ─── 3. 模型注册 ─────────────────────────────────────────────────────────────
echo ""
echo "--- 模型注册 ---"
MODELS_RESP=$(curl -sf --max-time 5 "${BASE}/v1/models" 2>/dev/null || echo "")
if [ -n "$MODELS_RESP" ]; then
  MODEL_ID=$(echo "$MODELS_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null || echo "")
  if [ "$MODEL_ID" = "qwen3.6-27b" ]; then
    pass "模型已注册: qwen3.6-27b"
  else
    fail "模型 ID 不匹配，期望 'qwen3.6-27b'，实际 '${MODEL_ID}'"
  fi
else
  fail "无法获取模型列表"
fi

# ─── 4. 基础推理 ─────────────────────────────────────────────────────────────
echo ""
echo "--- 推理测试 ---"
INFERENCE_RESP=$(curl -sf --max-time 60 "${BASE}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"Reply with exactly: INFERENCE_OK"}],"max_tokens":10,"temperature":0}' 2>/dev/null || echo "")

if [ -n "$INFERENCE_RESP" ]; then
  CONTENT=$(echo "$INFERENCE_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null || echo "")
  if [ -n "$CONTENT" ]; then
    pass "推理成功: ${CONTENT}"
  else
    fail "推理返回空内容"
    echo "     响应: ${INFERENCE_RESP:0:200}"
  fi
else
  fail "推理请求超时或失败"
fi

# ─── 5. 多轮对话测试 ─────────────────────────────────────────────────────────
echo ""
echo "--- 多轮对话测试 ---"
MULTI_RESP=$(curl -sf --max-time 60 "${BASE}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-27b","messages":[{"role":"user","content":"What is 2+3?"},{"role":"assistant","content":"5"},{"role":"user","content":"Multiply that by 2"}],"max_tokens":30,"temperature":0}' 2>/dev/null || echo "")

if [ -n "$MULTI_RESP" ]; then
  MULTI_CONTENT=$(echo "$MULTI_RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null || echo "")
  if [ -n "$MULTI_CONTENT" ]; then
    pass "多轮对话成功: ${MULTI_CONTENT}"
  else
    fail "多轮对话返回空"
  fi
else
  fail "多轮对话请求超时或失败"
fi

# ─── 结果汇总 ─────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " 结果: ${PASS} 通过 / ${FAIL} 失败"
echo "========================================"

if [ ${FAIL} -gt 0 ]; then
  exit 1
fi
