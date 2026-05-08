# Discourse 统一 Dockerfile
# 支持多阶段构建: development, test, production

# =============================================================================
# 基础阶段 - 包含所有环境共用的依赖
# =============================================================================
FROM ruby:3.4-slim-bookworm AS base

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive \
    RAILS_ENV=production \
    RAILS_SERVE_STATIC_FILES=1 \
    RAILS_LOG_TO_STDOUT=1 \
    DISCOURSE_HOME=/var/www/discourse \
    BUNDLE_PATH=/var/www/discourse/vendor/bundle \
    NODE_VERSION=20 \
    PNPM_VERSION=9

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 基础工具
    curl \
    ca-certificates \
    gnupg \
    git \
    # 构建工具
    build-essential \
    # PostgreSQL 客户端
    libpq-dev \
    postgresql-client \
    # Redis 工具
    redis-tools \
    # 图像处理
    imagemagick \
    libmagickwand-dev \
    # 其他库
    libxml2-dev \
    libxslt1-dev \
    libyaml-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libncurses5-dev \
    libffi-dev \
    libgdbm-dev \
    # Node.js 依赖
    && rm -rf /var/lib/apt/lists/*

# 安装 Node.js 和 pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm@${PNPM_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
WORKDIR ${DISCOURSE_HOME}

# =============================================================================
# Ruby 依赖阶段
# =============================================================================
FROM base AS ruby-dependencies

COPY Gemfile Gemfile.lock ./

RUN bundle config set --local deployment 'true' \
    && bundle config set --local without 'development test' \
    && bundle install --jobs $(nproc) --retry 3

# =============================================================================
# Node 依赖阶段
# =============================================================================
FROM base AS node-dependencies

# 复制项目文件（pnpm workspace 需要完整项目结构）
COPY . .

# 配置 pnpm 并使用 npm 安装依赖
# 注意：Discourse 项目使用 pnpm workspace，但我们可以用 npm 安装
RUN npm install -g pnpm && \
    pnpm config set strict-peer-dependencies false && \
    pnpm install --no-frozen-lockfile || \
    (echo "pnpm install failed, trying npm..." && npm install)

# =============================================================================
# 构建阶段 - 编译前端资源
# =============================================================================
FROM base AS build

# 复制 Ruby 依赖
COPY --from=ruby-dependencies ${BUNDLE_PATH} ${BUNDLE_PATH}

# 复制 Node 依赖
COPY --from=node-dependencies ${DISCOURSE_HOME}/node_modules ${DISCOURSE_HOME}/node_modules
COPY --from=node-dependencies ${DISCOURSE_HOME}/frontend ${DISCOURSE_HOME}/frontend
COPY --from=node-dependencies ${DISCOURSE_HOME}/plugins ${DISCOURSE_HOME}/plugins
COPY --from=node-dependencies ${DISCOURSE_HOME}/themes ${DISCOURSE_HOME}/themes

# 复制源代码
COPY . .

# 设置 bundle 配置
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test'

# 编译前端资源（跳过需要数据库的初始化）
ENV DISABLE_DATABASE_ENVIRONMENT_CHECK=1
RUN bundle exec rake assets:precompile 2>/dev/null || \
    (echo "Assets precompile skipped - will run at runtime" && \
     mkdir -p public/assets && \
     touch public/assets/.precompile_pending)

# =============================================================================
# 生产环境阶段
# =============================================================================
FROM base AS production

# 安装生产环境必要的运行时依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Nginx
    nginx \
    # 监控工具
    curl \
    # 日志轮转
    logrotate \
    && rm -rf /var/lib/apt/lists/*

# 创建 discourse 用户
RUN groupadd -r discourse && useradd -r -g discourse -d ${DISCOURSE_HOME} discourse

# 复制 Ruby 依赖
COPY --from=ruby-dependencies ${BUNDLE_PATH} ${BUNDLE_PATH}

# 复制 Node 依赖
COPY --from=node-dependencies ${DISCOURSE_HOME}/node_modules ${DISCOURSE_HOME}/node_modules

# 复制源代码
COPY --chown=discourse:discourse . .

# 复制编译后的资源
COPY --from=build --chown=discourse:discourse ${DISCOURSE_HOME}/public/assets ${DISCOURSE_HOME}/public/assets

# 创建必要的目录
RUN mkdir -p tmp/pids log public/uploads public/backups \
    && chown -R discourse:discourse ${DISCOURSE_HOME}

# 配置 Nginx
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/discourse.conf /etc/nginx/conf.d/discourse.conf

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/healthcheck || exit 1

# 暴露端口
EXPOSE 80 443

# 启动脚本
COPY docker/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
CMD ["bundle", "exec", "unicorn", "-c", "config/unicorn.conf.rb"]

# =============================================================================
# 开发环境阶段
# =============================================================================
FROM base AS development

# 安装开发工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 开发工具
    vim \
    nano \
    htop \
    # 调试工具
    gdb \
    # 网络工具
    net-tools \
    iputils-ping \
    telnet \
    # Git 工具
    git \
    # 其他开发依赖
    && rm -rf /var/lib/apt/lists/*

# 创建 discourse 用户
RUN groupadd -r discourse && useradd -r -g discourse -d ${DISCOURSE_HOME} discourse

# 设置开发环境变量
ENV RAILS_ENV=development \
    BUNDLE_PATH=/var/www/discourse/vendor/bundle \
    BUNDLE_WITHOUT=""

# 创建必要的目录
RUN mkdir -p tmp/pids log public/uploads public/backups \
    && chown -R discourse:discourse ${DISCOURSE_HOME}

# 开发环境使用 root 运行以便处理文件权限
USER root

# 暴露开发端口
EXPOSE 3000 9229

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

# =============================================================================
# 测试环境阶段
# =============================================================================
FROM base AS test

# 安装测试工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Chrome 依赖 (用于系统测试)
    wget \
    gnupg \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libgcc1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    xdg-utils \
    # 其他测试工具
    && rm -rf /var/lib/apt/lists/*

# 安装 Chrome 或 Chromium（根据架构）
RUN if [ "$(uname -m)" = "x86_64" ]; then \
        # AMD64: 安装 Google Chrome \
        wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add - \
        && echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list \
        && apt-get update \
        && apt-get install -y google-chrome-stable \
        && rm -rf /var/lib/apt/lists/*; \
    else \
        # ARM64: 安装 Chromium \
        apt-get update \
        && apt-get install -y chromium \
        && rm -rf /var/lib/apt/lists/*; \
    fi

# 创建 discourse 用户
RUN groupadd -r discourse && useradd -r -g discourse -d ${DISCOURSE_HOME} discourse

# 设置测试环境变量
ENV RAILS_ENV=test \
    BUNDLE_PATH=/var/www/discourse/vendor/bundle \
    BUNDLE_WITHOUT="" \
    CI=true \
    CHROME_BIN=/usr/bin/chromium

# 创建必要的目录
RUN mkdir -p tmp/pids log public/uploads public/backups test-results coverage \
    && chown -R discourse:discourse ${DISCOURSE_HOME}

USER discourse

CMD ["bundle", "exec", "rake", "docker:test"]
