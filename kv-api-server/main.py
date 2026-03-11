"""
KV API Server - Python + Redis
提供兼容 Cloudflare KV 的 HTTP API 接口
"""
import json
import hashlib
import os
import uuid
from typing import Optional, Any
from dataclasses import dataclass, asdict

from fastapi import FastAPI, HTTPException, Header, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import redis.asyncio as redis
from redis.asyncio import Redis


# ============== 配置 ==============
# Redis 配置
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", None)
REDIS_DB = int(os.getenv("REDIS_DB", 0))

# API 认证密钥 (建议通过环境变量设置)
API_KEY = os.getenv("KV_API_KEY", "your-secret-api-key-change-this")

# 数据前缀 (防止键冲突)
KEY_PREFIX = "kv:"


# ============== 数据模型 ==============
@dataclass
class KVRecord:
    """KV 记录结构"""
    value: str
    metadata: dict

    def to_json(self) -> str:
        return json.dumps(asdict(self))

    @classmethod
    def from_json(cls, json_str: str) -> 'KVRecord':
        data = json.loads(json_str)
        return cls(**data)


class KVListResponse(BaseModel):
    """KV 列表响应"""
    keys: list[dict]
    list_complete: bool
    cursor: Optional[str] = None


# ============== Redis 连接池 ==============
redis_pool: Redis = None


async def get_redis() -> Redis:
    """获取 Redis 连接"""
    global redis_pool
    if redis_pool is None:
        redis_pool = redis.Redis(
            host=REDIS_HOST,
            port=REDIS_PORT,
            password=REDIS_PASSWORD,
            db=REDIS_DB,
            ssl=REDIS_SSL,
            decode_responses=True
        )
    return redis_pool


# ============== FastAPI 应用 ==============
app = FastAPI(
    title="KV API Server",
    description="Cloudflare KV compatible API with Redis backend",
    version="1.0.0"
)


# ============== 认证中间件 ==============
async def verify_api_key(x_api_key: str = Header(..., alias="X-API-Key")):
    """验证 API 密钥"""
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return x_api_key


# ============== 辅助函数 ==============
def make_redis_key(key: str) -> str:
    """添加前缀防止键冲突"""
    return f"{KEY_PREFIX}{key}"


def strip_prefix(key: str) -> str:
    """移除前缀"""
    if key.startswith(KEY_PREFIX):
        return key[len(KEY_PREFIX):]
    return key


def encode_cursor(data: dict) -> str:
    """编码游标"""
    return hashlib.sha256(json.dumps(data, sort_keys=True).encode()).hexdigest()[:16]


def decode_cursor(cursor: Optional[str]) -> Optional[dict]:
    """简单游标处理 (实际项目中应该用更安全的方式)"""
    # 这里简化处理，实际应该存储游标信息到 Redis
    # 为了演示，我们返回 None，游标功能将在实际实现中用 Redis 存储游标信息
    return None


# ============== KV API 接口 ==============

@app.get("/health")
async def health_check():
    """健康检查"""
    return {"status": "ok", "redis": "connected"}


@app.put("/kv/{key:path}")
async def put_kv(
    key: str,
    value: str = "",
    metadata: Optional[dict] = None,
    x_api_key: str = Header(..., alias="X-API-Key")
):
    """
    保存或更新 KV 键值

    兼容: env.img_url.put(key, value, { metadata })
    """
    await verify_api_key(x_api_key)

    client = await get_redis()
    record = KVRecord(
        value=value,
        metadata=metadata or {}
    )

    redis_key = make_redis_key(key)
    await client.set(redis_key, record.to_json())

    return {"success": True, "key": key}


@app.get("/kv/{key:path}")
async def get_kv(
    key: str,
    x_api_key: str = Header(..., alias="X-API-Key")
):
    """
    获取 KV 值

    兼容: env.img_url.get(key)
    """
    await verify_api_key(x_api_key)

    client = await get_redis()
    redis_key = make_redis_key(key)
    data = await client.get(redis_key)

    if data is None:
        raise HTTPException(status_code=404, detail="Key not found")

    record = KVRecord.from_json(data)
    return record.value


@app.get("/kv/{key:path}/metadata")
async def get_kv_with_metadata(
    key: str,
    x_api_key: str = Header(..., alias="X-API-Key")
):
    """
    获取 KV 值和元数据

    兼容: env.img_url.getWithMetadata(key)
    """
    await verify_api_key(x_api_key)

    client = await get_redis()
    redis_key = make_redis_key(key)
    data = await client.get(redis_key)

    if data is None:
        return None

    record = KVRecord.from_json(data)
    return {
        "value": record.value,
        "metadata": record.metadata
    }


@app.delete("/kv/{key:path}")
async def delete_kv(
    key: str,
    x_api_key: str = Header(..., alias="X-API-Key")
):
    """
    删除 KV 键

    兼容: env.img_url.delete(key)
    """
    await verify_api_key(x_api_key)

    client = await get_redis()
    redis_key = make_redis_key(key)
    result = await client.delete(redis_key)

    return {"success": True, "deleted": result > 0}


@app.get("/kv/list")
async def list_kv(
    limit: int = 100,
    cursor: Optional[str] = None,
    prefix: Optional[str] = None,
    x_api_key: str = Header(..., alias="X-API-Key")
):
    """
    列出 KV 键 (分页)

    兼容: env.img_url.list({ limit, cursor, prefix })
    """
    await verify_api_key(x_api_key)

    # 参数验证
    if limit <= 0:
        limit = 100
    if limit > 1000:
        limit = 1000

    client = await get_redis()

    # 构建搜索模式
    search_pattern = f"{KEY_PREFIX}{prefix or ''}*"

    # 使用 SCAN 获取匹配的键
    all_keys = []
    async for key in client.scan_iter(match=search_pattern, count=100):
        all_keys.append(strip_prefix(key))

    # 排序（保持一致性）
    all_keys.sort()

    # 处理游标分页
    start_idx = 0
    if cursor:
        # 从 Redis 获取游标位置
        cursor_data = await client.get(f"cursor:{cursor}")
        if cursor_data:
            start_idx = int(json.loads(cursor_data).get("offset", 0))

    # 获取分页数据
    keys = all_keys[start_idx:start_idx + limit]

    # 获取每个键的完整数据
    keys_data = []
    for key in keys:
        redis_key = make_redis_key(key)
        data = await client.get(redis_key)
        if data:
            record = KVRecord.from_json(data)
            keys_data.append({
                "name": key,
                "metadata": record.metadata
            })

    # 判断是否还有更多数据
    list_complete = len(all_keys) <= start_idx + limit

    # 生成新的游标
    next_cursor = None
    if not list_complete:
        next_cursor = str(uuid.uuid4())[:16]
        # 存储游标位置（设置 1 小时过期）
        await client.setex(
            f"cursor:{next_cursor}",
            3600,
            json.dumps({"offset": start_idx + limit})
        )

    return KVListResponse(
        keys=keys_data,
        list_complete=list_complete,
        cursor=next_cursor
    )


@app.on_event("startup")
async def startup():
    """启动时检查 Redis 连接"""
    try:
        client = await get_redis()
        await client.ping()
        print("✅ Redis 连接成功")
    except Exception as e:
        print(f"❌ Redis 连接失败: {e}")


@app.on_event("shutdown")
async def shutdown():
    """关闭时清理连接"""
    global redis_pool
    if redis_pool:
        await redis_pool.close()
        print("Redis 连接已关闭")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )
