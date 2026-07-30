#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

_env_HANDSHAKE_SERVER_HOST="${HANDSHAKE_SERVER_HOST-}"
_env_HANDSHAKE_SERVER_USER="${HANDSHAKE_SERVER_USER-}"
_env_SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE-}"
_env_SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL-}"
_env_SSH_SERVER_ALIVE_COUNT_MAX="${SSH_SERVER_ALIVE_COUNT_MAX-}"
_env_GITLAB_LOCAL_HTTP_PORT="${GITLAB_LOCAL_HTTP_PORT-}"
_env_GITLAB_LOCAL_SSH_PORT="${GITLAB_LOCAL_SSH_PORT-}"
_env_HANDSHAKE_REMOTE_GITLAB_HTTP_PORT="${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT-}"
_env_HANDSHAKE_REMOTE_GITLAB_SSH_PORT="${HANDSHAKE_REMOTE_GITLAB_SSH_PORT-}"
_env_DRY_RUN="${DRY_RUN-}"

_has_HANDSHAKE_SERVER_HOST="${HANDSHAKE_SERVER_HOST+x}"
_has_HANDSHAKE_SERVER_USER="${HANDSHAKE_SERVER_USER+x}"
_has_SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE+x}"
_has_SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL+x}"
_has_SSH_SERVER_ALIVE_COUNT_MAX="${SSH_SERVER_ALIVE_COUNT_MAX+x}"
_has_GITLAB_LOCAL_HTTP_PORT="${GITLAB_LOCAL_HTTP_PORT+x}"
_has_GITLAB_LOCAL_SSH_PORT="${GITLAB_LOCAL_SSH_PORT+x}"
_has_HANDSHAKE_REMOTE_GITLAB_HTTP_PORT="${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT+x}"
_has_HANDSHAKE_REMOTE_GITLAB_SSH_PORT="${HANDSHAKE_REMOTE_GITLAB_SSH_PORT+x}"
_has_DRY_RUN="${DRY_RUN+x}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
elif [[ -f env.example ]]; then
  set -a
  source env.example
  set +a
fi

[[ -n "$_has_HANDSHAKE_SERVER_HOST" ]] && HANDSHAKE_SERVER_HOST="$_env_HANDSHAKE_SERVER_HOST"
[[ -n "$_has_HANDSHAKE_SERVER_USER" ]] && HANDSHAKE_SERVER_USER="$_env_HANDSHAKE_SERVER_USER"
[[ -n "$_has_SSH_IDENTITY_FILE" ]] && SSH_IDENTITY_FILE="$_env_SSH_IDENTITY_FILE"
[[ -n "$_has_SSH_SERVER_ALIVE_INTERVAL" ]] && SSH_SERVER_ALIVE_INTERVAL="$_env_SSH_SERVER_ALIVE_INTERVAL"
[[ -n "$_has_SSH_SERVER_ALIVE_COUNT_MAX" ]] && SSH_SERVER_ALIVE_COUNT_MAX="$_env_SSH_SERVER_ALIVE_COUNT_MAX"
[[ -n "$_has_GITLAB_LOCAL_HTTP_PORT" ]] && GITLAB_LOCAL_HTTP_PORT="$_env_GITLAB_LOCAL_HTTP_PORT"
[[ -n "$_has_GITLAB_LOCAL_SSH_PORT" ]] && GITLAB_LOCAL_SSH_PORT="$_env_GITLAB_LOCAL_SSH_PORT"
[[ -n "$_has_HANDSHAKE_REMOTE_GITLAB_HTTP_PORT" ]] && HANDSHAKE_REMOTE_GITLAB_HTTP_PORT="$_env_HANDSHAKE_REMOTE_GITLAB_HTTP_PORT"
[[ -n "$_has_HANDSHAKE_REMOTE_GITLAB_SSH_PORT" ]] && HANDSHAKE_REMOTE_GITLAB_SSH_PORT="$_env_HANDSHAKE_REMOTE_GITLAB_SSH_PORT"
[[ -n "$_has_DRY_RUN" ]] && DRY_RUN="$_env_DRY_RUN"

HANDSHAKE_SERVER_HOST="${HANDSHAKE_SERVER_HOST:-}"
HANDSHAKE_SERVER_USER="${HANDSHAKE_SERVER_USER:-root}"
SSH_IDENTITY_FILE="${SSH_IDENTITY_FILE:-}"
SSH_SERVER_ALIVE_INTERVAL="${SSH_SERVER_ALIVE_INTERVAL:-30}"
SSH_SERVER_ALIVE_COUNT_MAX="${SSH_SERVER_ALIVE_COUNT_MAX:-3}"
GITLAB_LOCAL_HTTP_PORT="${GITLAB_LOCAL_HTTP_PORT:-8929}"
GITLAB_LOCAL_SSH_PORT="${GITLAB_LOCAL_SSH_PORT:-2222}"
HANDSHAKE_REMOTE_GITLAB_HTTP_PORT="${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT:-18080}"
HANDSHAKE_REMOTE_GITLAB_SSH_PORT="${HANDSHAKE_REMOTE_GITLAB_SSH_PORT:-12222}"
DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat <<'EOF'
Usage:
  ./tunnel.sh tunnel
  ./tunnel.sh check
  ./tunnel.sh help

The tunnel command publishes local GitLab ports to Aliyun loopback:
  127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT} -> 127.0.0.1:${GITLAB_LOCAL_HTTP_PORT}
  127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_SSH_PORT}  -> 127.0.0.1:${GITLAB_LOCAL_SSH_PORT}
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

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

ssh_target() {
  [[ -n "$HANDSHAKE_SERVER_HOST" ]] || die "HANDSHAKE_SERVER_HOST is required"
  printf '%s@%s' "$HANDSHAKE_SERVER_USER" "$HANDSHAKE_SERVER_HOST"
}

cmd_tunnel() {
  local target
  local -a args

  target="$(ssh_target)"
  args=(
    -o "ServerAliveInterval=$SSH_SERVER_ALIVE_INTERVAL"
    -o "ServerAliveCountMax=$SSH_SERVER_ALIVE_COUNT_MAX"
    -o "ExitOnForwardFailure=yes"
  )
  if [[ -n "$SSH_IDENTITY_FILE" ]]; then
    args+=(-i "$SSH_IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi

  run ssh -N \
    "${args[@]}" \
    -R "127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_HTTP_PORT}:127.0.0.1:${GITLAB_LOCAL_HTTP_PORT}" \
    -R "127.0.0.1:${HANDSHAKE_REMOTE_GITLAB_SSH_PORT}:127.0.0.1:${GITLAB_LOCAL_SSH_PORT}" \
    "$target"
}

cmd_check() {
  local target
  local -a args

  target="$(ssh_target)"
  args=(
    -o "ServerAliveInterval=$SSH_SERVER_ALIVE_INTERVAL"
    -o "ServerAliveCountMax=$SSH_SERVER_ALIVE_COUNT_MAX"
    -o "ExitOnForwardFailure=yes"
  )
  if [[ -n "$SSH_IDENTITY_FILE" ]]; then
    args+=(-i "$SSH_IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi

  run ssh \
    "${args[@]}" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    "$target" \
    "true"
}

case "${1:-help}" in
  tunnel)
    cmd_tunnel
    ;;
  check)
    cmd_check
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    die "Unknown command: ${1:-}"
    ;;
esac
