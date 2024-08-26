import type { ServerWebSocket } from "bun";
import type { WebSocketData, TntUserInfo, JsonRpcError } from "../types";
import getTarantool from "../tnt";

export type InitUserResponse = TntUserInfo;
export type InitUserError = JsonRpcError<1000, "InitUserError">;
export type InitUserRequest = {
    userId: string
};

export async function handleInitUser(
    ws: ServerWebSocket<WebSocketData>,
    data: InitUserRequest
): Promise<InitUserResponse> {
    console.log("handleInitUser", data);
    let tnt = await getTarantool();
    return await tnt.initUserInfo(data.userId);
}
