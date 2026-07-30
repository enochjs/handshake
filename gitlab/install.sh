#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"

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

if [[ ! -f .env ]]; then
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    echo "Would create gitlab/.env from env.example"
    set -a
    source env.example
    set +a
  else
    cp env.example .env
    echo "Created gitlab/.env from env.example"
    echo "Review it now if this machine needs non-default ports."
  fi
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

GITLAB_HOST_IP="${GITLAB_HOST_IP:-10.10.0.216}"
GITLAB_HTTP_PORT="${GITLAB_HTTP_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"

if ! command -v docker >/dev/null 2>&1; then
  run sudo apt-get update
  run sudo apt-get install -y docker.io
  run sudo systemctl enable --now docker
fi

if ! docker compose version >/dev/null 2>&1; then
  run sudo apt-get install -y docker-compose-v2
fi

run mkdir -p config logs data backups
run docker compose up -d
run docker compose ps

echo "GitLab HTTP: http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}"
echo "GitLab SSH:  ssh://git@${GITLAB_HOST_IP}:${GITLAB_SSH_PORT}/<group>/<repo>.git"
echo "Status:      ./status.sh"
