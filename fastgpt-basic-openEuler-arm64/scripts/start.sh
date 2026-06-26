#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  bash ./scripts/init-env.sh
fi

bash ./scripts/preflight.sh

FILES=(-f docker-compose.upstream.yml -f docker-compose.arm64.override.yml)

if [ "${PULL_IMAGES:-0}" = "1" ]; then
  docker compose "${FILES[@]}" pull
fi
docker compose "${FILES[@]}" up -d
docker compose "${FILES[@]}" ps
