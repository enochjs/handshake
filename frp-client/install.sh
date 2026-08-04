#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
_env_DRY_RUN="${DRY_RUN-}"
_env_FRP_VERSION="${FRP_VERSION-}"
_env_FRP_SERVER_ADDR="${FRP_SERVER_ADDR-}"
_env_FRP_SERVER_PORT="${FRP_SERVER_PORT-}"
_env_FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN-}"
_env_FRP_SECRET_KEY="${FRP_SECRET_KEY-}"
_env_GITLAB_LOCAL_NAME="${GITLAB_LOCAL_NAME-}"
_env_GITLAB_WEB_BIND_ADDR="${GITLAB_WEB_BIND_ADDR-}"
_env_GITLAB_WEB_BIND_PORT="${GITLAB_WEB_BIND_PORT-}"
_env_GITLAB_SSH_BIND_ADDR="${GITLAB_SSH_BIND_ADDR-}"
_env_GITLAB_SSH_BIND_PORT="${GITLAB_SSH_BIND_PORT-}"
_env_MACHINE_SSH_BIND_ADDR="${MACHINE_SSH_BIND_ADDR-}"
_env_MACHINE_SSH_BIND_PORT="${MACHINE_SSH_BIND_PORT-}"
_env_FRP_FALLBACK_TIMEOUT_MS="${FRP_FALLBACK_TIMEOUT_MS-}"
_env_FRP_KEEP_TUNNEL_OPEN="${FRP_KEEP_TUNNEL_OPEN-}"
_env_DIRECT_GITLAB_SSH_PREFIX="${DIRECT_GITLAB_SSH_PREFIX-}"
_env_FRP_GITLAB_SSH_PREFIX="${FRP_GITLAB_SSH_PREFIX-}"
_env_FRP_CONFIG_PATH="${FRP_CONFIG_PATH-}"
_env_FRP_BINARY_PATH="${FRP_BINARY_PATH-}"
_env_FRP_SKIP_BINARY_INSTALL="${FRP_SKIP_BINARY_INSTALL-}"
_env_FRP_SERVICE_MANAGER="${FRP_SERVICE_MANAGER-}"

_has_DRY_RUN="${DRY_RUN+x}"
_has_FRP_VERSION="${FRP_VERSION+x}"
_has_FRP_SERVER_ADDR="${FRP_SERVER_ADDR+x}"
_has_FRP_SERVER_PORT="${FRP_SERVER_PORT+x}"
_has_FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN+x}"
_has_FRP_SECRET_KEY="${FRP_SECRET_KEY+x}"
_has_GITLAB_LOCAL_NAME="${GITLAB_LOCAL_NAME+x}"
_has_GITLAB_WEB_BIND_ADDR="${GITLAB_WEB_BIND_ADDR+x}"
_has_GITLAB_WEB_BIND_PORT="${GITLAB_WEB_BIND_PORT+x}"
_has_GITLAB_SSH_BIND_ADDR="${GITLAB_SSH_BIND_ADDR+x}"
_has_GITLAB_SSH_BIND_PORT="${GITLAB_SSH_BIND_PORT+x}"
_has_MACHINE_SSH_BIND_ADDR="${MACHINE_SSH_BIND_ADDR+x}"
_has_MACHINE_SSH_BIND_PORT="${MACHINE_SSH_BIND_PORT+x}"
_has_FRP_FALLBACK_TIMEOUT_MS="${FRP_FALLBACK_TIMEOUT_MS+x}"
_has_FRP_KEEP_TUNNEL_OPEN="${FRP_KEEP_TUNNEL_OPEN+x}"
_has_DIRECT_GITLAB_SSH_PREFIX="${DIRECT_GITLAB_SSH_PREFIX+x}"
_has_FRP_GITLAB_SSH_PREFIX="${FRP_GITLAB_SSH_PREFIX+x}"
_has_FRP_CONFIG_PATH="${FRP_CONFIG_PATH+x}"
_has_FRP_BINARY_PATH="${FRP_BINARY_PATH+x}"
_has_FRP_SKIP_BINARY_INSTALL="${FRP_SKIP_BINARY_INSTALL+x}"
_has_FRP_SERVICE_MANAGER="${FRP_SERVICE_MANAGER+x}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
elif [[ "$DRY_RUN" != "1" && "$DRY_RUN" != "true" ]]; then
  cp env.example .env
  echo "Created frp-client/.env; fill it and rerun."
  exit 1
