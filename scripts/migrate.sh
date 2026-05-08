#!/bin/bash
# Discourse 数据库迁移脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查数据库连接
log_info "Checking database connection..."
docker-compose exec app pg_isready -h postgres -U discourse || {
    log_error "Database is not ready. Please start the services first."
    exit 1
}

# 运行迁移
log_info "Running database migrations..."
docker-compose exec app bundle exec rake db:migrate

# 迁移插件
docker-compose exec app bundle exec rake plugin:migrate

log_info "Migration completed successfully!"
