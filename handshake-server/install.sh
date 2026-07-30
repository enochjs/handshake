#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
    echo "Would create handshake-server/.env from env.example"
    set -a
    source env.example
    set +a
  else
    cp env.example .env
    echo "Created handshake-server/.env from env.example"
  fi
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

HANDSHAKE_JUMP_USER="${HANDSHAKE_JUMP_USER:-gitproxy}"
HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
HANDSHAKE_AUTHORIZED_KEYS="${HANDSHAKE_AUTHORIZED_KEYS:-/home/${HANDSHAKE_JUMP_USER}/.ssh/authorized_keys}"
HANDSHAKE_SERVER_BIND="${HANDSHAKE_SERVER_BIND:-127.0.0.1}"
HANDSHAKE_KEY_SERVER_PORT="${HANDSHAKE_KEY_SERVER_PORT:-8787}"

run sudo apt-get update
run sudo apt-get install -y python3 openssh-server curl rsync
run sudo systemctl enable --now ssh

if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  run sudo useradd --create-home --shell /bin/bash "$HANDSHAKE_JUMP_USER"
else
  if ! id "$HANDSHAKE_JUMP_USER" >/dev/null 2>&1; then
    sudo useradd --create-home --shell /bin/bash "$HANDSHAKE_JUMP_USER"
  fi
fi

run sudo passwd -l "$HANDSHAKE_JUMP_USER"
run sudo install -d -m 700 -o "$HANDSHAKE_JUMP_USER" -g "$HANDSHAKE_JUMP_USER" "/home/${HANDSHAKE_JUMP_USER}/.ssh"
run sudo touch "$HANDSHAKE_AUTHORIZED_KEYS"
run sudo chown "$HANDSHAKE_JUMP_USER:$HANDSHAKE_JUMP_USER" "$HANDSHAKE_AUTHORIZED_KEYS"
run sudo chmod 600 "$HANDSHAKE_AUTHORIZED_KEYS"

if [[ "$DRY_RUN" != "1" && "$DRY_RUN" != "true" ]]; then
  if sudo sshd -T | grep -qi '^allowtcpforwarding no'; then
    echo "Error: sshd has AllowTcpForwarding=no. Set AllowTcpForwarding yes in /etc/ssh/sshd_config."
    exit 1
  fi
fi

run sudo install -d -m 755 /opt/handshake
run sudo rsync -a --delete "$REPO_ROOT/" /opt/handshake/
run sudo install -d -m 755 /etc/handshake-server
run sudo install -d -m 700 "$(dirname "$HANDSHAKE_TOKEN_FILE")"
run sudo touch "$HANDSHAKE_TOKEN_FILE"
run sudo chmod 600 "$HANDSHAKE_TOKEN_FILE"
run sudo cp .env /etc/handshake-server/handshake-server.env
run sudo cp systemd/handshake-add-key.service /etc/systemd/system/handshake-add-key.service
run sudo systemctl daemon-reload
run sudo systemctl enable --now handshake-add-key.service

echo "Jump user: ${HANDSHAKE_JUMP_USER}"
echo "Add invite token:"
echo "  echo '<token>' | sudo tee -a ${HANDSHAKE_TOKEN_FILE}"
echo "Health:"
echo "  curl -fsS http://${HANDSHAKE_SERVER_BIND}:${HANDSHAKE_KEY_SERVER_PORT}/healthz"
