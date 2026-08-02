#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
elif [[ "$DRY_RUN" != "1" && "$DRY_RUN" != "true" ]]; then
  cp env.example .env
  echo "Created frp-server/.env; set FRP_AUTH_TOKEN and rerun."
  exit 1
fi

FRP_VERSION="${FRP_VERSION:-0.68.0}"
FRP_IMAGE="${FRP_IMAGE:-fatedier/frps:v${FRP_VERSION}}"
FRP_SERVER_BIND_ADDR="${FRP_SERVER_BIND_ADDR:-0.0.0.0}"
FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-./generated/frps.toml}"
FRP_LOG_LEVEL="${FRP_LOG_LEVEL:-info}"
FRP_LOG_MAX_DAYS="${FRP_LOG_MAX_DAYS:-7}"

[[ -n "$FRP_AUTH_TOKEN" ]] || { echo "FRP_AUTH_TOKEN is required"; exit 1; }

print_cmd() {
  local first=1
  local arg
  for arg in "$@"; do
    [[ "$first" -eq 1 ]] || printf ' '
    printf '%q' "$arg"
    first=0
  done
  printf '\n'
}

run() {
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd "$@"
  else
    "$@"
  fi
}

render_config() {
  sed \
    -e "s|\${FRP_SERVER_BIND_ADDR}|${FRP_SERVER_BIND_ADDR}|g" \
    -e "s|\${FRP_BIND_PORT}|${FRP_BIND_PORT}|g" \
    -e "s|\${FRP_AUTH_TOKEN}|${FRP_AUTH_TOKEN}|g" \
    -e "s|\${FRP_LOG_LEVEL}|${FRP_LOG_LEVEL}|g" \
    -e "s|\${FRP_LOG_MAX_DAYS}|${FRP_LOG_MAX_DAYS}|g" \
    frps.toml.template
}

if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Using image ${FRP_IMAGE}"
fi

run mkdir -p "$(dirname "$FRP_CONFIG_PATH")"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Would render $FRP_CONFIG_PATH"
  render_config
else
  render_config >"$FRP_CONFIG_PATH"
  chmod 600 "$FRP_CONFIG_PATH"
fi

run docker compose up -d
run docker compose ps

echo "frps config: ${FRP_CONFIG_PATH}"
echo "frps image: ${FRP_IMAGE}"
echo "frps bind: ${FRP_SERVER_BIND_ADDR}:${FRP_BIND_PORT}"
