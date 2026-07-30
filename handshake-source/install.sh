#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
SERVICE_NAME=handshake-source-tunnel.service
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

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
    echo "Would create handshake-source/.env from env.example"
    set -a
    source env.example
    set +a
  else
    cp env.example .env
    echo "Created handshake-source/.env from env.example"
  fi
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

HANDSHAKE_SERVER_HOST="${HANDSHAKE_SERVER_HOST:-}"
HANDSHAKE_SERVER_USER="${HANDSHAKE_SERVER_USER:-gitproxy}"

[[ -n "$HANDSHAKE_SERVER_HOST" ]] || { echo "HANDSHAKE_SERVER_HOST is required in handshake-source/.env"; exit 1; }

run sudo apt-get update
run sudo apt-get install -y openssh-client curl

if [[ "$DRY_RUN" != "1" && "$DRY_RUN" != "true" ]]; then
  ./tunnel.sh check
fi

if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  print_cmd sudo tee "$SERVICE_PATH"
else
  sudo tee "$SERVICE_PATH" >/dev/null <<EOF
[Unit]
Description=Handshake reverse SSH tunnel for internal GitLab
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$(id -un)
Group=$(id -gn)
WorkingDirectory=${SCRIPT_DIR}
EnvironmentFile=${SCRIPT_DIR}/.env
ExecStart=${SCRIPT_DIR}/tunnel.sh tunnel
Restart=always
RestartSec=5
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF
fi

run sudo systemctl daemon-reload
run sudo systemctl enable --now "$SERVICE_NAME"
run sudo systemctl --no-pager --full status "$SERVICE_NAME"

echo "Tunnel service: ${SERVICE_NAME}"
echo "Remote GitLab SSH: 127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_SSH_PORT:-12222} on ${HANDSHAKE_SERVER_HOST}"
