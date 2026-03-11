#!/bin/bash

# KV API Server 安装脚本 (Python venv 部署)
# 支持: Ubuntu/Debian 和 CentOS/RHEL

set -e

# 配置变量
INSTALL_DIR="/opt/kv-api-server"
SERVICE_NAME="kv-api"
SERVICE_USER="kvapi"
VENV_DIR="$INSTALL_DIR/venv"
REDIS_PORT=6379
API_PORT=8000

echo "======================================"
echo "  KV API Server 安装脚本"
echo "  (Python venv 部署)"
echo "======================================"

# 检测操作系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "❌ 无法检测操作系统"
    exit 1
fi

echo "📦 检测到操作系统: $OS"

# 1. 安装系统依赖
echo ""
echo "📥 安装系统依赖..."

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get update
    apt-get install -y python3 python3-venv python3-pip redis-server curl

elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ]; then
    yum install -y python3 python3-devel
    # CentOS/RHEL 需要 EPEL 源来安装 redis
    yum install -y epel-release
    yum install -y redis curl
else
    echo "❌ 不支持的操作系统: $OS"
    exit 1
fi

echo "✅ 系统依赖安装完成"

# 2. 安装并配置 Redis
echo ""
echo "🔧 配置 Redis..."

# 生成随机密码
REDIS_PASSWORD=$(openssl rand -hex 16)

# 配置 Redis 密码
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    # Debian/Ubuntu 配置
    sed -i "s/^# requirepass.*/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
    sed -i "s/^bind 127.0.0.1.*/bind 127.0.0.1/" /etc/redis/redis.conf
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "rocky" ]; then
    # CentOS/RHEL 配置
    sed -i "s/^# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis.conf
    sed -i "s/^bind 127.0.0.1/bind 127.0.0.1/" /etc/redis.conf
fi

# 启动 Redis
systemctl enable redis
systemctl restart redis

echo "✅ Redis 配置完成"

# 3. 创建服务用户
echo ""
echo "👤 创建服务用户..."
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
    echo "✅ 用户 $SERVICE_USER 已创建"
else
    echo "✅ 用户 $SERVICE_USER 已存在"
fi

# 4. 创建安装目录
echo ""
echo "📁 创建安装目录..."
mkdir -p "$INSTALL_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# 5. 复制项目文件
echo ""
echo "📋 复制项目文件..."
cp main.py requirements.txt "$INSTALL_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# 6. 创建 Python 虚拟环境
echo ""
echo "🐍 创建 Python 虚拟环境..."
sudo -u "$SERVICE_USER" python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install -r "$INSTALL_DIR/requirements.txt"
deactivate

echo "✅ 虚拟环境创建完成"

# 7. 生成 API 密钥并创建环境变量文件
echo ""
echo "🔑 生成密钥..."
API_KEY=$(openssl rand -hex 32)

cat > "$INSTALL_DIR/.env" << EOF
# Redis 配置
REDIS_HOST=localhost
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_DB=0

# API 认证密钥
KV_API_KEY=$API_KEY

# 服务端口
PORT=$API_PORT
EOF

chmod 600 "$INSTALL_DIR/.env"
chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.env"

echo "✅ 环境变量文件已创建"

# 8. 创建 systemd 服务
echo ""
echo "⚙️  创建 systemd 服务..."

cat > "/etc/systemd/system/$SERVICE_NAME.service" << EOF
[Unit]
Description=KV API Server
After=network.target redis.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$VENV_DIR/bin"
EnvironmentFile=$INSTALL_DIR/.env
ExecStart=$VENV_DIR/bin/uvicorn main:app --host 0.0.0.0 --port \${PORT} --workers 2
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"

echo "✅ Systemd 服务已创建"

# 9. 启动服务
echo ""
echo "🚀 启动服务..."
systemctl start "$SERVICE_NAME"

# 10. 等待服务启动
echo "⏳ 等待服务启动..."
sleep 5

# 11. 健康检查
echo ""
echo "🔍 健康检查..."
if curl -s http://localhost:$API_PORT/health > /dev/null; then
    echo "✅ KV API 服务运行正常!"
else
    echo "❌ KV API 服务启动失败"
    systemctl status "$SERVICE_NAME"
    journalctl -u "$SERVICE_NAME" -n 50 --no-pager
    exit 1
fi

# 12. 配置防火墙（可选）
echo ""
read -p "是否需要开放防火墙端口 $API_PORT? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v ufw &> /dev/null; then
        ufw allow "$API_PORT/tcp"
        echo "✅ UFW 防火墙规则已添加"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port="$API_PORT/tcp"
        firewall-cmd --reload
        echo "✅ Firewalld 防火墙规则已添加"
    else
        echo "⚠️  未检测到防火墙，请手动开放端口 $API_PORT"
    fi
fi

echo ""
echo "======================================"
echo "  安装完成!"
echo "======================================"
echo ""
echo "📍 服务地址: http://localhost:$API_PORT"
echo "📚 API 文档: http://localhost:$API_PORT/docs"
echo ""
echo "🔑 重要信息 (请妥善保存!):"
echo "   Redis 密码: $REDIS_PASSWORD"
echo "   API 密钥: $API_KEY"
echo ""
echo "📝 常用命令:"
echo "   查看状态: systemctl status $SERVICE_NAME"
echo "   查看日志: journalctl -u $SERVICE_NAME -f"
echo "   重启服务: systemctl restart $SERVICE_NAME"
echo "   停止服务: systemctl stop $SERVICE_NAME"
echo ""
echo "⚠️  安全建议:"
echo "   1. 配置 Nginx 反向代理 + HTTPS"
echo "   2. 使用防火墙限制访问来源"
echo "   3. 定期更新系统和依赖"
echo "======================================"
