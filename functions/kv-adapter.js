/**
 * KV 适配器
 * 支持 Cloudflare KV 和自建 KV API 双模式
 *
 * 环境变量配置:
 * - KV_API_URL: 自建 KV API 地址 (如: http://localhost:8000)
 * - KV_API_KEY: 自建 KV API 密钥
 *
 * 如果设置了 KV_API_URL，使用自建 KV API；否则使用 Cloudflare KV
 */

class KVAdapter {
    constructor(env) {
        this.env = env;
        this.useRemoteKV = !!(env.KV_API_URL && env.KV_API_KEY);
        this.apiUrl = env.KV_API_URL;
        this.apiKey = env.KV_API_KEY;
    }

    /**
     * 保存键值
     */
    async put(key, value, options = {}) {
        if (!this.useRemoteKV) {
            // 使用 Cloudflare KV
            return await this.env.img_url.put(key, value, options);
        }

        // 使用自建 KV API
        const url = new URL(`${this.apiUrl}/kv/${key}`);
        if (value !== undefined && value !== "") {
            url.searchParams.append("value", value);
        }

        const headers = {
            "X-API-Key": this.apiKey,
            "Content-Type": "application/json"
        };

        let body = undefined;
        if (options.metadata) {
            body = JSON.stringify({ metadata: options.metadata });
        }

        const response = await fetch(url.toString(), {
            method: "PUT",
            headers,
            body
        });

        if (!response.ok) {
            throw new Error(`KV put failed: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }

    /**
     * 获取值
     */
    async get(key) {
        if (!this.useRemoteKV) {
            return await this.env.img_url.get(key);
        }

        const response = await fetch(`${this.apiUrl}/kv/${key}`, {
            headers: { "X-API-Key": this.apiKey }
        });

        if (!response.ok) {
            if (response.status === 404) return null;
            throw new Error(`KV get failed: ${response.status} ${response.statusText}`);
        }
        return await response.text();
    }

    /**
     * 获取值和元数据
     */
    async getWithMetadata(key) {
        if (!this.useRemoteKV) {
            return await this.env.img_url.getWithMetadata(key);
        }

        const response = await fetch(`${this.apiUrl}/kv/${key}/metadata`, {
            headers: { "X-API-Key": this.apiKey }
        });

        if (!response.ok) {
            if (response.status === 404) return null;
            throw new Error(`KV getWithMetadata failed: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();
        // 兼容 Cloudflare KV 的返回格式
        return {
            value: data.value,
            metadata: data.metadata
        };
    }

    /**
     * 删除键
     */
    async delete(key) {
        if (!this.useRemoteKV) {
            return await this.env.img_url.delete(key);
        }

        const response = await fetch(`${this.apiUrl}/kv/${key}`, {
            method: "DELETE",
            headers: { "X-API-Key": this.apiKey }
        });

        if (!response.ok) {
            throw new Error(`KV delete failed: ${response.status} ${response.statusText}`);
        }
        return await response.json();
    }

    /**
     * 列出键
     */
    async list(options = {}) {
        if (!this.useRemoteKV) {
            return await this.env.img_url.list(options);
        }

        const params = new URLSearchParams();
        if (options.limit) params.append("limit", options.limit);
        if (options.cursor) params.append("cursor", options.cursor);
        if (options.prefix) params.append("prefix", options.prefix);

        const response = await fetch(`${this.apiUrl}/kv/list?${params}`, {
            headers: { "X-API-Key": this.apiKey }
        });

        if (!response.ok) {
            throw new Error(`KV list failed: ${response.status} ${response.statusText}`);
        }

        const data = await response.json();
        // 兼容 Cloudflare KV 的返回格式
        return {
            keys: data.keys,
            list_complete: data.list_complete,
            cursor: data.cursor
        };
    }

    /**
     * 检查 KV 是否可用
     */
    isAvailable() {
        if (this.useRemoteKV) {
            return true; // 自建 KV API 假设总是可用
        }
        return !!(this.env.img_url);
    }
}

/**
 * 创建 KV 适配器实例
 */
export function createKVAdapter(env) {
    return new KVAdapter(env);
}

export default KVAdapter;
