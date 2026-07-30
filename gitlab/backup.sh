#!/usr/bin/env bash
# GitLab 每日备份：应用数据 + 配置密钥
# 用法: ./backup.sh
# 定时: 0 2 * * * /home/linkmore/gitlab/backup.sh

set -euo pipefail

CONTAINER="${GITLAB_CONTAINER:-gitlab}"
GITLAB_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "${GITLAB_DIR}/.env" ]]; then
  set -a
  source "${GITLAB_DIR}/.env"
  set +a
fi

CONTAINER="${GITLAB_CONTAINER:-gitlab}"
KEEP_DAYS="${BACKUP_KEEP_DAYS:-7}"
CONFIG_BACKUP_DIR="${GITLAB_DIR}/backups/config"
LOG_DIR="${GITLAB_DIR}/backups"
LOG_FILE="${LOG_DIR}/backup.log"
STAMP="$(date +%Y%m%d_%H%M%S)"

mkdir -p "$CONFIG_BACKUP_DIR" "$LOG_DIR"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"
}

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  log "ERROR: 容器 $CONTAINER 未运行"
  exit 1
fi

log "开始备份..."

# 1) GitLab 官方备份（仓库/DB/上传等）→ ~/gitlab/data/backups/
log "创建 gitlab-backup..."
docker exec -t "$CONTAINER" gitlab-backup create STRATEGY=copy CRON=1
log "gitlab-backup 完成"

# 2) 配置与密钥（恢复时必需，官方 backup 不含此项）
DEST="${CONFIG_BACKUP_DIR}/${STAMP}"
mkdir -p "$DEST"
docker cp "${CONTAINER}:/etc/gitlab/gitlab.rb" "${DEST}/gitlab.rb"
docker cp "${CONTAINER}:/etc/gitlab/gitlab-secrets.json" "${DEST}/gitlab-secrets.json"
# SSH host keys（避免恢复后客户端 host key 变化）
docker cp "${CONTAINER}:/etc/gitlab/ssh_host_rsa_key" "${DEST}/" 2>/dev/null || true
docker cp "${CONTAINER}:/etc/gitlab/ssh_host_rsa_key.pub" "${DEST}/" 2>/dev/null || true
docker cp "${CONTAINER}:/etc/gitlab/ssh_host_ecdsa_key" "${DEST}/" 2>/dev/null || true
docker cp "${CONTAINER}:/etc/gitlab/ssh_host_ecdsa_key.pub" "${DEST}/" 2>/dev/null || true
docker cp "${CONTAINER}:/etc/gitlab/ssh_host_ed25519_key" "${DEST}/" 2>/dev/null || true
docker cp "${CONTAINER}:/etc/gitlab/ssh_host_ed25519_key.pub" "${DEST}/" 2>/dev/null || true
chmod -R go-rwx "$DEST" || true
log "配置快照: $DEST"

# 3) 清理过期配置快照（数据 tar 由 backup_keep_time 清理）
find "$CONFIG_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"${KEEP_DAYS}" -exec rm -rf {} +
log "已清理 ${KEEP_DAYS} 天前的配置快照"

# 列出最近备份
log "最近数据备份:"
docker exec "$CONTAINER" bash -c 'ls -lt /var/opt/gitlab/backups/*_gitlab_backup.tar 2>/dev/null | head -5' \
  | tee -a "$LOG_FILE" || log "(暂无 tar)"

log "备份完成"
