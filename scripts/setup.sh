#!/bin/bash
# Discourse Docker 环境初始化脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "\n${BLUE}[STEP]${NC} $1"
}

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi

    log_info "Docker and Docker Compose are installed"
}

# 创建环境文件
setup_env() {
    log_step "Setting up environment configuration..."
    
    if [ ! -f .env ]; then
        cp .env.example .env
        log_info "Created .env file from .env.example"
        log_warn "Please edit .env file with your configuration before continuing"
        
        # 生成安全密钥
        SECRET_KEY=$(openssl rand -hex 64 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 128 | head -n 1)
        sed -i.bak "s/change_me_in_production.*/${SECRET_KEY}/" .env && rm -f .env.bak
        log_info "Generated SECRET_KEY_BASE"
    else
        log_warn ".env file already exists, skipping..."
    fi
}

# 创建必要目录
setup_directories() {
    log_step "Creating necessary directories..."
    
    mkdir -p backups
    mkdir -p docker/nginx/ssl
    
    log_info "Directories created"
}

# 构建镜像
build_images() {
    log_step "Building Docker images..."
    
    docker-compose build
    
    log_info "Docker images built successfully"
}

# 初始化数据库
init_database() {
    log_step "Initializing database..."
    
    docker-compose up -d postgres redis
    sleep 5
    
    docker-compose run --rm app bundle exec rake db:create db:migrate
    
    log_info "Database initialized"
}

# 预编译资源
precompile_assets() {
    log_step "Precompiling assets..."
    
    docker-compose run --rm app bundle exec rake assets:precompile
    
    log_info "Assets precompiled"
}

# 启动服务
start_services() {
    log_step "Starting services..."
    
    docker-compose up -d
    
    log_info "Services started"
}

# 显示状态
show_status() {
    log_step "Setup complete!"
    
    echo ""
    echo "========================================"
    echo "Discourse is now running!"
    echo "========================================"
    echo ""
    echo "Access your forum at:"
    echo "  - Local: http://localhost:${DISCOURSE_HTTP_PORT:-3000}"
    echo ""
    echo "Useful commands:"
    echo "  - View logs: docker-compose logs -f"
    echo "  - Stop: docker-compose down"
    echo "  - Restart: docker-compose restart"
    echo "  - Rails console: docker-compose exec app bundle exec rails console"
    echo "  - Database backup: ./scripts/backup.sh"
    echo ""
    echo "========================================"
}

# 主流程
main() {
    echo "========================================"
    echo "Discourse Docker Setup"
    echo "========================================"
    
    check_docker
    setup_env
    setup_directories
    build_images
    init_database
    precompile_assets
    start_services
    show_status
}

# 根据参数执行不同操作
case "${1:-}" in
    env)
        setup_env
        ;;
    build)
        build_images
        ;;
    db)
        init_database
        ;;
    assets)
        precompile_assets
        ;;
    start)
        start_services
        ;;
    *)
        main
        ;;
esac
