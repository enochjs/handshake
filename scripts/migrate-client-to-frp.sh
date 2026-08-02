#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

HANDSHAKE_SSH_CONFIG_PATH="${HANDSHAKE_SSH_CONFIG_PATH:-$HOME/.ssh/config}"
HANDSHAKE_INCLUDE_PATH="${HANDSHAKE_INCLUDE_PATH:-$HOME/.ssh/handshake_config}"
DIRECT_GITLAB_SSH_PREFIX="${DIRECT_GITLAB_SSH_PREFIX:-ssh://git@10.10.0.216:2222/}"
HANDSHAKE_GITLAB_SSH_PREFIX="${HANDSHAKE_GITLAB_SSH_PREFIX:-ssh://git@gitlab-via-handshake/}"

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

expand_path() {
  local value="$1"
  case "$value" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${value#"~/"}" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

remove_ssh_include() {
  local config_path="$1"
  local include_path="$2"
  local tmp_path

  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    echo "Remove Include ${include_path} from ${config_path}"
    return 0
  fi

  [[ -f "$config_path" ]] || return 0
  tmp_path="$(mktemp)"
  awk \
    -v include_line="Include ${include_path}" \
    -v legacy_line="Include ~/.ssh/handshake_config" \
    '$0 != include_line && $0 != legacy_line { print }' \
    "$config_path" >"$tmp_path"
  cat "$tmp_path" >"$config_path"
  rm -f "$tmp_path"
}

uninstall_git_hs() {
  if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
    echo "cargo uninstall handshake-client || true"
    return 0
  fi

  if command -v cargo >/dev/null 2>&1; then
    cargo uninstall handshake-client >/dev/null 2>&1 || true
  fi
}

ssh_config_path="$(expand_path "$HANDSHAKE_SSH_CONFIG_PATH")"
include_path="$(expand_path "$HANDSHAKE_INCLUDE_PATH")"

run_shell "git config --global --unset-all url.${HANDSHAKE_GITLAB_SSH_PREFIX}.insteadOf ${DIRECT_GITLAB_SSH_PREFIX} || true"
run_shell "git config --global --unset-all url.${DIRECT_GITLAB_SSH_PREFIX}.insteadOf ${HANDSHAKE_GITLAB_SSH_PREFIX} || true"
remove_ssh_include "$ssh_config_path" "$include_path"
run rm -f "$include_path"
uninstall_git_hs

cd "$ROOT_DIR/frp-client"
if [[ "$DRY_RUN" == "1" || "$DRY_RUN" == "true" ]]; then
  print_cmd bash install.sh
  bash install.sh
else
  bash install.sh
fi
