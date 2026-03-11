#!/bin/bash

# KV API Server 卸载脚本

set -e

SERVICE_NAME="kv-api"
SERVICE_USER="kvapi"
INSTALL_DIR="/opt/kv-api-server"

echo "======================================"
echo "  KV API Server 卸载脚本"
echo "======================================"

echo ""
read -p "确定要卸载 KV API Server 吗? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "取消卸载"
    exit 0
fi

# 1. 停止并禁用服务
echo ""
echo "🛑 停止服务..."
if systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl stop "$SERVICE_NAME"
fi
if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    systemctl disable "$SERVICE_NAME"
fi
echo "✅ 服务已停止"

# 2. 删除 systemd 服务文件
echo ""
echo "🗑️  删除服务文件..."
rm -f "/etc/systemd/system/$SERVICE_NAME.service"
systemctl daemon-reload
echo "✅ 服务文件已删除"

# 3. 询问是否删除用户
echo ""
read -p "是否删除服务用户 $SERVICE_USER? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    userdel -r "$SERVICE_USER" 2>/dev/null || true
    echo "✅ 用户已删除"
else
    echo "⏭️  跳过删除用户"
fi

# 4. 询问是否删除安装目录
echo ""
read -p "是否删除安装目录 $INSTALL_DIR? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR"
    echo "✅ 安装目录已删除"
else
    echo "⏭️  跳过删除安装目录"
fi

# 5. 询问是否重置 Redis 配置
echo ""
read -p "是否重置 Redis 密码配置? (将删除密码保护) (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f /etc/redis/redis.conf ]; then
        sed -i 's/^requirepass.*/# requirepass foobared/' /etc/redis/redis.conf
        systemctl restart redis
        echo "✅ Redis 配置已重置"
    elif [ -f /etc/redis.conf ]; then
        sed -i 's/^requirepass.*/# requirepass foobared/' /etc/redis.conf
        systemctl restart redis
        echo "✅ Redis 配置已重置"
    fi
else
    echo "⏭️  跳过 Redis 配置重置"
fi

echo ""
echo "======================================"
echo "  卸载完成!"
echo "======================================"