fi

[[ -n "$_has_DRY_RUN" ]] && DRY_RUN="$_env_DRY_RUN"
[[ -n "$_has_FRP_VERSION" ]] && FRP_VERSION="$_env_FRP_VERSION"
[[ -n "$_has_FRP_SERVER_ADDR" ]] && FRP_SERVER_ADDR="$_env_FRP_SERVER_ADDR"
[[ -n "$_has_FRP_SERVER_PORT" ]] && FRP_SERVER_PORT="$_env_FRP_SERVER_PORT"
[[ -n "$_has_FRP_AUTH_TOKEN" ]] && FRP_AUTH_TOKEN="$_env_FRP_AUTH_TOKEN"
[[ -n "$_has_FRP_SECRET_KEY" ]] && FRP_SECRET_KEY="$_env_FRP_SECRET_KEY"
[[ -n "$_has_GITLAB_LOCAL_NAME" ]] && GITLAB_LOCAL_NAME="$_env_GITLAB_LOCAL_NAME"
[[ -n "$_has_GITLAB_WEB_BIND_ADDR" ]] && GITLAB_WEB_BIND_ADDR="$_env_GITLAB_WEB_BIND_ADDR"
[[ -n "$_has_GITLAB_WEB_BIND_PORT" ]] && GITLAB_WEB_BIND_PORT="$_env_GITLAB_WEB_BIND_PORT"
[[ -n "$_has_GITLAB_SSH_BIND_ADDR" ]] && GITLAB_SSH_BIND_ADDR="$_env_GITLAB_SSH_BIND_ADDR"
[[ -n "$_has_GITLAB_SSH_BIND_PORT" ]] && GITLAB_SSH_BIND_PORT="$_env_GITLAB_SSH_BIND_PORT"
[[ -n "$_has_MACHINE_SSH_BIND_ADDR" ]] && MACHINE_SSH_BIND_ADDR="$_env_MACHINE_SSH_BIND_ADDR"
[[ -n "$_has_MACHINE_SSH_BIND_PORT" ]] && MACHINE_SSH_BIND_PORT="$_env_MACHINE_SSH_BIND_PORT"
[[ -n "$_has_FRP_FALLBACK_TIMEOUT_MS" ]] && FRP_FALLBACK_TIMEOUT_MS="$_env_FRP_FALLBACK_TIMEOUT_MS"
[[ -n "$_has_FRP_KEEP_TUNNEL_OPEN" ]] && FRP_KEEP_TUNNEL_OPEN="$_env_FRP_KEEP_TUNNEL_OPEN"
[[ -n "$_has_DIRECT_GITLAB_SSH_PREFIX" ]] && DIRECT_GITLAB_SSH_PREFIX="$_env_DIRECT_GITLAB_SSH_PREFIX"
[[ -n "$_has_FRP_GITLAB_SSH_PREFIX" ]] && FRP_GITLAB_SSH_PREFIX="$_env_FRP_GITLAB_SSH_PREFIX"
[[ -n "$_has_FRP_CONFIG_PATH" ]] && FRP_CONFIG_PATH="$_env_FRP_CONFIG_PATH"
[[ -n "$_has_FRP_BINARY_PATH" ]] && FRP_BINARY_PATH="$_env_FRP_BINARY_PATH"
[[ -n "$_has_FRP_SKIP_BINARY_INSTALL" ]] && FRP_SKIP_BINARY_INSTALL="$_env_FRP_SKIP_BINARY_INSTALL"
[[ -n "$_has_FRP_SERVICE_MANAGER" ]] && FRP_SERVICE_MANAGER="$_env_FRP_SERVICE_MANAGER"

