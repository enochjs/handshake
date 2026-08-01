#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
_env_DRY_RUN="${DRY_RUN-}"
_env_HANDSHAKE_KEY_SERVER_URL="${HANDSHAKE_KEY_SERVER_URL-}"
_env_HANDSHAKE_KEY_SERVER_TUNNEL="${HANDSHAKE_KEY_SERVER_TUNNEL-}"
_env_HANDSHAKE_KEY_SERVER_TUNNEL_HOST="${HANDSHAKE_KEY_SERVER_TUNNEL_HOST-}"
_env_HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT="${HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT-}"
_env_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST="${HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST-}"
_env_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT="${HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT-}"
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
_has_HANDSHAKE_KEY_SERVER_TUNNEL="${HANDSHAKE_KEY_SERVER_TUNNEL+x}"
_has_HANDSHAKE_KEY_SERVER_TUNNEL_HOST="${HANDSHAKE_KEY_SERVER_TUNNEL_HOST+x}"
_has_HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT="${HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT+x}"
_has_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST="${HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST+x}"
_has_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT="${HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT+x}"
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

is_dry_run() {
  [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]
}

is_enabled() {
  [[ "${1:-}" == "1" || "${1:-}" == "true" || "${1:-}" == "yes" ]]
}

is_disabled() {
  [[ "${1:-}" == "0" || "${1:-}" == "false" || "${1:-}" == "no" ]]
}

run() {
  if is_dry_run; then
    print_cmd "$@"
  else
    "$@"
  fi
}

require_ssh_config_line() {
  local output="$1"
  local expected="$2"
  if [[ $'\n'"$output"$'\n' != *$'\n'"$expected"$'\n'* ]]; then
    echo "SSH config check failed: expected '$expected' for gitlab-via-handshake" >&2
    return 1
  fi
}

cargo_bin_dir() {
  if [[ -n "${CARGO_INSTALL_ROOT:-}" ]]; then
    printf '%s/bin\n' "$CARGO_INSTALL_ROOT"
  elif [[ -n "${CARGO_HOME:-}" ]]; then
    printf '%s/bin\n' "$CARGO_HOME"
  else
    printf '%s/.cargo/bin\n' "$HOME"
  fi
}

verify_git_hs_on_path() {
  if is_dry_run; then
    return 0
  fi

  if ! command -v git-hs >/dev/null 2>&1; then
    echo "git-hs was installed, but it is not on PATH." >&2
    echo "Add this to your shell profile, then open a new terminal:" >&2
    echo "  export PATH=\"$(cargo_bin_dir):\$PATH\"" >&2
    return 1
  fi
}

KEY_SERVER_TUNNEL_PID=""

cleanup_key_server_tunnel() {
  if [[ -n "$KEY_SERVER_TUNNEL_PID" ]]; then
    kill "$KEY_SERVER_TUNNEL_PID" 2>/dev/null || true
    wait "$KEY_SERVER_TUNNEL_PID" 2>/dev/null || true
  fi
}

