#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLE="${ROLE:-${1:-}}"
DRY_RUN="${DRY_RUN:-0}"
DESTROY_CONFIRM="${DESTROY_CONFIRM:-}"
CONFIRM_VALUE="delete-handshake"

usage() {
  cat <<EOF
Usage:
  ROLE=gitlab DESTROY_CONFIRM=${CONFIRM_VALUE} ./scripts/destroy.sh
  ROLE=server DESTROY_CONFIRM=${CONFIRM_VALUE} ./scripts/destroy.sh
  ROLE=source DESTROY_CONFIRM=${CONFIRM_VALUE} ./scripts/destroy.sh
  ROLE=client DESTROY_CONFIRM=${CONFIRM_VALUE} ./scripts/destroy.sh
  ROLE=all DESTROY_CONFIRM=${CONFIRM_VALUE} ./scripts/destroy.sh

This is destructive. It removes services, runtime config, generated data,
the Aliyun gitproxy user for ROLE=server, and GitLab data for ROLE=gitlab.

Use DRY_RUN=1 to print commands without executing them.
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

run_shell() {
  local command="$1"
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    printf '%s\n' "$command"
  else
    bash -c "$command"
  fi
}

source_env() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    set -a
    source "$env_file"
    set +a
  fi
}

require_confirmation() {
  [[ -n "$ROLE" ]] || { usage >&2; die "ROLE is required"; }
  case "$ROLE" in
    gitlab|server|source|client|all) ;;
    *) usage >&2; die "unknown ROLE: $ROLE" ;;
  esac

  if [[ "$DESTROY_CONFIRM" != "$CONFIRM_VALUE" ]]; then
    usage >&2
    die "set DESTROY_CONFIRM=${CONFIRM_VALUE} to run the full delete script"
  fi
}

destroy_gitlab() {
  cd "$ROOT_DIR"
  source_env gitlab/.env

  run docker compose -f gitlab/docker-compose.yml down --volumes --remove-orphans
  run_shell "rm -rf gitlab/config gitlab/logs gitlab/data gitlab/backups gitlab/.env"
}

destroy_server() {
  cd "$ROOT_DIR/handshake-server"
  source_env .env

  local jump_user="${HANDSHAKE_JUMP_USER:-gitproxy}"
  local token_file="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
  local token_dir
  token_dir="$(dirname "$token_file")"

  run_shell "sudo systemctl disable --now handshake-add-key.service || true"
  run sudo rm -f /etc/systemd/system/handshake-add-key.service
  run sudo systemctl daemon-reload
  run sudo rm -rf /etc/handshake-server /opt/handshake "$token_file"
  if [[ "$token_dir" == "/etc/handshake-client" ]]; then
    run sudo rm -rf "$token_dir"
  fi
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    run sudo userdel -r "$jump_user"
  elif id "$jump_user" >/dev/null 2>&1; then
    sudo userdel -r "$jump_user"
  fi
  run rm -f .env
}

destroy_source() {
  cd "$ROOT_DIR/handshake-source"

  run_shell "sudo systemctl disable --now handshake-source-tunnel.service || true"
  run sudo rm -f /etc/systemd/system/handshake-source-tunnel.service
  run sudo systemctl daemon-reload
  run rm -f .env
}

destroy_client() {
  cd "$ROOT_DIR/handshake-client"
  source_env .env

  local include_path="${HANDSHAKE_INCLUDE_PATH:-$HOME/.ssh/handshake_config}"
  case "$include_path" in
    "~") include_path="$HOME" ;;
    "~/"*) include_path="$HOME/${include_path#"~/"}" ;;
  esac

  run cargo run -- disable
  run rm -f "$include_path" .env
}

require_confirmation

case "$ROLE" in
  gitlab)
    destroy_gitlab
    ;;
  server)
    destroy_server
    ;;
  source)
    destroy_source
    ;;
  client)
    destroy_client
    ;;
  all)
    destroy_client
    destroy_source
    destroy_server
    destroy_gitlab
    ;;
esac

echo "Destroy complete for ROLE=${ROLE}"