FRP_VERSION="${FRP_VERSION:-0.68.0}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_SECRET_KEY="${FRP_SECRET_KEY:-}"
GITLAB_LOCAL_NAME="${GITLAB_LOCAL_NAME:-gitlab.internal}"
GITLAB_WEB_BIND_ADDR="${GITLAB_WEB_BIND_ADDR:-127.0.0.1}"
GITLAB_WEB_BIND_PORT="${GITLAB_WEB_BIND_PORT:-8929}"
GITLAB_SSH_BIND_ADDR="${GITLAB_SSH_BIND_ADDR:-127.0.0.1}"
GITLAB_SSH_BIND_PORT="${GITLAB_SSH_BIND_PORT:-2222}"
MACHINE_SSH_BIND_ADDR="${MACHINE_SSH_BIND_ADDR:-127.0.0.1}"
MACHINE_SSH_BIND_PORT="${MACHINE_SSH_BIND_PORT:-10022}"
FRP_FALLBACK_TIMEOUT_MS="${FRP_FALLBACK_TIMEOUT_MS:-300}"
FRP_KEEP_TUNNEL_OPEN="${FRP_KEEP_TUNNEL_OPEN:-true}"
DIRECT_GITLAB_SSH_PREFIX="${DIRECT_GITLAB_SSH_PREFIX:-ssh://git@10.10.0.216:2222/}"
FRP_GITLAB_SSH_PREFIX="${FRP_GITLAB_SSH_PREFIX:-ssh://git@gitlab.internal:2222/}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-/etc/frp/frpc-client.toml}"
FRP_BINARY_PATH="${FRP_BINARY_PATH:-/usr/local/bin/frpc}"
FRP_SKIP_BINARY_INSTALL="${FRP_SKIP_BINARY_INSTALL:-0}"
FRP_SERVICE_MANAGER="${FRP_SERVICE_MANAGER:-auto}"

[[ -n "$FRP_SERVER_ADDR" ]] || { echo "FRP_SERVER_ADDR is required"; exit 1; }
[[ -n "$FRP_AUTH_TOKEN" ]] || { echo "FRP_AUTH_TOKEN is required"; exit 1; }
[[ -n "$FRP_SECRET_KEY" ]] || { echo "FRP_SECRET_KEY is required"; exit 1; }

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

render_config() {
  sed \
    -e "s|\${FRP_SERVER_ADDR}|${FRP_SERVER_ADDR}|g" \
    -e "s|\${FRP_SERVER_PORT}|${FRP_SERVER_PORT}|g" \
    -e "s|\${FRP_AUTH_TOKEN}|${FRP_AUTH_TOKEN}|g" \
    -e "s|\${FRP_SECRET_KEY}|${FRP_SECRET_KEY}|g" \
    -e "s|\${GITLAB_WEB_BIND_ADDR}|${GITLAB_WEB_BIND_ADDR}|g" \
    -e "s|\${GITLAB_WEB_BIND_PORT}|${GITLAB_WEB_BIND_PORT}|g" \
    -e "s|\${GITLAB_SSH_BIND_ADDR}|${GITLAB_SSH_BIND_ADDR}|g" \
    -e "s|\${GITLAB_SSH_BIND_PORT}|${GITLAB_SSH_BIND_PORT}|g" \
    -e "s|\${MACHINE_SSH_BIND_ADDR}|${MACHINE_SSH_BIND_ADDR}|g" \
    -e "s|\${MACHINE_SSH_BIND_PORT}|${MACHINE_SSH_BIND_PORT}|g" \
    -e "s|\${FRP_KEEP_TUNNEL_OPEN}|${FRP_KEEP_TUNNEL_OPEN}|g" \
    -e "s|\${FRP_FALLBACK_TIMEOUT_MS}|${FRP_FALLBACK_TIMEOUT_MS}|g" \
    frpc.toml.template
}

frp_os() {
  case "$(uname -s)" in
    Linux) printf 'linux\n' ;;
    Darwin) printf 'darwin\n' ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
}

frp_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
}

install_frpc_binary() {
  [[ "$FRP_SKIP_BINARY_INSTALL" != "1" && "$FRP_SKIP_BINARY_INSTALL" != "true" ]] || return 0

  local os
  local arch
  local archive
  local url
  local tmp_dir
  os="$(frp_os)"
  arch="$(frp_arch)"
  archive="frp_${FRP_VERSION}_${os}_${arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${archive}"
  tmp_dir="/tmp/frp-${FRP_VERSION}-client"

  run curl -fL "$url" -o "/tmp/${archive}"
  run rm -rf "$tmp_dir"
  run mkdir -p "$tmp_dir"
  run tar -xzf "/tmp/${archive}" -C "$tmp_dir" --strip-components=1
  run sudo install -m 755 "$tmp_dir/frpc" "$FRP_BINARY_PATH"
}

