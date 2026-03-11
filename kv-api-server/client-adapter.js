/**
 * KV 客户端适配器
 * 将 Cloudflare KV API 调用转发到自建的 KV API 服务
 *
 * 使用方法：
 * 1. 将此文件复制到 functions 目录
 * 2. 在需要使用 KV 的地方引入并使用
 */

const KV_API_URL = "https://your-kv-api-domain.com";  // 替换为你的 KV API 地址
const KV_API_KEY = "your-secret-api-key-change-this"; // 替换为你的 API 密钥

class KVClient {
    constructor(apiUrl, apiKey) {
        this.apiUrl = apiUrl;
        this.apiKey = apiKey;
    }

    /**
     * 保存键值
     * 兼容: env.img_url.put(key, value, { metadata })
     */
    async put(key, value, options = {}) {
        const url = new URL(`${this.apiUrl}/kv/${key}`);
        if (value !== undefined && value !== "") {
            url.searchParams.append("value", value);
        }

        const headers = {
            "X-API-Key": this.apiKey,
            "Content-Type": "application/json"
        };

        // 如果有 metadata，放在请求体中
        let body = undefined;
        if (options.metadata) {
            body = JSON.stringify({ metadata: options.metadata });
            url.searchParams.delete("value"); // 清除之前的 value
        }

        const response = await fetch(url.toString(), {
            method: "PUT",
            headers,
            body
        });

        if (!response.ok) {
            throw new Error(`KV put failed: ${response.status}`);
        }
        return await response.json();
    }

    /**
     * 获取值
     * 兼容: env.img_url.get(key)
     */
    async get(key) {
        const response = await fetch(`${this.apiUrl}/kv/${key}`, {
            headers: {
                "X-API-Key": this.apiKey
            }
        });

        if (!response.ok) {
            if (response.status === 404) return null;
            throw new Error(`KV get failed: ${response.status}`);
        }
        return await response.text();
    }

    /**
     * 获取值和元数据
     * 兼容: env.img_url.getWithMetadata(key)
     */
    async getWithMetadata(key) {
        const response = await fetch(`${this.apiUrl}/kv/${key}/metadata`, {
            headers: {
                "X-API-Key": this.apiKey
            }
        });

        if (!response.ok) {
            if (response.status === 404) return null;
            throw new Error(`KV getWithMetadata failed: ${response.status}`);
        }
        const data = await response.json();
        return {
            value: data.value,
            metadata: data.metadata
        };
    }

    /**
     * 删除键
     * 兼容: env.img_url.delete(key)
     */
    async delete(key) {
        const response = await fetch(`${this.apiUrl}/kv/${key}`, {
            method: "DELETE",
            headers: {
                "X-API-Key": this.apiKey
            }
        });

        if (!response.ok) {
            throw new Error(`KV delete failed: ${response.status}`);
        }
        return await response.json();
    }

    /**
     * 列出键
     * 兼容: env.img_url.list({ limit, cursor, prefix })
     */
    async list(options = {}) {
        const params = new URLSearchParams();
        if (options.limit) params.append("limit", options.limit);
        if (options.cursor) params.append("cursor", options.cursor);
        if (options.prefix) params.append("prefix", options.prefix);

        const response = await fetch(`${this.apiUrl}/kv/list?${params}`, {
            headers: {
                "X-API-Key": this.apiKey
            }
        });

        if (!response.ok) {
            throw new Error(`KV list failed: ${response.status}`);
        }
        return await response.json();
    }
}

// 创建全局 KV 客户端实例
const kvClient = new KVClient(KV_API_URL, KV_API_KEY);

// 导出适配函数，兼容原有代码
export const KVAdapter = {
    put: (key, value, options) => kvClient.put(key, value, options),
    get: (key) => kvClient.get(key),
    getWithMetadata: (key) => kvClient.getWithMetadata(key),
    delete: (key) => kvClient.delete(key),
    list: (options) => kvClient.list(options)
};

export default KVAdapter;
