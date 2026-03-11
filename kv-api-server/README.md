# KV API Server

基于 Python + Redis 的 KV 存储服务，兼容 Cloudflare KV API。

## 功能特性

- ✅ Redis 后端存储
- ✅ API 密钥认证 (双层认证)
- ✅ 兼容 Cloudflare KV 接口
- ✅ Systemd 服务管理
- ✅ 支持元数据 (metadata)
- ✅ 分页列表查询

## 快速开始

### 自动安装 (推荐)

在 Ubuntu/Debian 或 CentOS/RHEL 服务器上运行：

```bash
# 上传项目文件到服务器
scp -r kv-api-server/ root@your-server:/root/

# SSH 登录服务器
ssh root@your-server

# 进入目录并运行安装脚本
cd kv-api-server
chmod +x install.sh
./install.sh
```

安装脚本会自动：
- 安装 Python 3、Redis、systemd
- 配置 Redis 密码保护
- 创建 Python 虚拟环境
- 创建 systemd 服务
- 生成安全的随机密钥

### 手动安装

如果自动安装失败，可以手动安装：

```bash
# 1. 安装依赖
sudo apt install python3 python3-venv python3-pip redis-server -y  # Ubuntu/Debian
sudo yum install python3 python3-devel redis -y                      # CentOS/RHEL

# 2. 配置 Redis 密码
echo "requirepass your-password" | sudo tee -a /etc/redis/redis.conf
sudo systemctl restart redis

# 3. 创建虚拟环境
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# 4. 配置环境变量
cp .env.example .env
vim .env  # 修改配置

# 5. 启动服务
python main.py
```

## 配置

环境变量在 `/opt/kv-api-server/.env` 中配置：

```bash
# Redis 配置
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=your-password
REDIS_DB=0

# API 认证密钥
KV_API_KEY=your-api-key

# 服务端口
PORT=8000
```

## 服务管理

安装完成后使用 systemctl 管理：

```bash
# 查看状态
systemctl status kv-api

# 启动服务
systemctl start kv-api

# 停止服务
systemctl stop kv-api

# 重启服务
systemctl restart kv-api

# 查看日志
journalctl -u kv-api -f
```

## API 接口

所有接口需要在请求头中携带认证：
```
X-API-Key: your-api-key
```

### 保存键值
```http
PUT /kv/{key}?value=xxx&metadata={"key":"value"}
```

### 获取值
```http
GET /kv/{key}
```

### 获取值和元数据
```http
GET /kv/{key}/metadata
```

### 删除键
```http
DELETE /kv/{key}
```

### 列表查询
```http
GET /kv/list?limit=100&cursor=xxx&prefix=xxx
```

## 在 Telegraph-Image 项目中使用

将 `client-adapter.js` 复制到项目中，配置 API 地址和密钥：

```javascript
const KV_API_URL = "https://your-kv-api-domain.com";
const KV_API_KEY = "your-secret-api-key";
```

## 安全建议

1. **使用 HTTPS** - 配置 Nginx 反向代理 + SSL 证书
2. **防火墙** - 限制 API 端口的访问来源
3. **定期更新** - 保持系统和依赖包最新
4. **备份 Redis** - 定期备份 Redis 数据

## 卸载

```bash
cd kv-api-server
chmod +x uninstall.sh
./uninstall.sh
```

## 故障排查

```bash
# 查看服务状态
systemctl status kv-api

# 查看详细日志
journalctl -u kv-api -n 100 --no-pager

# 测试 Redis 连接
redis-cli -a your-password ping

# 测试 API 健康检查
curl http://localhost:8000/health
```
