#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FILES=(-f docker-compose.upstream.yml -f docker-compose.arm64.override.yml)

case "${1:-stop}" in
  stop)
    docker compose "${FILES[@]}" stop
    ;;
  down)
    docker compose "${FILES[@]}" down
    ;;
  *)
    echo "Usage: $0 [stop|down]" >&2
    exit 2
    ;;
esac
