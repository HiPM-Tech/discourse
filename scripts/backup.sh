#!/bin/bash
# Discourse 数据备份脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BACKUP_DIR="./backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="discourse_backup_${TIMESTAMP}"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 创建备份目录
mkdir -p "${BACKUP_DIR}"

log_info "Starting backup: ${BACKUP_NAME}"

# 备份数据库
log_info "Backing up database..."
docker-compose exec -T postgres pg_dump -U discourse discourse > "${BACKUP_DIR}/${BACKUP_NAME}.sql"

# 备份上传文件
log_info "Backing up uploads..."
docker-compose run --rm app tar czf - /var/www/discourse/public/uploads > "${BACKUP_DIR}/${BACKUP_NAME}_uploads.tar.gz" 2>/dev/null || true

# 备份 Redis 数据
log_info "Backing up Redis..."
docker-compose exec -T redis redis-cli BGSAVE
sleep 2
docker-compose run --rm app tar czf - /data/dump.rdb > "${BACKUP_DIR}/${BACKUP_NAME}_redis.tar.gz" 2>/dev/null || true

# 创建备份信息文件
cat > "${BACKUP_DIR}/${BACKUP_NAME}_info.txt" <<EOF
Discourse Backup Information
============================
Backup Date: $(date)
Backup Name: ${BACKUP_NAME}

Contents:
- ${BACKUP_NAME}.sql: PostgreSQL database dump
- ${BACKUP_NAME}_uploads.tar.gz: Uploaded files
- ${BACKUP_NAME}_redis.tar.gz: Redis data

Restore Instructions:
1. Stop the application: docker-compose down
2. Restore database: docker-compose exec -T postgres psql -U discourse < ${BACKUP_NAME}.sql
3. Restore uploads: tar xzf ${BACKUP_NAME}_uploads.tar.gz
4. Restore Redis: tar xzf ${BACKUP_NAME}_redis.tar.gz
5. Start the application: docker-compose up -d
EOF

log_info "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}*"

# 清理旧备份（保留最近7天）
log_info "Cleaning up old backups..."
find "${BACKUP_DIR}" -name "discourse_backup_*" -mtime +7 -delete

log_info "Backup process finished successfully!"
