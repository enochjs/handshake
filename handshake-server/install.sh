#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
_env_HANDSHAKE_SOURCE_PUBLIC_KEY="${HANDSHAKE_SOURCE_PUBLIC_KEY-}"
_env_HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE="${HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE-}"
_env_HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS="${HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS-}"
_has_HANDSHAKE_SOURCE_PUBLIC_KEY="${HANDSHAKE_SOURCE_PUBLIC_KEY+x}"
_has_HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE="${HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE+x}"
_has_HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS="${HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS+x}"

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

[[ -n "$_has_HANDSHAKE_SOURCE_PUBLIC_KEY" ]] && HANDSHAKE_SOURCE_PUBLIC_KEY="$_env_HANDSHAKE_SOURCE_PUBLIC_KEY"
[[ -n "$_has_HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE" ]] && HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE="$_env_HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE"
[[ -n "$_has_HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS" ]] && HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS="$_env_HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS"

HANDSHAKE_JUMP_USER="${HANDSHAKE_JUMP_USER:-gitproxy}"
HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
HANDSHAKE_AUTHORIZED_KEYS="${HANDSHAKE_AUTHORIZED_KEYS:-/home/${HANDSHAKE_JUMP_USER}/.ssh/authorized_keys}"
HANDSHAKE_SERVER_BIND="${HANDSHAKE_SERVER_BIND:-127.0.0.1}"
HANDSHAKE_KEY_SERVER_PORT="${HANDSHAKE_KEY_SERVER_PORT:-8787}"
HANDSHAKE_SOURCE_PUBLIC_KEY="${HANDSHAKE_SOURCE_PUBLIC_KEY:-}"
HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE="${HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE:-}"
HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS="${HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS:-restrict,port-forwarding,permitlisten=\"127.0.0.1:12222\",permitlisten=\"127.0.0.1:18080\"}"

append_source_tunnel_key() {
  local raw_key="$1"
  local key_type
  local key_body
  local source_key
  local entry

  read -r key_type key_body _ <<<"$raw_key"
  if [[ -z "${key_type:-}" || -z "${key_body:-}" || "$key_type" != ssh-* ]]; then
    echo "Error: source public key must look like: ssh-ed25519 AAAA... source-host" >&2
    exit 1
  fi

  source_key="${key_type} ${key_body}"
  entry="${HANDSHAKE_SOURCE_AUTHORIZED_KEYS_OPTIONS} ${source_key} source-tunnel"

  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    printf "grep -qF '%s' '%s' || echo '%s' | sudo tee -a '%s'\n" \
      "$source_key" \
      "$HANDSHAKE_AUTHORIZED_KEYS" \
      "$entry" \
      "$HANDSHAKE_AUTHORIZED_KEYS"
  elif ! sudo grep -qF "$source_key" "$HANDSHAKE_AUTHORIZED_KEYS"; then
    printf '%s\n' "$entry" | sudo tee -a "$HANDSHAKE_AUTHORIZED_KEYS" >/dev/null
  fi
}

install_source_tunnel_keys() {
  local installed=0
  local raw_key

  if [[ -n "$HANDSHAKE_SOURCE_PUBLIC_KEY" ]]; then
    append_source_tunnel_key "$HANDSHAKE_SOURCE_PUBLIC_KEY"
    installed=1
  fi

  if [[ -n "$HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE" ]]; then
    if [[ ! -f "$HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE" ]]; then
      echo "Error: HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE does not exist: $HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE" >&2
      exit 1
    fi

    while IFS= read -r raw_key || [[ -n "$raw_key" ]]; do
      [[ -n "$raw_key" ]] || continue
      [[ "$raw_key" == \#* ]] && continue
      append_source_tunnel_key "$raw_key"
      installed=1
    done <"$HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE"
  fi

  if [[ "$installed" -eq 0 ]]; then
    echo "Source tunnel key: not configured"
    echo "  Add HANDSHAKE_SOURCE_PUBLIC_KEY='<source host public key>' to handshake-server/.env, or"
    echo "  add HANDSHAKE_SOURCE_PUBLIC_KEYS_FILE='/path/to/source-public-keys' with one key per line, then rerun ./install.sh"
  fi
}

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
install_source_tunnel_keys

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
