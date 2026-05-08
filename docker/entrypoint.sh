#!/bin/bash
set -e

# Discourse Docker 入口脚本
# 支持多种启动模式

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 等待数据库就绪
wait_for_db() {
    log_info "Waiting for database..."
    until pg_isready -h "${DISCOURSE_DB_HOST:-postgres}" -p "${DISCOURSE_DB_PORT:-5432}" -U "${DISCOURSE_DB_USERNAME:-discourse}" > /dev/null 2>&1; do
        sleep 1
    done
    log_info "Database is ready!"
}

# 等待 Redis 就绪
wait_for_redis() {
    log_info "Waiting for Redis..."
    until redis-cli -h "${DISCOURSE_REDIS_HOST:-redis}" -p "${DISCOURSE_REDIS_PORT:-6379}" ping > /dev/null 2>&1; do
        sleep 1
    done
    log_info "Redis is ready!"
}

# 初始化数据库
init_database() {
    log_info "Initializing database..."
    
    # 创建数据库（如果不存在）
    bundle exec rake db:create 2>/dev/null || true
    
    # 运行迁移
    bundle exec rake db:migrate
    
    # 种子数据（仅在开发环境）
    if [ "$RAILS_ENV" = "development" ]; then
        bundle exec rake db:seed 2>/dev/null || true
    fi
    
    log_info "Database initialization complete!"
}

# 编译前端资源
precompile_assets() {
    if [ "$RAILS_ENV" = "production" ]; then
        # 检查是否需要编译资源
        if [ -f "public/assets/.precompile_pending" ] || [ ! -d "public/assets" ] || [ -z "$(ls -A public/assets 2>/dev/null)" ]; then
            log_info "Precompiling assets..."
            bundle exec rake assets:precompile
            rm -f public/assets/.precompile_pending
            log_info "Asset precompilation complete!"
        else
            log_info "Assets already precompiled, skipping..."
        fi
    fi
}

# 启动 Nginx (生产环境)
start_nginx() {
    if [ "$RAILS_ENV" = "production" ]; then
        log_info "Starting Nginx..."
        nginx
    fi
}

# 主逻辑
case "${1:-}" in
    web)
        wait_for_db
        wait_for_redis
        init_database
        precompile_assets
        start_nginx
        log_info "Starting Unicorn web server..."
        exec bundle exec unicorn -c config/unicorn.conf.rb
        ;;
    
    sidekiq)
        wait_for_db
        wait_for_redis
        log_info "Starting Sidekiq..."
        exec bundle exec sidekiq -c 10 -q critical -q low -q default
        ;;
    
    migrate)
        wait_for_db
        log_info "Running database migrations..."
        exec bundle exec rake db:migrate
        ;;
    
    console)
        wait_for_db
        wait_for_redis
        log_info "Starting Rails console..."
        exec bundle exec rails console
        ;;
    
    backup)
        wait_for_db
        log_info "Creating backup..."
        exec bundle exec rake db:backup
        ;;
    
    restore)
        wait_for_db
        if [ -z "$2" ]; then
            log_error "Usage: entrypoint.sh restore <backup_file>"
            exit 1
        fi
        log_info "Restoring from backup: $2"
        exec bundle exec rake db:restore["$2"]
        ;;
    
    test)
        wait_for_db
        wait_for_redis
        log_info "Running tests..."
        exec bundle exec rake docker:test
        ;;
    
    bash|shell|sh)
        log_info "Starting shell..."
        exec /bin/bash
        ;;
    
    *)
        # 默认行为：根据 RAILS_ENV 启动相应服务
        wait_for_db
        wait_for_redis
        init_database
        precompile_assets
        
        if [ "$RAILS_ENV" = "production" ]; then
            start_nginx
            log_info "Starting Unicorn..."
            exec bundle exec unicorn -c config/unicorn.conf.rb
        else
            log_info "Starting Rails server..."
            exec bundle exec rails server -b 0.0.0.0 -p 3000
        fi
        ;;
esac
