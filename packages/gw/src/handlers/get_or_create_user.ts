import type { ServerWebSocket } from "bun";
import type { WebSocketData, TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetOrCreateUserResponse = TntUserInfo;
export type GetOrCreateUserError = JsonRpcError<1000, "GetOrCreateUserError">;
export type GetOrCreateUserRequest = { tg_id?: number };

export async function handleGetOrCreateUser(
    ws: WS,
    data: GetOrCreateUserRequest
): Promise<GetOrCreateUserResponse> {
    console.log("handleGetOrCreateUser", data);
    let tnt = await getTarantool();
    if (data.tg_id) {
        return tnt.createUserFromTg(data.tg_id);
    }
    return tnt.createAnonymousUser();
}
