import Tarantool from "tarantool-driver";
import _ from "lodash";

import type { TntRegisterTaps, TntUserInfo, WS } from "./types";
import { Server } from "bun";

export const toSnakeCase = (obj: any) => {
    return _.mapKeys(obj, (value, key) => {
        return _.snakeCase(key);
    });
};

export const toCamelCase = (obj: any) => {
    return _.mapKeys(obj, (value, key) => {
        return _.camelCase(key);
    });
};

export class TntSubscribe {
    client: WebSocket | null = null;
    constructor(public ws: Server) {}

    onMessage(event: any) {
        console.log("TntSubscribe.onMessage", event.data);
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
        console.log("TntSubscribe.onClose");
        if (!this.client) {
            return;
        }
        this.client.close();
        await new Promise((resolve) => setTimeout(resolve, 1000));
        this.connect();
    }

    async connect() {
        console.log("TntSubscribe.connect");
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
            host: "127.0.0.1",
            port: 3301,
            lazyConnect: true,
            username: "tnt",
            password: "tnt",
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
        console.log("registerTaps", taps);
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
        console.log("getTopReferrals", limit);
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
        console.log("getUsersAround", userId);
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
        console.log("getTopUsers", limit);
        let result = await this.tarantool.call("get_top_users", limit);
        if (result && result.length > 0) {
            return result[0].map(toCamelCase) as any;
        }
        return [];
    }

    async getUserInfo(userId: string): Promise<TntUserInfo> {
        console.log("getUserInfo", userId);
        let result = await this.tarantool.call("get_user_details", userId);
        if (result && result.length > 0) {
            return toCamelCase(result[0][0]) as any;
        }
        throw new Error("User not found");
    }

    async createAnonymousUser(referrer_id?: string): Promise<TntUserInfo> {
        console.log("createAnonymousUser");
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
        console.log("updateProfile", userId, data);
        let result = await this.tarantool.call("update_user", userId, data);
        return toCamelCase(result[0][0]) as any;
    }

    async createUserFromTg(
        tg_id: number,
        username: string,
        referrer_id?: string
    ): Promise<TntUserInfo> {
        console.log("createUserFromTg", tg_id);
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
