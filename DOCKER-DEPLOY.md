# Discourse Docker 统一部署方案

这是一个统一的 Docker Compose 编排方案，解决了原项目部署分散、迁移困难的问题。

## 架构概览

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Compose                            │
│                                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐              │
│  │   Nginx     │  │  Discourse  │  │   Sidekiq   │              │
│  │  (Reverse)  │  │    (App)    │  │  (Worker)   │              │
│  └──────┬──────┘  └──────┬──────┘  └─────────────┘              │
│         │                │                                       │
│         └────────────────┘                                       │
│                  │                                               │
│         ┌────────┴────────┐                                      │
│         │                 │                                      │
│  ┌──────┴──────┐   ┌──────┴──────┐                              │
│  │  PostgreSQL │   │    Redis    │                              │
│  │  (Database) │   │   (Cache)   │                              │
│  └─────────────┘   └─────────────┘                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## 文件结构

```
.
├── docker-compose.yml                    # 基础配置
├── docker-compose.prod.yml               # 生产环境扩展
├── docker-compose.dev.yml                # 开发环境扩展
├── docker-compose.test.yml               # 测试环境扩展
├── Dockerfile                            # 多阶段构建文件
├── .env.example                          # 环境变量示例
├── docker/
│   ├── entrypoint.sh                     # 容器入口脚本
│   ├── nginx/
│   │   ├── nginx.conf                    # Nginx 主配置
│   │   └── discourse.conf                # Discourse 站点配置
│   └── postgres/
│       └── init-dev.sql                  # 开发环境初始化脚本
├── scripts/
│   ├── setup.sh                          # 一键安装脚本
│   ├── backup.sh                         # 数据备份脚本
│   ├── restore.sh                        # 数据恢复脚本
│   └── migrate.sh                        # 数据库迁移脚本
└── .github/workflows/
    ├── docker-build.yml                  # 自动构建工作流
    └── docker-build-manual.yml           # 手动构建工作流
```

## 快速开始

### 1. 环境准备

确保已安装：
- Docker 20.10+
- Docker Compose 2.0+

### 2. 配置环境变量

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置
vim .env
```

### 3. 一键安装

```bash
# 完整安装（推荐）
./scripts/setup.sh

# 或分步执行
./scripts/setup.sh env      # 仅创建环境配置
./scripts/setup.sh build    # 仅构建镜像
./scripts/setup.sh db       # 仅初始化数据库
```

---

## 环境使用指南

### 开发环境

```bash
# 启动开发环境
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# 查看日志
docker-compose logs -f app

# 进入 Rails 控制台
docker-compose exec app bundle exec rails console

# 运行数据库迁移
docker-compose exec app bundle exec rake db:migrate

# 安装新依赖
docker-compose exec app bundle install
docker-compose exec app pnpm install
```

**开发环境特性：**
- 代码热重载（bind mount）
- MailHog 邮件测试 (http://localhost:8025)
- 数据库和 Redis 端口暴露
- Ember CLI 开发服务器（可选）
- Chrome 浏览器用于系统测试（可选）

### 生产环境

```bash
# 启动生产环境
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# 查看状态
docker-compose ps

# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 停止服务
docker-compose down
```

**生产环境特性：**
- Nginx 反向代理
- 自动 SSL（需配置证书）
- 资源限制
- 健康检查
- 自动备份服务（可选）

### 测试环境

```bash
# 运行完整测试套件
docker-compose -f docker-compose.yml -f docker-compose.test.yml up --abort-on-container-exit

# 仅运行 Lint
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile lint run --rm lint

# 仅运行 RSpec
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile rspec run --rm rspec

# 仅运行 QUnit
docker-compose -f docker-compose.yml -f docker-compose.test.yml --profile qunit run --rm qunit

# 使用 Turbo 并行测试
USE_TURBO=1 docker-compose -f docker-compose.yml -f docker-compose.test.yml up
```

---

## 数据管理

### 备份数据

```bash
# 创建备份
./scripts/backup.sh

# 备份包含：
# - PostgreSQL 数据库
# - 上传的文件
# - Redis 数据
```

### 恢复数据

```bash
# 查看可用备份
ls backups/

# 恢复指定备份
./scripts/restore.sh discourse_backup_20240115_120000
```

### 数据库迁移

```bash
# 运行迁移
./scripts/migrate.sh

# 或手动执行
docker-compose exec app bundle exec rake db:migrate
docker-compose exec app bundle exec rake plugin:migrate
```

---

## 环境变量说明

| 变量名 | 说明 | 默认值 | 必需 |
|--------|------|--------|------|
| `DISCOURSE_HOSTNAME` | 应用主机名 | localhost | 是 |
| `DISCOURSE_SECRET_KEY_BASE` | 安全密钥 | - | 生产环境 |
| `DISCOURSE_DB_PASSWORD` | 数据库密码 | discourse_password | 生产环境 |
| `DISCOURSE_REDIS_PASSWORD` | Redis 密码 | - | 否 |
| `DISCOURSE_SMTP_ADDRESS` | SMTP 服务器 | - | 否 |
| `DISCOURSE_SMTP_PORT` | SMTP 端口 | 587 | 否 |
| `DISCOURSE_SMTP_USER_NAME` | SMTP 用户名 | - | 否 |
| `DISCOURSE_SMTP_PASSWORD` | SMTP 密码 | - | 否 |
| `UNICORN_WORKERS` | Worker 数量 | 4 | 否 |
| `UNICORN_SIDEKIQS` | Sidekiq 实例数 | 1 | 否 |

---

## 多环境对比

| 特性 | 开发环境 | 测试环境 | 生产环境 |
|------|----------|----------|----------|
| 代码挂载 | ✅ | ✅ | ❌ |
| 热重载 | ✅ | ❌ | ❌ |
| MailHog | ✅ | ❌ | ❌ |
| Nginx | ❌ | ❌ | ✅ |
| SSL | ❌ | ❌ | ✅ |
| 资源限制 | ❌ | ❌ | ✅ |
| 健康检查 | ❌ | ❌ | ✅ |
| 自动备份 | ❌ | ❌ | ✅ |

---

## 故障排查

### 查看日志

```bash
# 所有服务
docker-compose logs -f