install_hosts_entry() {
  local entry="127.0.0.1 ${GITLAB_LOCAL_NAME}"
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    echo "$entry"
    return 0
  fi

  if ! grep -qE "^[[:space:]]*127\\.0\\.0\\.1[[:space:]].*\\b${GITLAB_LOCAL_NAME}\\b" /etc/hosts; then
    printf '%s\n' "$entry" | sudo tee -a /etc/hosts >/dev/null
  fi
}

service_manager() {
  if [[ "$FRP_SERVICE_MANAGER" != "auto" ]]; then
    printf '%s\n' "$FRP_SERVICE_MANAGER"
    return 0
  fi

  case "$(uname -s)" in
    Linux) printf 'systemd\n' ;;
    Darwin) printf 'launchd\n' ;;
    *) printf 'manual\n' ;;
  esac
}

install_config_permissions() {
  local manager="$1"

  case "$manager" in
    systemd)
      run sudo chmod 600 "$FRP_CONFIG_PATH"
      ;;
    launchd|manual)
      run sudo chown "$(id -un):$(id -gn)" "$FRP_CONFIG_PATH"
      run sudo chmod 600 "$FRP_CONFIG_PATH"
      ;;
    *) echo "Unknown FRP_SERVICE_MANAGER: ${manager}" >&2; exit 1 ;;
  esac
}

install_systemd_service() {
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd sudo tee /etc/systemd/system/frp-client.service
  else
    sudo tee /etc/systemd/system/frp-client.service >/dev/null <<EOF
[Unit]
Description=frp client visitor for private GitLab
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${FRP_BINARY_PATH} -c ${FRP_CONFIG_PATH}
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  fi

  run sudo systemctl daemon-reload
  run sudo systemctl enable --now frp-client.service
}

install_launchd_service() {
  local plist_path="$HOME/Library/LaunchAgents/com.handshake.frp-client.plist"
  run mkdir -p "$(dirname "$plist_path")"

  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    print_cmd sudo chown "$(id -un):$(id -gn)" "$plist_path"
    echo "Would render $plist_path"
  else
    if [[ -e "$plist_path" ]]; then
      sudo chown "$(id -un):$(id -gn)" "$plist_path"
    fi
    cat >"$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.handshake.frp-client</string>
  <key>ProgramArguments</key>
  <array>
    <string>${FRP_BINARY_PATH}</string>
    <string>-c</string>
    <string>${FRP_CONFIG_PATH}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/frp-client.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/frp-client.err.log</string>
</dict>
</plist>
EOF
  fi

  run launchctl unload "$plist_path"
  run launchctl load "$plist_path"
}

install_manual_service() {
  echo "Start frpc manually with:"
  echo "  ${FRP_BINARY_PATH} -c ${FRP_CONFIG_PATH}"
}

install_frpc_binary

service_mgr="$(service_manager)"

run sudo install -d -m 755 "$(dirname "$FRP_CONFIG_PATH")"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Would render $FRP_CONFIG_PATH"
  render_config
else
  render_config | sudo tee "$FRP_CONFIG_PATH" >/dev/null
fi
install_config_permissions "$service_mgr"

install_hosts_entry
run git config --global "url.${FRP_GITLAB_SSH_PREFIX}.insteadOf" "$DIRECT_GITLAB_SSH_PREFIX"

case "$service_mgr" in
  systemd) install_systemd_service ;;
  launchd) install_launchd_service ;;
  manual) install_manual_service ;;
  *) echo "Unknown FRP_SERVICE_MANAGER: ${FRP_SERVICE_MANAGER}" >&2; exit 1 ;;
esac

echo "frp client config: ${FRP_CONFIG_PATH}"
echo "GitLab Web: http://${GITLAB_LOCAL_NAME}:${GITLAB_WEB_BIND_PORT}"
echo "GitLab SSH: ssh://git@${GITLAB_LOCAL_NAME}:${GITLAB_SSH_BIND_PORT}/<group>/<repo>.git"
echo "Machine SSH: ssh linkmore@${GITLAB_LOCAL_NAME} -p ${MACHINE_SSH_BIND_PORT}"
