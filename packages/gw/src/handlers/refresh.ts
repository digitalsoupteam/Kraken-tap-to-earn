import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type RefreshResponse = TntUserInfo;
export type RefreshError = JsonRpcError<1006, "RefreshError">;
export type RefreshRequest = {};

export async function handleRefresh(
    ws: WS,
    data: RefreshRequest
): Promise<RefreshResponse> {
    let tnt = await getTarantool();
    return await tnt.refresh(ws.data.userId);
}
