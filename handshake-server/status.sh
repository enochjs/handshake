#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

HANDSHAKE_SERVER_BIND="${HANDSHAKE_SERVER_BIND:-127.0.0.1}"
HANDSHAKE_KEY_SERVER_PORT="${HANDSHAKE_KEY_SERVER_PORT:-8787}"
HANDSHAKE_JUMP_USER="${HANDSHAKE_JUMP_USER:-gitproxy}"
HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
HANDSHAKE_AUTHORIZED_KEYS="${HANDSHAKE_AUTHORIZED_KEYS:-/home/${HANDSHAKE_JUMP_USER}/.ssh/authorized_keys}"

systemctl --no-pager --full status handshake-add-key.service || true
curl -fsS "http://${HANDSHAKE_SERVER_BIND}:${HANDSHAKE_KEY_SERVER_PORT}/healthz"
id "$HANDSHAKE_JUMP_USER"
getent passwd "$HANDSHAKE_JUMP_USER"
sudo test -d "/home/${HANDSHAKE_JUMP_USER}/.ssh"
sudo test -f "$HANDSHAKE_TOKEN_FILE"
sudo test -f "$HANDSHAKE_AUTHORIZED_KEYS"

echo "Jump user: ${HANDSHAKE_JUMP_USER}"
echo "Token file: ${HANDSHAKE_TOKEN_FILE}"
echo "Authorized keys: ${HANDSHAKE_AUTHORIZED_KEYS}"
