#!/usr/bin/env bash
###############################################################################
# diagnose-patches.sh — 诊断 init-patch / plugin-patch 是否生效
#
# 用于排查"新增模型按钮触发异常跳转"等 patch 失效问题。
# 自动从脚本所在目录的上一级解析部署根目录。
#
# 用法：
#   bash scripts/diagnose-patches.sh
###############################################################################
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP="${APP:-fgbasic-app}"
PLUGIN="${PLUGIN:-fgbasic-plugin}"
COMPOSE_FILES=(-f docker-compose.upstream.yml -f docker-compose.arm64.override.yml)

hr() { printf '\n========== %s ==========\n' "$1"; }

hr "1. init-patch 启动日志"
docker logs "$APP" 2>&1 | grep -iE "init-patch|patched" | head -20 \
  || echo "(无 init-patch 日志 — entrypoint 可能没生效)"

hr "2. 容器用户 + /patches 挂载"
echo "Config.User = $(docker inspect "$APP" --format '{{.Config.User}}' 2>/dev/null)"
docker exec "$APP" sh -c 'id; echo; ls -la /patches/ 2>&1' || echo "(容器不可用)"

hr "3. 容器内 chunk 实际状态"
docker exec "$APP" sh -c '
echo "--- 含 /dashboard/agent 的 chunks ---"
grep -l "/dashboard/agent" /app/projects/app/.next/static/chunks/*.js 2>/dev/null | head -10
echo
echo "--- 跳转模式实际形态 ---"
for f in $(grep -l "/dashboard/agent" /app/projects/app/.next/static/chunks/*.js 2>/dev/null); do
  echo "  $(basename "$f"):"
  grep -oE "/dashboard/agent.{0,100}" "$f" | head -2 | sed "s/^/    /"
done
echo
echo "--- 仍含 \"},2e3)\" 跳转模式的 chunks（应为空） ---"
grep -l "\"},2e3)" /app/projects/app/.next/static/chunks/*.js 2>/dev/null | head -10 || echo "  (none)"
echo
echo "--- .orig 备份 ---"
ls /app/projects/app/.next/static/chunks/*.orig 2>/dev/null | head -5 || echo "  (无 .orig — init-patch 没跑过)"
'

hr "4. plugin /api/models 是否为空"
TOKEN=$(grep '^FASTGPT_PLUGIN_TOKEN=' .env 2>/dev/null | cut -d= -f2-)
if [ -n "$TOKEN" ]; then
  docker exec "$APP" sh -c "curl -s 'http://fastgpt-plugin:3000/api/models' -H 'Authorization: Bearer $TOKEN'" \
    | head -c 200
  echo
else
  echo "(.env 缺 FASTGPT_PLUGIN_TOKEN)"
fi

hr "5. plugin 容器是否挂了 plugin-patch/index.js"
docker exec "$PLUGIN" sh -c 'wc -c /app/dist/index.js /app/dist/index.js.orig 2>/dev/null || echo "no orig (未挂 patch)"'

hr "6. compose 实际渲染配置 (fastgpt-app section)"
docker compose "${COMPOSE_FILES[@]}" config 2>&1 \
  | awk '/^  fastgpt-app:/{flag=1} /^  [a-z][a-z-]*:/{if($0!~/fastgpt-app/) flag=0} flag' \
  | head -40

hr "诊断结束"
echo
echo "重点关注："
echo "  - 第 1 段：必须有 '[init-patch] starting...' 行"
echo "  - 第 3 段：跳转模式应为 '},9e9)' 而非 '},2e3)'；应有 .orig 文件"
echo "  - 第 4 段：plugin 应返回 'data:[]'"
echo "  - 第 5 段：dist/index.js 与 .orig 字节数应不同"
echo "  - 第 6 段：应含 user: root 和 entrypoint: /patches/init-patch.sh"
