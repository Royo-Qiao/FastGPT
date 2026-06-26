#!/bin/sh
###############################################################################
# init-patch.sh — FastGPT 容器启动 wrapper
#
# 功能:
#   1. 替换 SSR 端 _error.js 为无副作用版本（消除 useMount toast）
#   2. 修改客户端 _error-*.js chunk，setTimeout 跳转延迟 2 秒 → 9e9 毫秒（~285 年）
#   3. 修改任何包含 push("/account/model") / push("/dashboard/agent") + 2e3
#      的 chunk，把 2e3 改成 9e9 —— 消除"未配置语言/索引模型"后的自动跳转
#   4. exec 原始 server.js
#
# 设计：所有 chunk patch 都从 .orig 重新生成（首次运行先备份），重启幂等
###############################################################################
set -e

PATCHES=/patches
NEXT_BASE=/app/projects/app/.next

echo "[init-patch] starting FastGPT with patches..."

# ─── 1. SSR 端替换 _error.js ────────────────────────────────────────────────
SSR_ERROR="${NEXT_BASE}/server/pages/_error.js"
SSR_PATCH="${PATCHES}/_error.server.js"

if [ -f "${SSR_ERROR}" ] && [ -f "${SSR_PATCH}" ]; then
  if [ ! -f "${SSR_ERROR}.orig" ]; then
    cp "${SSR_ERROR}" "${SSR_ERROR}.orig"
    echo "[init-patch] backup → ${SSR_ERROR}.orig"
  fi
  cp "${SSR_PATCH}" "${SSR_ERROR}"
  echo "[init-patch] SSR _error.js replaced"
else
  echo "[init-patch] WARN: SSR _error or patch not found, skipped"
fi

# ─── 2. _error chunk 改 setTimeout 延迟 ─────────────────────────────────────
ERROR_PATCHED=0
for chunk in "${NEXT_BASE}/static/chunks/pages/"_error-*.js; do
  [ -f "${chunk}" ] || continue
  if [ ! -f "${chunk}.orig" ]; then
    cp "${chunk}" "${chunk}.orig"
  fi
  sed -e 's/,2e3)/,9e9)/g' -e 's/,2000)/,9e9)/g' "${chunk}.orig" > "${chunk}"
  ERROR_PATCHED=$((ERROR_PATCHED + 1))
done

# ─── 3. dashboard 入口 guard 跳转延迟 ───────────────────────────────────────
# 匹配 chunk 中 push("/dashboard/agent")},2e3) 模式（覆盖 LLM/embedding guard）
# 已 patched 的文件不会被 grep 命中；首次需备份 .orig；后续从 .orig 重新生成
MODEL_PATCHED=0
for chunk in "${NEXT_BASE}/static/chunks/"*.js; do
  [ -f "${chunk}" ] || continue
  # 已备份 → 检查 .orig 是否含目标模式；否则检查当前文件
  src="${chunk}.orig"
  [ -f "${src}" ] || src="${chunk}"
  if grep -F -q '/dashboard/agent")},2e3)' "${src}" 2>/dev/null; then
    if [ ! -f "${chunk}.orig" ]; then
      cp "${chunk}" "${chunk}.orig"
    fi
    sed -e 's|/account/model")},2e3)|/account/model")},9e9)|g' \
        -e 's|/dashboard/agent")},2e3)|/dashboard/agent")},9e9)|g' \
        "${chunk}.orig" > "${chunk}"
    MODEL_PATCHED=$((MODEL_PATCHED + 1))
    echo "[init-patch] model-redirect patched: $(basename "${chunk}")"
  fi
done

echo "[init-patch] done. _error chunks: ${ERROR_PATCHED}, model-redirect chunks: ${MODEL_PATCHED}. exec server.js..."

# ─── 4. exec 原始 server.js（保留 PID 1） ───────────────────────────────────
exec node --max-old-space-size=4096 ./projects/app/server.js
