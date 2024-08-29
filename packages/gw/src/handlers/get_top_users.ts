import type { ServerWebSocket } from "bun";
import type { WebSocketData, TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetTopUsersResponse = TntUserInfo[];
export type GetTopUsersError = JsonRpcError<1000, "GetTopUsersError">;
export type GetTopUsersRequest = {
    limit: number;
};

export async function handleGetTopUsers(
    ws: WS,
    data: GetTopUsersRequest
): Promise<GetTopUsersResponse> {
    console.log("handleGetTopUsers", data);
    let tnt = await getTarantool();
    return await tnt.getTopUsers(data.limit);
}
