#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_env_HSD_REMOTE_HOST="${HSD_REMOTE_HOST-}"
_env_HSD_REMOTE_USER="${HSD_REMOTE_USER-}"
_env_HSD_REMOTE_DIR="${HSD_REMOTE_DIR-}"
_env_HSD_SSH_IDENTITY_FILE="${HSD_SSH_IDENTITY_FILE-}"
_env_HSD_SSH_SERVER_ALIVE_INTERVAL="${HSD_SSH_SERVER_ALIVE_INTERVAL-}"
_env_HSD_SSH_SERVER_ALIVE_COUNT_MAX="${HSD_SSH_SERVER_ALIVE_COUNT_MAX-}"
_env_HSD_GITLAB_LOCAL_HTTP_PORT="${HSD_GITLAB_LOCAL_HTTP_PORT-}"
_env_HSD_GITLAB_LOCAL_SSH_PORT="${HSD_GITLAB_LOCAL_SSH_PORT-}"
_env_HSD_GITLAB_REMOTE_HTTP_PORT="${HSD_GITLAB_REMOTE_HTTP_PORT-}"
_env_HSD_GITLAB_REMOTE_SSH_PORT="${HSD_GITLAB_REMOTE_SSH_PORT-}"
_env_HSD_API_KEY="${HSD_API_KEY-}"
_env_HSD_NODE_URL="${HSD_NODE_URL-}"
_env_HSD_WALLET_URL="${HSD_WALLET_URL-}"
_env_HSD_LOCAL_NODE_PORT="${HSD_LOCAL_NODE_PORT-}"
_env_HSD_LOCAL_WALLET_PORT="${HSD_LOCAL_WALLET_PORT-}"
_env_HSD_DRY_RUN="${HSD_DRY_RUN-}"

_has_HSD_REMOTE_HOST="${HSD_REMOTE_HOST+x}"
_has_HSD_REMOTE_USER="${HSD_REMOTE_USER+x}"
_has_HSD_REMOTE_DIR="${HSD_REMOTE_DIR+x}"
_has_HSD_SSH_IDENTITY_FILE="${HSD_SSH_IDENTITY_FILE+x}"
_has_HSD_SSH_SERVER_ALIVE_INTERVAL="${HSD_SSH_SERVER_ALIVE_INTERVAL+x}"
_has_HSD_SSH_SERVER_ALIVE_COUNT_MAX="${HSD_SSH_SERVER_ALIVE_COUNT_MAX+x}"
_has_HSD_GITLAB_LOCAL_HTTP_PORT="${HSD_GITLAB_LOCAL_HTTP_PORT+x}"
_has_HSD_GITLAB_LOCAL_SSH_PORT="${HSD_GITLAB_LOCAL_SSH_PORT+x}"
_has_HSD_GITLAB_REMOTE_HTTP_PORT="${HSD_GITLAB_REMOTE_HTTP_PORT+x}"
_has_HSD_GITLAB_REMOTE_SSH_PORT="${HSD_GITLAB_REMOTE_SSH_PORT+x}"
_has_HSD_API_KEY="${HSD_API_KEY+x}"
_has_HSD_NODE_URL="${HSD_NODE_URL+x}"
_has_HSD_WALLET_URL="${HSD_WALLET_URL+x}"
_has_HSD_LOCAL_NODE_PORT="${HSD_LOCAL_NODE_PORT+x}"
_has_HSD_LOCAL_WALLET_PORT="${HSD_LOCAL_WALLET_PORT+x}"
_has_HSD_DRY_RUN="${HSD_DRY_RUN+x}"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/.env"
  set +a
fi

