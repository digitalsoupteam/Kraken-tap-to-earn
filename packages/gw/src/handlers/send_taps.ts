import { t, Static } from "elysia";
import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type SendTapsResponse = { userInfo: TntUserInfo; error?: string }[];
export type SendTapsError = JsonRpcError<1005, "SendTapsError">;
export const SchemaSendTaps = t.Array(
    t.Object(
        {
            x: t.Number({ minimum: 0, maximum: 20000, multipleOf: 1 }),
            y: t.Number({ minimum: 0, maximum: 20000, multipleOf: 1 }),
        },
        { additionalProperties: false }
    ),
    { minItems: 1, maxItems: 100 } // we expect that user can tap 10 times per second (batch) using 10 fingers
);
export type SendTapsRequest = Static<typeof SchemaSendTaps>;

export async function handleSendTaps(
    ws: WS,
    taps: SendTapsRequest
): Promise<SendTapsResponse> {
    let tnt = await getTarantool();
    return await tnt.registerTaps([{ taps, userId: ws.data.userId }]);
}
