#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"

systemctl --no-pager --full status frps.service || true
ss -lntup | grep -E "(:${FRP_BIND_PORT})\\b" || true

echo "frps bind port: ${FRP_BIND_PORT}"