[[ -n "$_has_HSD_REMOTE_HOST" ]] && HSD_REMOTE_HOST="$_env_HSD_REMOTE_HOST"
[[ -n "$_has_HSD_REMOTE_USER" ]] && HSD_REMOTE_USER="$_env_HSD_REMOTE_USER"
[[ -n "$_has_HSD_REMOTE_DIR" ]] && HSD_REMOTE_DIR="$_env_HSD_REMOTE_DIR"
[[ -n "$_has_HSD_SSH_IDENTITY_FILE" ]] && HSD_SSH_IDENTITY_FILE="$_env_HSD_SSH_IDENTITY_FILE"
[[ -n "$_has_HSD_SSH_SERVER_ALIVE_INTERVAL" ]] && HSD_SSH_SERVER_ALIVE_INTERVAL="$_env_HSD_SSH_SERVER_ALIVE_INTERVAL"
[[ -n "$_has_HSD_SSH_SERVER_ALIVE_COUNT_MAX" ]] && HSD_SSH_SERVER_ALIVE_COUNT_MAX="$_env_HSD_SSH_SERVER_ALIVE_COUNT_MAX"
[[ -n "$_has_HSD_GITLAB_LOCAL_HTTP_PORT" ]] && HSD_GITLAB_LOCAL_HTTP_PORT="$_env_HSD_GITLAB_LOCAL_HTTP_PORT"
[[ -n "$_has_HSD_GITLAB_LOCAL_SSH_PORT" ]] && HSD_GITLAB_LOCAL_SSH_PORT="$_env_HSD_GITLAB_LOCAL_SSH_PORT"
[[ -n "$_has_HSD_GITLAB_REMOTE_HTTP_PORT" ]] && HSD_GITLAB_REMOTE_HTTP_PORT="$_env_HSD_GITLAB_REMOTE_HTTP_PORT"
[[ -n "$_has_HSD_GITLAB_REMOTE_SSH_PORT" ]] && HSD_GITLAB_REMOTE_SSH_PORT="$_env_HSD_GITLAB_REMOTE_SSH_PORT"
[[ -n "$_has_HSD_API_KEY" ]] && HSD_API_KEY="$_env_HSD_API_KEY"
[[ -n "$_has_HSD_NODE_URL" ]] && HSD_NODE_URL="$_env_HSD_NODE_URL"
[[ -n "$_has_HSD_WALLET_URL" ]] && HSD_WALLET_URL="$_env_HSD_WALLET_URL"
[[ -n "$_has_HSD_LOCAL_NODE_PORT" ]] && HSD_LOCAL_NODE_PORT="$_env_HSD_LOCAL_NODE_PORT"
[[ -n "$_has_HSD_LOCAL_WALLET_PORT" ]] && HSD_LOCAL_WALLET_PORT="$_env_HSD_LOCAL_WALLET_PORT"
[[ -n "$_has_HSD_DRY_RUN" ]] && HSD_DRY_RUN="$_env_HSD_DRY_RUN"

HSD_REMOTE_HOST="${HSD_REMOTE_HOST:-}"
HSD_REMOTE_USER="${HSD_REMOTE_USER:-root}"
HSD_REMOTE_DIR="${HSD_REMOTE_DIR:-~/handshake}"
HSD_SSH_IDENTITY_FILE="${HSD_SSH_IDENTITY_FILE:-}"
HSD_SSH_SERVER_ALIVE_INTERVAL="${HSD_SSH_SERVER_ALIVE_INTERVAL:-30}"
HSD_SSH_SERVER_ALIVE_COUNT_MAX="${HSD_SSH_SERVER_ALIVE_COUNT_MAX:-3}"
HSD_GITLAB_LOCAL_HTTP_PORT="${HSD_GITLAB_LOCAL_HTTP_PORT:-8929}"
HSD_GITLAB_LOCAL_SSH_PORT="${HSD_GITLAB_LOCAL_SSH_PORT:-2222}"
HSD_GITLAB_REMOTE_HTTP_PORT="${HSD_GITLAB_REMOTE_HTTP_PORT:-18080}"
HSD_GITLAB_REMOTE_SSH_PORT="${HSD_GITLAB_REMOTE_SSH_PORT:-12222}"
HSD_API_KEY="${HSD_API_KEY:-changeme}"
HSD_NODE_URL="${HSD_NODE_URL:-http://127.0.0.1:12037}"
HSD_WALLET_URL="${HSD_WALLET_URL:-http://127.0.0.1:12039}"
HSD_LOCAL_NODE_PORT="${HSD_LOCAL_NODE_PORT:-12037}"
HSD_LOCAL_WALLET_PORT="${HSD_LOCAL_WALLET_PORT:-12039}"
HSD_DRY_RUN="${HSD_DRY_RUN:-0}"
HSD_TUNNEL_UNIT="hsd-tunnel.service"
HSD_TUNNEL_SYSTEM_UNIT="hsd-tunnel.service"
HSD_TUNNEL_SYSTEM_UNIT_SRC="hsd-tunnel.system.service"

