#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [ "${1:-}" != "--force" ] && [ -f "$ENV_FILE" ]; then
  echo ".env already exists: $ENV_FILE"
  exit 0
fi

rand_hex() {
  local bytes="$1"
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$bytes"
  else
    dd if=/dev/urandom bs="$bytes" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
  fi
}

cat >"$ENV_FILE" <<EOF
COMPOSE_PROJECT_NAME=fgbasic

FASTGPT_BIND_ADDR=172.16.2.198
FASTGPT_PORT=13000
MCP_BIND_ADDR=172.16.2.198
MCP_PORT=13003
MINIO_BIND_ADDR=172.16.2.198
MINIO_API_PORT=19000
MINIO_CONSOLE_PORT=19001

FASTGPT_FE_DOMAIN=http://172.16.2.198:13000
FASTGPT_STORAGE_EXTERNAL_ENDPOINT=http://172.16.2.198:19000
# Used by scripts/detect-infer-endpoint.sh as a note only.
# Configure this in FastGPT's model provider UI after startup.
FASTGPT_INFER_BASE_URL=http://172.16.2.198:8010/v1

FASTGPT_DEFAULT_ROOT_PSW=fg-$(rand_hex 8)
FASTGPT_ROOT_KEY=fg-root-$(rand_hex 24)
FASTGPT_TOKEN_KEY=fg-token-$(rand_hex 24)
FASTGPT_FILE_TOKEN_KEY=fg-file-$(rand_hex 24)
FASTGPT_AES256_SECRET_KEY=$(rand_hex 32)
FASTGPT_PLUGIN_TOKEN=fg-plugin-$(rand_hex 24)
FASTGPT_CODE_SANDBOX_TOKEN=fg-code-$(rand_hex 24)
FASTGPT_AIPROXY_TOKEN=fg-aiproxy-$(rand_hex 24)

SANDBOX_POOL_SIZE=4
EOF

chmod 600 "$ENV_FILE"
echo "Generated $ENV_FILE"
