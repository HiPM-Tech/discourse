#!/bin/bash
# Discourse 数据恢复脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BACKUP_DIR="./backups"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查参数
if [ -z "$1" ]; then
    log_error "Usage: $0 <backup_name>"
    echo "Available backups:"
    ls -1 "${BACKUP_DIR}"/discourse_backup_*.sql 2>/dev/null | xargs -n1 basename -s .sql || echo "No backups found"
    exit 1
fi

BACKUP_NAME="$1"
SQL_FILE="${BACKUP_DIR}/${BACKUP_NAME}.sql"
UPLOADS_FILE="${BACKUP_DIR}/${BACKUP_NAME}_uploads.tar.gz"
REDIS_FILE="${BACKUP_DIR}/${BACKUP_NAME}_redis.tar.gz"

# 检查备份文件是否存在
if [ ! -f "${SQL_FILE}" ]; then
    log_error "Backup file not found: ${SQL_FILE}"
fi

log_warn "This will overwrite existing data. Are you sure? (yes/no)"
read -r confirm
if [ "$confirm" != "yes" ]; then
    log_info "Restore cancelled"
    exit 0
fi

# 停止应用
log_info "Stopping application..."
docker-compose down

# 启动数据库
log_info "Starting database..."
docker-compose up -d postgres redis
sleep 5

# 恢复数据库
log_info "Restoring database..."
docker-compose exec -T postgres psql -U postgres -c "DROP DATABASE IF EXISTS discourse;"
docker-compose exec -T postgres psql -U postgres -c "CREATE DATABASE discourse OWNER discourse;"
docker-compose exec -T postgres psql -U discourse discourse < "${SQL_FILE}"

# 恢复上传文件
if [ -f "${UPLOADS_FILE}" ]; then
    log_info "Restoring uploads..."
    docker-compose run --rm app tar xzf - -C /var/www/discourse/public < "${UPLOADS_FILE}"
fi

# 恢复 Redis 数据
if [ -f "${REDIS_FILE}" ]; then
    log_info "Restoring Redis..."
    docker-compose run --rm redis tar xzf - -C /data < "${REDIS_FILE}"
fi

# 启动应用
log_info "Starting application..."
docker-compose up -d

log_info "Restore completed successfully!"
log_info "Please wait a few minutes for the application to fully start."
