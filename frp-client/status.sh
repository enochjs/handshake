#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

GITLAB_LOCAL_NAME="${GITLAB_LOCAL_NAME:-gitlab.internal}"
GITLAB_WEB_BIND_PORT="${GITLAB_WEB_BIND_PORT:-8929}"
GITLAB_SSH_BIND_PORT="${GITLAB_SSH_BIND_PORT:-2222}"
FRP_GITLAB_SSH_PREFIX="${FRP_GITLAB_SSH_PREFIX:-ssh://git@gitlab.internal:2222/}"

grep -E "127\\.0\\.0\\.1[[:space:]].*\\b${GITLAB_LOCAL_NAME}\\b" /etc/hosts
curl -fsS "http://${GITLAB_LOCAL_NAME}:${GITLAB_WEB_BIND_PORT}/-/health" || true
ssh -o BatchMode=yes -o ConnectTimeout=10 -T -p "$GITLAB_SSH_BIND_PORT" "git@${GITLAB_LOCAL_NAME}" || true
git config --global --get-all "url.${FRP_GITLAB_SSH_PREFIX}.insteadOf" || true

echo "GitLab Web: http://${GITLAB_LOCAL_NAME}:${GITLAB_WEB_BIND_PORT}"
echo "GitLab SSH: ssh://git@${GITLAB_LOCAL_NAME}:${GITLAB_SSH_BIND_PORT}/<group>/<repo>.git"
