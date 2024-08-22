import type { ServerWebSocket } from "bun";
import type { WebSocketData, TntUserInfo, JsonRpcError } from "../types";
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
    ws: ServerWebSocket<WebSocketData>,
    data: SendTapsRequest
): Promise<SendTapsResponse> {
    console.log("handleSendTaps", data.taps);
    let tnt = await getTarantool();
    return await tnt.registerTaps([
        { userId: ws.data.userId, taps: data.taps },
    ]);
}
