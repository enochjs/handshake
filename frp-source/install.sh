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
  echo "Created frp-source/.env; fill it and rerun."
  exit 1
fi

FRP_VERSION="${FRP_VERSION:-0.68.0}"
FRP_IMAGE="${FRP_IMAGE:-fatedier/frpc:v${FRP_VERSION}}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_SECRET_KEY="${FRP_SECRET_KEY:-}"
GITLAB_LOCAL_HOST="${GITLAB_LOCAL_HOST:-127.0.0.1}"
GITLAB_WEB_PORT="${GITLAB_WEB_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-./generated/frpc-source.toml}"

[[ -n "$FRP_SERVER_ADDR" ]] || { echo "FRP_SERVER_ADDR is required"; exit 1; }
[[ -n "$FRP_AUTH_TOKEN" ]] || { echo "FRP_AUTH_TOKEN is required"; exit 1; }
[[ -n "$FRP_SECRET_KEY" ]] || { echo "FRP_SECRET_KEY is required"; exit 1; }

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
    -e "s|\${FRP_SERVER_ADDR}|${FRP_SERVER_ADDR}|g" \
    -e "s|\${FRP_SERVER_PORT}|${FRP_SERVER_PORT}|g" \
    -e "s|\${FRP_AUTH_TOKEN}|${FRP_AUTH_TOKEN}|g" \
    -e "s|\${FRP_SECRET_KEY}|${FRP_SECRET_KEY}|g" \
    -e "s|\${GITLAB_LOCAL_HOST}|${GITLAB_LOCAL_HOST}|g" \
    -e "s|\${GITLAB_WEB_PORT}|${GITLAB_WEB_PORT}|g" \
    -e "s|\${GITLAB_SSH_PORT}|${GITLAB_SSH_PORT}|g" \
    frpc.toml.template
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

echo "frp source config: ${FRP_CONFIG_PATH}"
echo "frp source image: ${FRP_IMAGE}"
echo "GitLab Web: ${GITLAB_LOCAL_HOST}:${GITLAB_WEB_PORT}"
echo "GitLab SSH: ${GITLAB_LOCAL_HOST}:${GITLAB_SSH_PORT}"
