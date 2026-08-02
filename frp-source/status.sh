#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

GITLAB_LOCAL_HOST="${GITLAB_LOCAL_HOST:-127.0.0.1}"
GITLAB_WEB_PORT="${GITLAB_WEB_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"

systemctl --no-pager --full status frp-source.service || true
curl -fsS "http://${GITLAB_LOCAL_HOST}:${GITLAB_WEB_PORT}/-/health" || true
nc -z "$GITLAB_LOCAL_HOST" "$GITLAB_SSH_PORT" || true

echo "GitLab Web: ${GITLAB_LOCAL_HOST}:${GITLAB_WEB_PORT}"
echo "GitLab SSH: ${GITLAB_LOCAL_HOST}:${GITLAB_SSH_PORT}"
