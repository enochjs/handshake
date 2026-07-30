#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

HANDSHAKE_SERVER_HOST="${HANDSHAKE_SERVER_HOST:-}"
GITLAB_LOCAL_HTTP_PORT="${GITLAB_LOCAL_HTTP_PORT:-8929}"
GITLAB_LOCAL_SSH_PORT="${GITLAB_LOCAL_SSH_PORT:-2222}"
HANDSHAKE_REMOTE_GITLAB_HTTP_PORT="${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT:-18080}"
HANDSHAKE_REMOTE_GITLAB_SSH_PORT="${HANDSHAKE_REMOTE_GITLAB_SSH_PORT:-12222}"

systemctl --no-pager --full status handshake-source-tunnel.service || true

echo "Local GitLab HTTP: 127.0.0.1:${GITLAB_LOCAL_HTTP_PORT}"
echo "Local GitLab SSH:  127.0.0.1:${GITLAB_LOCAL_SSH_PORT}"
echo "Aliyun host:        ${HANDSHAKE_SERVER_HOST:-unset}"
echo "Remote HTTP:        127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT}"
echo "Remote SSH:         127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_SSH_PORT}"
