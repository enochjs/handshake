#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
elif [[ "$DRY_RUN" != "1" && "$DRY_RUN" != "true" ]]; then
  cp env.example .env
  echo "Created frp-source/.env; fill it and rerun."
  exit 1
fi

FRP_VERSION="${FRP_VERSION:-0.68.0}"
FRP_SERVER_ADDR="${FRP_SERVER_ADDR:-}"
FRP_SERVER_PORT="${FRP_SERVER_PORT:-7000}"
FRP_AUTH_TOKEN="${FRP_AUTH_TOKEN:-}"
FRP_SECRET_KEY="${FRP_SECRET_KEY:-}"
GITLAB_LOCAL_HOST="${GITLAB_LOCAL_HOST:-127.0.0.1}"
GITLAB_WEB_PORT="${GITLAB_WEB_PORT:-8929}"
GITLAB_SSH_PORT="${GITLAB_SSH_PORT:-2222}"
FRP_CONFIG_PATH="${FRP_CONFIG_PATH:-/etc/frp/frpc-source.toml}"
FRP_BINARY_PATH="${FRP_BINARY_PATH:-/usr/local/bin/frpc}"
FRP_SKIP_BINARY_INSTALL="${FRP_SKIP_BINARY_INSTALL:-0}"

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
    -e "s|\${GITLAB_LOCAL_HOST}|${GITLAB_LOCAL_HOST}|g" \
    -e "s|\${GITLAB_WEB_PORT}|${GITLAB_WEB_PORT}|g" \
    -e "s|\${GITLAB_SSH_PORT}|${GITLAB_SSH_PORT}|g" \
    frpc.toml.template
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

  local arch
  local archive
  local url
  local tmp_dir
  arch="$(frp_arch)"
  archive="frp_${FRP_VERSION}_linux_${arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${archive}"
  tmp_dir="/tmp/frp-${FRP_VERSION}-source"

  run curl -fL "$url" -o "/tmp/${archive}"
  run rm -rf "$tmp_dir"
  run mkdir -p "$tmp_dir"
  run tar -xzf "/tmp/${archive}" -C "$tmp_dir" --strip-components=1
  run sudo install -m 755 "$tmp_dir/frpc" "$FRP_BINARY_PATH"
}

install_frpc_binary

run sudo install -d -m 755 "$(dirname "$FRP_CONFIG_PATH")"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  echo "Would render $FRP_CONFIG_PATH"
  render_config
else
  render_config | sudo tee "$FRP_CONFIG_PATH" >/dev/null
  sudo chmod 600 "$FRP_CONFIG_PATH"
fi

if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  print_cmd sudo tee /etc/systemd/system/frp-source.service
else
  sudo tee /etc/systemd/system/frp-source.service >/dev/null <<EOF
[Unit]
Description=frp source for internal GitLab
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
run sudo systemctl enable --now frp-source.service
run sudo systemctl --no-pager --full status frp-source.service

echo "frp source config: ${FRP_CONFIG_PATH}"
echo "GitLab Web: ${GITLAB_LOCAL_HOST}:${GITLAB_WEB_PORT}"
echo "GitLab SSH: ${GITLAB_LOCAL_HOST}:${GITLAB_SSH_PORT}"
