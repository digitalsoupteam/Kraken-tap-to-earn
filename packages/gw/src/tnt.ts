import Tarantool from "tarantool-driver";
import { Server } from "bun";
import _ from "lodash";

import type { TntRegisterTaps, TntUserInfo, WS } from "./types";

export const toSnakeCase = (obj: any): any => {
    if (_.isArray(obj)) {
        return obj.map(toSnakeCase);
    } else if (_.isObject(obj)) {
        return _.mapKeys(_.mapValues(obj, toSnakeCase), (value, key) =>
            _.snakeCase(key)
        );
    }
    return obj;
};

export const toCamelCase = (obj: any): any => {
    if (_.isArray(obj)) {
        return obj.map(toCamelCase);
    } else if (_.isObject(obj)) {
        return _.mapKeys(_.mapValues(obj, toCamelCase), (value, key) =>
            _.camelCase(key)
        );
    }
    return obj;
};

export class TntSubscribe {
    client: WebSocket | null = null;
    constructor(public ws: Server) {}

    onMessage(event: any) {
        try {
            let data = JSON.parse(event.data);
            this.ws.publish(
                `user:${data.user_id}`,
                JSON.stringify({
                    jsonrpc: "2.0",
                    method: "updates",
                    params: toCamelCase(data),
                })
            );
        } catch (error) {
            console.error(error);
        }
    }

    async onClose() {
        if (!this.client) {
            return;
        }
        this.client.close();
        await new Promise((resolve) => setTimeout(resolve, 1000));
        this.connect();
    }

    async connect() {
        this.client = new WebSocket(
            process.env.TNT_WS || "ws://localhost:3300"
        );
        this.client.addEventListener("message", this.onMessage.bind(this));
        this.client.addEventListener("close", this.onClose.bind(this));
    }
}

class Client {
    private tarantool: Tarantool;
    constructor() {
        this.tarantool = new Tarantool({
            host: process.env.TARANTOOL_HOST || "127.0.0.1",
            port: parseInt(process.env.TARANTOOL_PORT ?? "3301"),
            lazyConnect: true,
            username: process.env.APP_LOGIN || "tnt",
            password: process.env.APP_PASSWORD || "tnt",
            retryStrategy: function (times) {
                var delay = Math.min(times * 50, 2000);
                return delay;
            },
        });
    }

    async connect() {
        return await this.tarantool.connect();
    }

    async registerTaps(
        taps: TntRegisterTaps[]
    ): Promise<{ userInfo: TntUserInfo; error?: string }[]> {
        let result = await this.tarantool.call(
            "register_taps",
            taps.map(toSnakeCase)
        );
        if (result && result.length > 0) {
            return result[0].map(toCamelCase) as any;
        }
        return [];
    }

    async getTopReferrals(
        userId: string,
        limit: number
    ): Promise<TntUserInfo[]> {
        let result = await this.tarantool.call(
            "get_top_referrals",
            userId,
            limit
        );
        if (result && result.length > 0) {
            return result[0].map(toCamelCase) as any;
        }
        return [];
    }

    async getUsersAround(
        userId: string,
        limit: number
    ): Promise<{ above: TntUserInfo[]; below: TntUserInfo[] }> {
        let result = await this.tarantool.call(
            "get_users_around_of",
            userId,
            limit
        );
        if (result && result.length > 0 && result[0].length > 0) {
            let { above, below } = result[0][0];
            return {
                above: above.map(toCamelCase),
                below: below.map(toCamelCase),
            };
        }
        return { above: [], below: [] };
    }

    async getTopUsers(limit: number): Promise<TntUserInfo[]> {
        let result = await this.tarantool.call("get_top_users", limit);
        if (result && result.length > 0) {
            return result[0].map(toCamelCase) as any;
        }
        return [];
    }

    async getUserInfo(userId: string): Promise<TntUserInfo> {
        let result = await this.tarantool.call("get_user_details", userId);
        if (result && result.length > 0) {
            return toCamelCase(result[0][0]) as any;
        }
        throw new Error("User not found");
    }

    async createAnonymousUser(referrer_id?: string): Promise<TntUserInfo> {
        let result = await this.tarantool.call(
            "create_anonymous_user",
            referrer_id
        );
        return toCamelCase(result[0][0]) as any;
    }

    async updateProfile(
        userId: string,
        data: { nickname?: string; wallet?: string }
    ) {
        let result = await this.tarantool.call("update_user", userId, data);
        return toCamelCase(result[0][0]) as any;
    }

    async createUserFromTg(
        tg_id: number,
        username?: string,
        referrer_id?: string
    ): Promise<TntUserInfo> {
        let result = await this.tarantool.call(
            "get_or_create_user_from_tg",
            tg_id,
            username,
            referrer_id
        );
        if (result && result.length > 0) {
            return toCamelCase(result[0][0]) as any;
        }
        throw new Error("User not found");
    }
}

export default (() => {
    let client: Client;
    async function getTarantool() {
        if (!client) {
            client = new Client();
            await client.connect();
        }
        return client;
    }
    return getTarantool;
})();
