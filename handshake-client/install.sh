#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
_env_DRY_RUN="${DRY_RUN-}"
_env_HANDSHAKE_KEY_SERVER_URL="${HANDSHAKE_KEY_SERVER_URL-}"
_env_HANDSHAKE_INVITE_TOKEN="${HANDSHAKE_INVITE_TOKEN-}"
_env_HANDSHAKE_PUBLIC_KEY_PATH="${HANDSHAKE_PUBLIC_KEY_PATH-}"
_env_HANDSHAKE_SSH_CONFIG_PATH="${HANDSHAKE_SSH_CONFIG_PATH-}"
_env_HANDSHAKE_INCLUDE_PATH="${HANDSHAKE_INCLUDE_PATH-}"
_env_HANDSHAKE_HOST="${HANDSHAKE_HOST-}"
_env_HANDSHAKE_USER="${HANDSHAKE_USER-}"
_env_HANDSHAKE_IDENTITY_FILE="${HANDSHAKE_IDENTITY_FILE-}"
_env_HANDSHAKE_GITLAB_REMOTE_SSH_PORT="${HANDSHAKE_GITLAB_REMOTE_SSH_PORT-}"

_has_DRY_RUN="${DRY_RUN+x}"
_has_HANDSHAKE_KEY_SERVER_URL="${HANDSHAKE_KEY_SERVER_URL+x}"
_has_HANDSHAKE_INVITE_TOKEN="${HANDSHAKE_INVITE_TOKEN+x}"
_has_HANDSHAKE_PUBLIC_KEY_PATH="${HANDSHAKE_PUBLIC_KEY_PATH+x}"
_has_HANDSHAKE_SSH_CONFIG_PATH="${HANDSHAKE_SSH_CONFIG_PATH+x}"
_has_HANDSHAKE_INCLUDE_PATH="${HANDSHAKE_INCLUDE_PATH+x}"
_has_HANDSHAKE_HOST="${HANDSHAKE_HOST+x}"
_has_HANDSHAKE_USER="${HANDSHAKE_USER+x}"
_has_HANDSHAKE_IDENTITY_FILE="${HANDSHAKE_IDENTITY_FILE+x}"
_has_HANDSHAKE_GITLAB_REMOTE_SSH_PORT="${HANDSHAKE_GITLAB_REMOTE_SSH_PORT+x}"

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

expand_path() {
  local value="$1"
  case "$value" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${value#"~/"}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

if [[ ! -f .env ]]; then
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    echo "Would create handshake-client/.env from env.example"
    set -a
    source env.example
    set +a
  else
    cp env.example .env
    echo "Created handshake-client/.env from env.example"
    echo "Set HANDSHAKE_INVITE_TOKEN in handshake-client/.env, then rerun ./install.sh"
    exit 1
  fi
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

[[ -n "$_has_DRY_RUN" ]] && DRY_RUN="$_env_DRY_RUN"
[[ -n "$_has_HANDSHAKE_KEY_SERVER_URL" ]] && HANDSHAKE_KEY_SERVER_URL="$_env_HANDSHAKE_KEY_SERVER_URL"
[[ -n "$_has_HANDSHAKE_INVITE_TOKEN" ]] && HANDSHAKE_INVITE_TOKEN="$_env_HANDSHAKE_INVITE_TOKEN"
[[ -n "$_has_HANDSHAKE_PUBLIC_KEY_PATH" ]] && HANDSHAKE_PUBLIC_KEY_PATH="$_env_HANDSHAKE_PUBLIC_KEY_PATH"
[[ -n "$_has_HANDSHAKE_SSH_CONFIG_PATH" ]] && HANDSHAKE_SSH_CONFIG_PATH="$_env_HANDSHAKE_SSH_CONFIG_PATH"
[[ -n "$_has_HANDSHAKE_INCLUDE_PATH" ]] && HANDSHAKE_INCLUDE_PATH="$_env_HANDSHAKE_INCLUDE_PATH"
[[ -n "$_has_HANDSHAKE_HOST" ]] && HANDSHAKE_HOST="$_env_HANDSHAKE_HOST"
[[ -n "$_has_HANDSHAKE_USER" ]] && HANDSHAKE_USER="$_env_HANDSHAKE_USER"
[[ -n "$_has_HANDSHAKE_IDENTITY_FILE" ]] && HANDSHAKE_IDENTITY_FILE="$_env_HANDSHAKE_IDENTITY_FILE"
[[ -n "$_has_HANDSHAKE_GITLAB_REMOTE_SSH_PORT" ]] && HANDSHAKE_GITLAB_REMOTE_SSH_PORT="$_env_HANDSHAKE_GITLAB_REMOTE_SSH_PORT"

HANDSHAKE_INVITE_TOKEN="${HANDSHAKE_INVITE_TOKEN:-}"
[[ -n "$HANDSHAKE_INVITE_TOKEN" ]] || { echo "HANDSHAKE_INVITE_TOKEN is required in handshake-client/.env"; exit 1; }

PUBLIC_KEY_PATH="$(expand_path "${HANDSHAKE_PUBLIC_KEY_PATH:-~/.ssh/id_ed25519.pub}")"
SSH_CONFIG_PATH="$(expand_path "${HANDSHAKE_SSH_CONFIG_PATH:-~/.ssh/config}")"
INCLUDE_PATH="$(expand_path "${HANDSHAKE_INCLUDE_PATH:-~/.ssh/handshake_config}")"

run cargo run -- setup \
  --token "$HANDSHAKE_INVITE_TOKEN" \
  --server-url "${HANDSHAKE_KEY_SERVER_URL:-http://106.14.219.191:8787}" \
  --key "$PUBLIC_KEY_PATH" \
  --ssh-config "$SSH_CONFIG_PATH" \
  --include-path "$INCLUDE_PATH" \
  --handshake-host "${HANDSHAKE_HOST:-106.14.219.191}" \
  --handshake-user "${HANDSHAKE_USER:-gitproxy}" \
  --identity-file "${HANDSHAKE_IDENTITY_FILE:-~/.ssh/id_ed25519}" \
  --gitlab-local-port "${HANDSHAKE_GITLAB_REMOTE_SSH_PORT:-12222}"

run cargo run -- status
run ssh -T gitlab-via-handshake
