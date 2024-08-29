import type { ServerWebSocket } from "bun";
import type { WebSocketData, TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type SendTapsResponse = { userInfo: TntUserInfo; error?: string }[];
export type SendTapsError = JsonRpcError<1000, "SendTapsError">;
export type SendTapsRequest = {
    userId: string;
    taps: {
        x: number;
        y: number;
    }[];
};

export async function handleSendTaps(
    ws: WS,
    data: SendTapsRequest
): Promise<SendTapsResponse> {
    let tnt = await getTarantool();
    return await tnt.registerTaps([data]);
}
