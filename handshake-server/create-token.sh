#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DRY_RUN="${DRY_RUN:-0}"
_env_DRY_RUN="${DRY_RUN-}"
_env_HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE-}"
_env_HANDSHAKE_NEW_TOKEN="${HANDSHAKE_NEW_TOKEN-}"

_has_DRY_RUN="${DRY_RUN+x}"
_has_HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE+x}"
_has_HANDSHAKE_NEW_TOKEN="${HANDSHAKE_NEW_TOKEN+x}"

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

run() {
  if is_dry_run; then
    print_cmd "$@"
  else
    "$@"
  fi
}

generate_token() {
  python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
}

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

[[ -n "$_has_DRY_RUN" ]] && DRY_RUN="$_env_DRY_RUN"
[[ -n "$_has_HANDSHAKE_TOKEN_FILE" ]] && HANDSHAKE_TOKEN_FILE="$_env_HANDSHAKE_TOKEN_FILE"
[[ -n "$_has_HANDSHAKE_NEW_TOKEN" ]] && HANDSHAKE_NEW_TOKEN="$_env_HANDSHAKE_NEW_TOKEN"

HANDSHAKE_TOKEN_FILE="${HANDSHAKE_TOKEN_FILE:-/etc/handshake-client/tokens}"
TOKEN="${1:-${HANDSHAKE_NEW_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(generate_token)"
fi

if [[ "$TOKEN" == *$'\n'* || "$TOKEN" == *$'\r'* ]]; then
  echo "Error: token must be a single line" >&2
  exit 1
fi

run sudo install -d -m 700 "$(dirname "$HANDSHAKE_TOKEN_FILE")"
if is_dry_run; then
  printf "printf '%%s\\n' '%s' | sudo tee -a '%s' >/dev/null\n" \
    "$TOKEN" \
    "$HANDSHAKE_TOKEN_FILE"
else
  printf '%s\n' "$TOKEN" | sudo tee -a "$HANDSHAKE_TOKEN_FILE" >/dev/null
fi
run sudo chmod 600 "$HANDSHAKE_TOKEN_FILE"

printf '%s\n' "$TOKEN"
