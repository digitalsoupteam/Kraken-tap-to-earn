import Tarantool from "tarantool-driver";
import _ from "lodash";

import type { TntRegisterTaps, TntUserInfo } from "./types";

const toSnakeCase = (obj: any) => {
    return _.mapKeys(obj, (value, key) => {
        return _.snakeCase(key);
    });
};

const toCamelCase = (obj: any) => {
    return _.mapKeys(obj, (value, key) => {
        return _.camelCase(key);
    });
};

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
        let result = await this.tarantool.call("get_user_info", userId);
        if (result && result.length > 0) {
            return toCamelCase(result[0]) as any;
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
        referrer_id?: string
    ): Promise<TntUserInfo> {
        console.log("createUserFromTg", tg_id);
        let result = await this.tarantool.call(
            "get_or_create_user_from_tg",
            tg_id,
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
