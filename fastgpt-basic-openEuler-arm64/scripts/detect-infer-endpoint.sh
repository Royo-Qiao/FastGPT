#!/usr/bin/env bash
set -euo pipefail

port="${1:-8010}"
loopback="http://127.0.0.1:${port}/v1"

container_ip="$(
  python3 - <<'PY' 2>/dev/null || true
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    s.connect(("8.8.8.8", 80))
    print(s.getsockname()[0])
finally:
    s.close()
PY
)"

if [ -z "$container_ip" ] && [ -r /etc/hosts ]; then
  container_ip="$(awk 'NF >= 2 && $1 !~ /^127\./ && $1 !~ /^::1/ {print $1; exit}' /etc/hosts)"
fi

echo "FastGPT inference endpoint notes"
echo "  from this SSH container: $loopback"

if [ -n "$container_ip" ]; then
  echo "  from host Docker containers, try: http://${container_ip}:${port}/v1"
else
  echo "  from host Docker containers: unable to detect this container IP"
fi

if command -v curl >/dev/null 2>&1; then
  echo
  echo "Checking $loopback/models"
  curl -fsS --max-time 3 "$loopback/models" || true
  echo
fi