key_server_url_uses_localhost() {
  case "${HANDSHAKE_KEY_SERVER_URL:-}" in
    http://127.0.0.1:*|http://localhost:*|https://127.0.0.1:*|https://localhost:*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

should_start_key_server_tunnel() {
  if is_disabled "${HANDSHAKE_KEY_SERVER_TUNNEL:-}"; then
    return 1
  fi
  if is_enabled "${HANDSHAKE_KEY_SERVER_TUNNEL:-}"; then
    return 0
  fi
  key_server_url_uses_localhost
}

start_key_server_tunnel() {
  should_start_key_server_tunnel || return 0

  local tunnel_host="${HANDSHAKE_KEY_SERVER_TUNNEL_HOST:-handshake}"
  local local_port="${HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT:-18787}"
  local remote_host="${HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST:-127.0.0.1}"
  local remote_port="${HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT:-8787}"
  local forward="${local_port}:${remote_host}:${remote_port}"
  local health_url="http://127.0.0.1:${local_port}/healthz"

  if is_dry_run; then
    run ssh -o ExitOnForwardFailure=yes -N -L "$forward" "$tunnel_host"
    return 0
  fi

  if curl -fsS --connect-timeout 1 --max-time 2 "$health_url" >/dev/null 2>&1; then
    return 0
  fi

  ssh -o ExitOnForwardFailure=yes -N -L "$forward" "$tunnel_host" &
  KEY_SERVER_TUNNEL_PID="$!"
  trap cleanup_key_server_tunnel EXIT

  for _ in {1..30}; do
    if curl -fsS --connect-timeout 1 --max-time 2 "$health_url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "Key-server SSH tunnel did not become ready: ${health_url}" >&2
  return 1
}

verify_ssh_config() {
  if is_dry_run; then
    run ssh -G gitlab-via-handshake
    return 0
  fi

  local output
  if ! output="$(ssh -G gitlab-via-handshake 2>/dev/null)"; then
    echo "SSH config check failed: cannot read gitlab-via-handshake with ssh -G" >&2
    return 1
  fi

  require_ssh_config_line "$output" "hostname 127.0.0.1"
  require_ssh_config_line "$output" "port ${HANDSHAKE_GITLAB_REMOTE_SSH_PORT:-12222}"
  require_ssh_config_line "$output" "user git"
  require_ssh_config_line "$output" "proxyjump handshake-client-jump"
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
[[ -n "$_has_HANDSHAKE_KEY_SERVER_TUNNEL" ]] && HANDSHAKE_KEY_SERVER_TUNNEL="$_env_HANDSHAKE_KEY_SERVER_TUNNEL"
[[ -n "$_has_HANDSHAKE_KEY_SERVER_TUNNEL_HOST" ]] && HANDSHAKE_KEY_SERVER_TUNNEL_HOST="$_env_HANDSHAKE_KEY_SERVER_TUNNEL_HOST"
[[ -n "$_has_HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT" ]] && HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT="$_env_HANDSHAKE_KEY_SERVER_TUNNEL_LOCAL_PORT"
[[ -n "$_has_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST" ]] && HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST="$_env_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_HOST"
[[ -n "$_has_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT" ]] && HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT="$_env_HANDSHAKE_KEY_SERVER_TUNNEL_REMOTE_PORT"
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

start_key_server_tunnel

SETUP_SUCCEEDED=1
setup_output_file="$(mktemp)"
if run cargo run -- setup \
  --token "$HANDSHAKE_INVITE_TOKEN" \
  --server-url "${HANDSHAKE_KEY_SERVER_URL:-http://106.14.219.191:8787}" \
  --key "$PUBLIC_KEY_PATH" \
  --ssh-config "$SSH_CONFIG_PATH" \
  --include-path "$INCLUDE_PATH" \
  --handshake-host "${HANDSHAKE_HOST:-106.14.219.191}" \
  --handshake-user "${HANDSHAKE_USER:-gitproxy}" \
  --identity-file "${HANDSHAKE_IDENTITY_FILE:-~/.ssh/id_ed25519}" \
  --gitlab-local-port "${HANDSHAKE_GITLAB_REMOTE_SSH_PORT:-12222}" >"$setup_output_file" 2>&1; then
  cat "$setup_output_file"
  if grep -Fq "请联系 枫荷" "$setup_output_file"; then
    SETUP_SUCCEEDED=0
    echo "检测到 key 注册需要人工处理；本次跳过 SSH 配置连通性验证。" >&2
  fi
else
  setup_status=$?
  cat "$setup_output_file" >&2
  if grep -Fq "403" "$setup_output_file"; then
    SETUP_SUCCEEDED=0
    echo "邀请 token 校验失败（403），请联系 枫荷 处理。" >&2
    echo "将继续刷新 git-hs 命令；本次不会重新注册 key 或验证 SSH 配置。" >&2
  else
    rm -f "$setup_output_file"
    exit "$setup_status"
  fi
fi
rm -f "$setup_output_file"

run cargo install --path . --force
verify_git_hs_on_path
run git-hs status
if [[ "$SETUP_SUCCEEDED" == "1" ]]; then
  verify_ssh_config
  run ssh -T gitlab-via-handshake
fi
