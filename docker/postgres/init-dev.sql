-- 开发环境 PostgreSQL 初始化脚本

-- 创建测试数据库
CREATE DATABASE discourse_test;

-- 创建 discourse 用户（如果不存在）
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'discourse') THEN
        CREATE ROLE discourse WITH LOGIN PASSWORD 'discourse';
    END IF;
END
$$;

-- 授予权限
GRANT ALL PRIVILEGES ON DATABASE discourse_development TO discourse;
GRANT ALL PRIVILEGES ON DATABASE discourse_test TO discourse;

-- 设置 discourse 用户为超级用户（开发环境方便）
ALTER USER discourse WITH SUPERUSER;
