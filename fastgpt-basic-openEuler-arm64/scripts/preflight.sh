#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

need_file() {
  [ -f "$1" ] || fail "missing required file: $1"
}

need_file docker-compose.upstream.yml
need_file docker-compose.arm64.override.yml
need_file config.json

ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] || fail "this package is restricted to aarch64; current arch is $ARCH"

CPU_INFO="$(
  {
    command -v lscpu >/dev/null 2>&1 && lscpu
    cat /proc/cpuinfo 2>/dev/null
  } 2>/dev/null || true
)"
echo "$CPU_INFO" | grep -qi 'Kunpeng-920' || fail "this package is restricted to Kunpeng-920 CPU"

if [ -r /etc/os-release ]; then
  . /etc/os-release
  [ "${ID:-}" = "openEuler" ] || fail "expected openEuler, got ID=${ID:-unknown}"
  [ "${VERSION_ID:-}" = "22.03" ] || fail "expected openEuler VERSION_ID=22.03, got ${VERSION_ID:-unknown}"
else
  fail "/etc/os-release is not readable"
fi

if grep -qaE '/docker/|/kubepods/' /proc/1/cgroup 2>/dev/null; then
  if [ ! -S /var/run/docker.sock ]; then
    if ! unshare -Ur true >/dev/null 2>&1; then
      cat >&2 <<'EOF'
ERROR: current SSH target is already inside an unprivileged container.
Docker socket is not mounted and user namespaces are blocked, so Docker/Podman
Compose cannot run safely here.

Use a host-level shell with Docker Engine access, or mount a valid Docker socket
into this environment before starting FastGPT.
EOF
      exit 20
    fi
  fi
fi

command -v docker >/dev/null 2>&1 || fail "docker CLI is not installed"
docker info >/dev/null 2>&1 || fail "docker daemon is not reachable"
docker compose version >/dev/null 2>&1 || fail "docker compose plugin is not available"

COMPOSE_VER="$(docker compose version --short 2>/dev/null | sed 's/^v//')"
python3 - "$COMPOSE_VER" <<'PY'
import sys
from itertools import zip_longest

version = sys.argv[1]
need = "2.24.4"

def parts(v):
    out = []
    for x in v.split("."):
        try:
            out.append(int("".join(ch for ch in x if ch.isdigit()) or "0"))
        except ValueError:
            out.append(0)
    return out

current = list(zip_longest(parts(version), parts(need), fillvalue=0))
if [a for a, _ in current] < [b for _, b in current]:
    print(f"ERROR: docker compose >= {need} is required, got {version}", file=sys.stderr)
    print("This package uses the Compose !override tag to replace upstream port bindings.", file=sys.stderr)
    sys.exit(1)
PY

if [ ! -f .env ]; then
  bash ./scripts/init-env.sh
fi

set -a
. ./.env
set +a

python3 - <<PY
import os
import socket
import sys

ports = [
    ("FASTGPT_BIND_ADDR", os.getenv("FASTGPT_BIND_ADDR", "127.0.0.1"), "FASTGPT_PORT", int(os.getenv("FASTGPT_PORT", "13000"))),
    ("MCP_BIND_ADDR", os.getenv("MCP_BIND_ADDR", "127.0.0.1"), "MCP_PORT", int(os.getenv("MCP_PORT", "13003"))),
    ("MINIO_BIND_ADDR", os.getenv("MINIO_BIND_ADDR", "127.0.0.1"), "MINIO_API_PORT", int(os.getenv("MINIO_API_PORT", "19000"))),
    ("MINIO_BIND_ADDR", os.getenv("MINIO_BIND_ADDR", "127.0.0.1"), "MINIO_CONSOLE_PORT", int(os.getenv("MINIO_CONSOLE_PORT", "19001"))),
]
busy = []
for bind_name, bind_addr, port_name, port in ports:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind((bind_addr, port))
    except OSError as exc:
        busy.append(f"{bind_name}={bind_addr} {port_name}={port}: {exc}")
    finally:
        s.close()

if busy:
    print("ERROR: bind address or port conflicts detected:", file=sys.stderr)
    for item in busy:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(1)
PY

if command -v curl >/dev/null 2>&1; then
  infer_base="${FASTGPT_INFER_BASE_URL:-http://172.16.2.198:8010/v1}"
  if curl -fsS --max-time 3 "${infer_base%/}/models" >/dev/null 2>&1; then
    echo "Inference API is reachable: ${infer_base}"
  else
    warn "inference API is not reachable at ${infer_base}"
  fi
fi

docker compose -f docker-compose.upstream.yml -f docker-compose.arm64.override.yml config >/dev/null
echo "Preflight passed."
