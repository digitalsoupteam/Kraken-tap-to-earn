import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetUserResponse = TntUserInfo;
export type GetUserError = JsonRpcError<1004, "GetUserError">;
export type GetUserRequest = {};

export async function handleGetUser(
    ws: WS,
    data: GetUserRequest
): Promise<GetUserResponse> {
    console.log("handleGetUser", data);
    let tnt = await getTarantool();
    return await tnt.getUserInfo(ws.data.userId);
}
