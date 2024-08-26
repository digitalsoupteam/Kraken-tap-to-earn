import Tarantool from "tarantool-driver";
import type { TntRegisterTaps, TntUserInfo } from "./types";

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
        let result = await this.tarantool.call("register_taps", taps);
        console.log("registerTaps result", result);
        if (result && result.length > 0) {
            return result[0];
        }
        return [];
    }

    async getTopUsers(limit: number): Promise<TntUserInfo[]> {
        console.log("getTopUsers", limit);
        let result = await this.tarantool.call("get_top_users", limit);
        console.log("getTopUsers result", result);
        if (result && result.length > 0) {
            return result[0];
        }
        return [];
    }

    async getUserInfo(userId: string): Promise<TntUserInfo> {
        console.log("getUserInfo", userId);
        let result = await this.tarantool.call("get_user_info", userId);
        console.log("getUserInfo result", result);
        if (result && result.length > 0) {
            return result[0];
        }
        throw new Error("User not found");
    }

    async initUserInfo(userId: string): Promise<TntUserInfo> {
        console.log("InitUser", userId);
        let result = await this.tarantool.call("get_or_create_user_from_tg", userId);
        console.log("initUser result", result);
        if (result && result.length > 0) {
            return result[0];
        }
        throw new Error("User not found");
    }

    async createUserFromTg(tg_id: number): Promise<TntUserInfo> {
        console.log("createUserFromTg", tg_id);
        let result = await this.tarantool.call(
            "get_or_create_user_from_tg",
            tg_id
        );
        console.log("createUserFromTg result", result);
        if (result && result.length > 0) {
            return result[0];
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
