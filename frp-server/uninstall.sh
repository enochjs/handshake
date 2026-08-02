#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-./generated/frps.toml}"
FRP_REMOVE_CONFIG="${FRP_REMOVE_CONFIG:-0}"

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

run docker compose down --remove-orphans

if [[ "$FRP_REMOVE_CONFIG" == "1" || "$FRP_REMOVE_CONFIG" == "true" ]]; then
  run rm -f "$FRP_CONFIG_PATH" .env
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd rmdir "$(dirname "$FRP_CONFIG_PATH")"
  else
    rmdir "$(dirname "$FRP_CONFIG_PATH")" 2>/dev/null || true
  fi
fi

echo "frp-server uninstalled"
