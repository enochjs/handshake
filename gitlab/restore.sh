#!/usr/bin/env bash
# GitLab 恢复说明与辅助脚本
#
# 完整恢复步骤（摘要）:
#   1. 停止写操作: docker exec -t gitlab gitlab-ctl stop puma sidekiq
#   2. 恢复配置密钥（若需要）:
#        cp backups/config/<时间戳>/gitlab-secrets.json config/
#        cp backups/config/<时间戳>/gitlab.rb config/   # 按需
#        docker compose -f ~/gitlab/docker-compose.yml restart
#   3. 将 *_gitlab_backup.tar 放到 data/backups/
#   4. 执行本脚本: ./restore.sh <备份时间戳>
#      时间戳形如 1785382687（文件名: 1785382687_YYYY_MM_DD_..._gitlab_backup.tar 的前缀数字）
#   5. docker exec -t gitlab gitlab-ctl reconfigure
#   6. docker exec -t gitlab gitlab-ctl restart
#
# 用法:
#   ./restore.sh                  # 列出可用备份
#   ./restore.sh <TIMESTAMP>      # 从指定备份恢复

set -euo pipefail

CONTAINER="${GITLAB_CONTAINER:-gitlab}"
GITLAB_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="${1:-}"

list_backups() {
  echo "=== 数据备份 (data/backups) ==="
  docker exec "$CONTAINER" bash -c 'ls -lt /var/opt/gitlab/backups/*_gitlab_backup.tar 2>/dev/null' || echo "(无)"
  echo
  echo "=== 配置快照 (backups/config) ==="
  ls -lt "${GITLAB_DIR}/backups/config" 2>/dev/null || echo "(无)"
  echo
  echo "恢复示例: $0 1785382687"
}

if [[ -z "$TIMESTAMP" ]]; then
  list_backups
  exit 0
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "错误: 容器 $CONTAINER 未运行"
  exit 1
fi

TAR="$(docker exec "$CONTAINER" bash -c "ls /var/opt/gitlab/backups/${TIMESTAMP}_*_gitlab_backup.tar 2>/dev/null | head -1")"
if [[ -z "$TAR" ]]; then
  echo "错误: 找不到时间戳为 ${TIMESTAMP} 的备份"
  list_backups
  exit 1
fi

echo "将恢复: $TAR"
echo "警告: 会覆盖当前 GitLab 数据。5 秒后继续，Ctrl+C 取消..."
sleep 5

echo "停止 puma / sidekiq..."
docker exec -t "$CONTAINER" gitlab-ctl stop puma
docker exec -t "$CONTAINER" gitlab-ctl stop sidekiq

echo "执行 gitlab-backup restore..."
docker exec -t "$CONTAINER" gitlab-backup restore BACKUP="$TIMESTAMP" force=yes

echo "reconfigure + restart..."
docker exec -t "$CONTAINER" gitlab-ctl reconfigure
docker exec -t "$CONTAINER" gitlab-ctl restart

echo "恢复完成。请打开 http://10.10.0.216:8929 检查。"
echo "若登录/加密相关异常，请从 backups/config/<时间戳>/ 恢复 gitlab-secrets.json 后重启。"