# 特定服务
docker-compose logs -f app
docker-compose logs -f postgres
docker-compose logs -f sidekiq
```

### 进入容器

```bash
# 进入应用容器
docker-compose exec app bash

# 进入数据库
docker-compose exec postgres psql -U discourse

# 进入 Redis
docker-compose exec redis redis-cli
```

### 重启服务

```bash
# 重启所有
docker-compose restart

# 重启特定服务
docker-compose restart app
docker-compose restart sidekiq
```

### 清理数据

```bash
# 停止并删除容器
docker-compose down

# 停止并删除容器和数据卷（⚠️ 数据丢失）
docker-compose down -v

# 删除所有未使用的数据
docker system prune -a
```

---

## 迁移指南

### 从旧版本迁移

1. **备份现有数据**
   ```bash
   ./scripts/backup.sh
   ```

2. **停止旧服务**
   ```bash
   cd /var/discourse
   ./launcher stop app
   ```

3. **部署新方案**
   ```bash
   cd /path/to/new/discourse
   ./scripts/setup.sh
   ```

4. **恢复数据**
   ```bash
   ./scripts/restore.sh <backup_name>
   ```

---

## 高级配置

### 配置 SSL 证书

1. 将证书放入 `docker/nginx/ssl/` 目录：
   ```
   docker/nginx/ssl/
   ├── fullchain.pem
   └── privkey.pem
   ```

2. 修改 `docker/nginx/discourse.conf` 添加 HTTPS 配置

### 配置 CDN

在 `.env` 文件中添加：
```bash
DISCOURSE_CDN_URL=https://cdn.example.com
```

### 配置 S3 存储

在 `.env` 文件中添加：
```bash
DISCOURSE_S3_BUCKET=your-bucket
DISCOURSE_S3_REGION=us-east-1
DISCOURSE_S3_ACCESS_KEY_ID=your-key
DISCOURSE_S3_SECRET_ACCESS_KEY=your-secret
```

---

## GitHub Container Registry

本项目使用 GitHub Actions 自动构建并推送 Docker 镜像到 GitHub Container Registry (GHCR)。

### 自动构建触发条件

- **Push 到 main/develop 分支**: 构建并推送 `latest` 标签
- **Push 标签 (v*)**: 构建并推送版本标签 (如 `v1.2.3`, `v1.2`, `v1`)
- **Pull Request**: 仅构建，不推送

### 镜像标签策略

| 事件 | 生成的标签 |
|------|-----------|
| Push to main | `latest`, `main`, `<sha>` |
| Push to develop | `develop`, `<sha>` |
| Push tag v1.2.3 | `v1.2.3`, `v1.2`, `v1` |
| Pull Request | `pr-<number>` |

### 镜像类型

| 目标 | 标签后缀 | 说明 |
|------|---------|------|
| production | 无 | 生产环境镜像 |
| development | `-dev` | 开发环境镜像 |
| test | `-test` | 测试环境镜像 |

### 使用预构建镜像

```bash
# 生产环境
docker pull ghcr.io/hipm-tech/discourse:latest

# 开发环境
docker pull ghcr.io/hipm-tech/discourse:latest-dev

# 测试环境
docker pull ghcr.io/hipm-tech/discourse:latest-test

# 特定版本
docker pull ghcr.io/hipm-tech/discourse:v1.2.3
```

### 配置 docker-compose 使用 GHCR 镜像

编辑 `.env` 文件：
```bash
DISCOURSE_IMAGE=ghcr.io/hipm-tech/discourse:latest
```

然后启动：
```bash
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### 手动触发构建

1. 进入 GitHub 仓库的 Actions 页面
2. 选择 "Docker Build Manual" 工作流
3. 点击 "Run workflow"
4. 选择参数：
   - **Build target**: production/development/test/all
   - **Target platforms**: amd64/arm64/both
   - **Push to registry**: 是否推送到仓库
   - **Additional tags**: 额外标签（可选）

### 安全扫描

每次构建后，会自动使用 Trivy 扫描镜像漏洞：
- 扫描结果上传到 GitHub Security tab
- 仅报告 CRITICAL 和 HIGH 级别漏洞
- 不影响构建流程

---

## 贡献

欢迎提交 Issue 和 PR 改进这个部署方案。

## 许可证

与 Discourse 主项目保持一致，采用 GPL v2 许可证。