usage() {
  cat <<'EOF'
Usage:
  ./hsd.sh help
  ./hsd.sh tunnel
  ./hsd.sh api-tunnel
  ./hsd.sh tunnel-install
  ./hsd.sh tunnel-start
  ./hsd.sh tunnel-stop
  ./hsd.sh tunnel-status
  ./hsd.sh tunnel-enable-boot
  ./hsd.sh sync
  ./hsd.sh node-info
  ./hsd.sh wallet-info
  ./hsd.sh wallet-primary
  ./hsd.sh name <name>
  ./hsd.sh name-rpc <name>
  ./hsd.sh block <height>
  ./hsd.sh rpc <method> [json_params]
  ./hsd.sh remote-ps
  ./hsd.sh remote-logs [service]
  ./hsd.sh remote-up
  ./hsd.sh remote-down
  ./hsd.sh remote-restart

Config:
  HSD_REMOTE_HOST                   Aliyun public IP or hostname, required for SSH commands
  HSD_REMOTE_USER                   SSH user, default: root
  HSD_REMOTE_DIR                    Remote compose directory, default: ~/handshake
  HSD_SSH_IDENTITY_FILE             SSH private key path (optional)
  HSD_SSH_SERVER_ALIVE_INTERVAL     SSH keepalive seconds, default: 30
  HSD_SSH_SERVER_ALIVE_COUNT_MAX    SSH keepalive miss count, default: 3
  HSD_GITLAB_LOCAL_HTTP_PORT        Local GitLab HTTP port, default: 8929
  HSD_GITLAB_LOCAL_SSH_PORT          Local GitLab SSH port, default: 2222
  HSD_GITLAB_REMOTE_HTTP_PORT        Aliyun published HTTP port, default: 18080
  HSD_GITLAB_REMOTE_SSH_PORT         Aliyun published SSH port, default: 12222
  HSD_API_KEY                       hsd API key, default: changeme
  HSD_NODE_URL                      Node API URL, default: http://127.0.0.1:12037
  HSD_WALLET_URL                    Wallet API URL, default: http://127.0.0.1:12039
  HSD_LOCAL_NODE_PORT               Local api-tunnel node port, default: 12037
  HSD_LOCAL_WALLET_PORT             Local api-tunnel wallet port, default: 12039
  HSD_DRY_RUN=1                     Print commands without running them

Examples:
  ./hsd.sh tunnel-install && ./hsd.sh tunnel-start
  # Path: Host A => Aliyun => 216 GitLab (reverse publish)
  HSD_REMOTE_HOST=1.2.3.4 ./hsd.sh tunnel
  ./hsd.sh api-tunnel
  HSD_API_KEY=secret ./hsd.sh node-info
  ./hsd.sh sync
  ./hsd.sh name handshake
  ./hsd.sh name-rpc handshake
  ./hsd.sh rpc getnameinfo '["handshake"]'
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

print_cmd() {
  local arg
  local first=1

  for arg in "$@"; do
    if [[ "$first" -eq 0 ]]; then
      printf ' '
    fi
    printf '%q' "$arg"
    first=0
  done
  printf '\n'
}

run_cmd() {
  if [[ "$HSD_DRY_RUN" == "1" || "$HSD_DRY_RUN" == "true" ]]; then
    print_cmd "$@"
    return 0
  fi

  "$@"
}

require_remote_host() {
  [[ -n "$HSD_REMOTE_HOST" ]] || die "HSD_REMOTE_HOST is required for this command"
}

ssh_target() {
  require_remote_host
  printf '%s@%s' "$HSD_REMOTE_USER" "$HSD_REMOTE_HOST"
}

ssh_base_args() {
  local args=()

  args+=(-o "ServerAliveInterval=$HSD_SSH_SERVER_ALIVE_INTERVAL")
  args+=(-o "ServerAliveCountMax=$HSD_SSH_SERVER_ALIVE_COUNT_MAX")
  args+=(-o "ExitOnForwardFailure=yes")
  if [[ -n "$HSD_SSH_IDENTITY_FILE" ]]; then
    args+=(-i "$HSD_SSH_IDENTITY_FILE" -o IdentitiesOnly=yes)
  fi
  printf '%s\n' "${args[@]}"
}

remote_prefix() {
  if [[ "$HSD_REMOTE_DIR" == "~" || "$HSD_REMOTE_DIR" == "~/"* ]]; then
    printf 'cd %s && ' "$HSD_REMOTE_DIR"
  else
    printf 'cd %q && ' "$HSD_REMOTE_DIR"
  fi
}

remote_compose() {
  local arg
  local target
  local remote_cmd
  local -a ssh_args=()

  target="$(ssh_target)"
  mapfile -t ssh_args < <(ssh_base_args)
  remote_cmd="$(remote_prefix)docker compose"
  for arg in "$@"; do
    remote_cmd+=" $(printf '%q' "$arg")"
  done
  run_cmd ssh "${ssh_args[@]}" "$target" "$remote_cmd"
}

http_get() {
  local url="$1"
  run_cmd curl --fail -sS -u "x:$HSD_API_KEY" "$url"
}

cmd_sync() {
  if [[ "$HSD_DRY_RUN" == "1" || "$HSD_DRY_RUN" == "true" ]]; then
    print_cmd curl --fail -sS -u "x:$HSD_API_KEY" "$HSD_NODE_URL/" "|" python3 -c "print sync progress"
    return 0
  fi

  curl --fail -sS -u "x:$HSD_API_KEY" "$HSD_NODE_URL/" |
    python3 -c 'import sys,json; d=json.load(sys.stdin); c=d["chain"]; print("height={} progress={:.2f}% tip={}".format(c["height"], c["progress"] * 100, c["tip"]))'
}

json_rpc() {
  local method="$1"
  local params="${2:-[]}"
  local payload

  payload="$(printf '{"method":"%s","params":%s}' "$method" "$params")"
  run_cmd curl --fail -sS -u "x:$HSD_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$HSD_NODE_URL/"
}

cmd_tunnel() {
  local target
  local -a ssh_args=()

  # Reverse publish local GitLab to Aliyun:
  # Host A => Aliyun:remote_port => 216:local_port
  target="$(ssh_target)"
  mapfile -t ssh_args < <(ssh_base_args)
  run_cmd ssh -N \
    "${ssh_args[@]}" \
    -R "127.0.0.1:${HSD_GITLAB_REMOTE_HTTP_PORT}:127.0.0.1:${HSD_GITLAB_LOCAL_HTTP_PORT}" \
    -R "127.0.0.1:${HSD_GITLAB_REMOTE_SSH_PORT}:127.0.0.1:${HSD_GITLAB_LOCAL_SSH_PORT}" \
    "$target"
}

cmd_api_tunnel() {
  local target
  local -a ssh_args=()

  # Optional: pull Aliyun hsd APIs to local ports.
  target="$(ssh_target)"
  mapfile -t ssh_args < <(ssh_base_args)
  run_cmd ssh -N \
    "${ssh_args[@]}" \
    -L "$HSD_LOCAL_NODE_PORT:127.0.0.1:12037" \
    -L "$HSD_LOCAL_WALLET_PORT:127.0.0.1:12039" \
    "$target"
}

cmd_tunnel_install() {
  local unit_src="$SCRIPT_DIR/systemd/$HSD_TUNNEL_UNIT"
  local unit_dst="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$HSD_TUNNEL_UNIT"

  [[ -f "$unit_src" ]] || die "Missing unit file: $unit_src"
  if [[ "$HSD_DRY_RUN" == "1" || "$HSD_DRY_RUN" == "true" ]]; then
    print_cmd mkdir -p "$(dirname "$unit_dst")"
    print_cmd cp "$unit_src" "$unit_dst"
    print_cmd systemctl --user daemon-reload
    print_cmd systemctl --user enable "$HSD_TUNNEL_UNIT"
    return 0
  fi

  mkdir -p "$(dirname "$unit_dst")"
  cp "$unit_src" "$unit_dst"
  systemctl --user daemon-reload
  systemctl --user enable "$HSD_TUNNEL_UNIT"
  printf 'Installed and enabled %s\n' "$unit_dst"
  printf 'Start with: ./hsd.sh tunnel-start\n'
  printf 'For boot autostart (system): ./hsd.sh tunnel-enable-boot\n'
}

cmd_tunnel_enable_boot() {
  local unit_src="$SCRIPT_DIR/systemd/$HSD_TUNNEL_SYSTEM_UNIT_SRC"
  local unit_dst="/etc/systemd/system/$HSD_TUNNEL_SYSTEM_UNIT"

  [[ -f "$unit_src" ]] || die "Missing unit file: $unit_src"
  if [[ "$HSD_DRY_RUN" == "1" || "$HSD_DRY_RUN" == "true" ]]; then
    print_cmd sudo cp "$unit_src" "$unit_dst"
    print_cmd sudo systemctl daemon-reload
    print_cmd systemctl --user stop "$HSD_TUNNEL_UNIT"
    print_cmd systemctl --user disable "$HSD_TUNNEL_UNIT"
    print_cmd sudo systemctl enable --now "$HSD_TUNNEL_SYSTEM_UNIT"
    return 0
  fi

  sudo cp "$unit_src" "$unit_dst"
  sudo systemctl daemon-reload
  # Avoid two tunnels fighting for the same local ports.
  systemctl --user stop "$HSD_TUNNEL_UNIT" 2>/dev/null || true
  systemctl --user disable "$HSD_TUNNEL_UNIT" 2>/dev/null || true
  sudo systemctl enable --now "$HSD_TUNNEL_SYSTEM_UNIT"
  printf 'Boot autostart enabled: %s\n' "$unit_dst"
  systemctl --no-pager --full status "$HSD_TUNNEL_SYSTEM_UNIT" || true
}

cmd_tunnel_start() {
  if systemctl cat "$HSD_TUNNEL_SYSTEM_UNIT" &>/dev/null; then
    run_cmd sudo systemctl start "$HSD_TUNNEL_SYSTEM_UNIT"
  else
    run_cmd systemctl --user start "$HSD_TUNNEL_UNIT"
  fi
}

cmd_tunnel_stop() {
  if systemctl cat "$HSD_TUNNEL_SYSTEM_UNIT" &>/dev/null; then
    run_cmd sudo systemctl stop "$HSD_TUNNEL_SYSTEM_UNIT"
  else
    run_cmd systemctl --user stop "$HSD_TUNNEL_UNIT"
  fi
}

cmd_tunnel_status() {
  if systemctl cat "$HSD_TUNNEL_SYSTEM_UNIT" &>/dev/null; then
    run_cmd systemctl status "$HSD_TUNNEL_SYSTEM_UNIT" --no-pager
  else
    run_cmd systemctl --user status "$HSD_TUNNEL_UNIT" --no-pager
  fi
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  tunnel)
    cmd_tunnel
    ;;
  api-tunnel)
    cmd_api_tunnel
    ;;
  tunnel-install)
    cmd_tunnel_install
    ;;
  tunnel-enable-boot)
    cmd_tunnel_enable_boot
    ;;
  tunnel-start)
    cmd_tunnel_start
    ;;
  tunnel-stop)
    cmd_tunnel_stop
    ;;
  tunnel-status)
    cmd_tunnel_status
    ;;
  sync)
    cmd_sync
    ;;
  node-info)
    http_get "$HSD_NODE_URL/"
    ;;
  wallet-info)
    http_get "$HSD_WALLET_URL/"
    ;;
  wallet-primary)
    http_get "$HSD_WALLET_URL/wallet/primary/"
    ;;
  name)
    [[ $# -eq 1 ]] || die "Usage: ./hsd.sh name <name>"
    http_get "$HSD_NODE_URL/name/$1"
    ;;
  name-rpc)
    [[ $# -eq 1 ]] || die "Usage: ./hsd.sh name-rpc <name>"
    json_rpc getnameinfo "[\"$1\"]"
    ;;
  block)
    [[ $# -eq 1 ]] || die "Usage: ./hsd.sh block <height>"
    http_get "$HSD_NODE_URL/block/$1"
    ;;
  rpc)
    [[ $# -ge 1 && $# -le 2 ]] || die "Usage: ./hsd.sh rpc <method> [json_params]"
    json_rpc "$@"
    ;;
  remote-ps)
    remote_compose ps
    ;;
  remote-logs)
    remote_compose logs -f "${1:-hsd}"
    ;;
  remote-up)
    remote_compose up -d
    ;;
  remote-down)
    remote_compose down
    ;;
  remote-restart)
    remote_compose up -d --force-recreate
    ;;
  *)
    usage >&2
    die "Unknown command: $cmd"
    ;;
esac
