#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

GITLAB_CONTAINER="${GITLAB_CONTAINER:-gitlab}"
GITLAB_HOST_IP="${GITLAB_HOST_IP:-10.10.0.216}"
GITLAB_HTTP_PORT="${GITLAB_HTTP_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"

docker compose ps
docker exec "$GITLAB_CONTAINER" gitlab-ctl status
curl -fsS "http://127.0.0.1:${GITLAB_HTTP_PORT}/-/health" || true

echo "Configured HTTP URL: http://${GITLAB_HOST_IP}:${GITLAB_HTTP_PORT}"
echo "Configured SSH port: ${GITLAB_SSH_PORT}"
