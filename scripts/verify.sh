#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

bash -n \
  gitlab/install.sh \
  gitlab/status.sh \
  gitlab/backup.sh \
  gitlab/restore.sh \
  gitlab/set-user-password.sh \
  handshake-server/install.sh \
  handshake-server/status.sh \
  handshake-source/tunnel.sh \
  handshake-source/install.sh \
  handshake-source/status.sh \
  handshake-client/install.sh \
  frp-server/install.sh \
  frp-server/uninstall.sh \
  frp-server/status.sh \
  frp-source/install.sh \
  frp-source/uninstall.sh \
  frp-source/status.sh \
  frp-client/install.sh \
  frp-client/status.sh \
  scripts/destroy.sh

scripts/test_installers.sh
scripts/test_frp_installers.sh
scripts/test_gitlab_user_helper.sh
python3 handshake-server/server/add_key_server_test.py
handshake-source/tests/tunnel_test.sh

(
  cd handshake-client
  cargo test
)

echo "PASS: repository verification"
