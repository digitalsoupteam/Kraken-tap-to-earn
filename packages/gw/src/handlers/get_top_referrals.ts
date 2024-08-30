import { t, Static } from "elysia";
import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetTopReferralsResponse = TntUserInfo[];
export type GetTopReferralsError = JsonRpcError<1002, "GetTopReferralsError">;
export const SchemaGetTopReferrals = t.Object(
    {
        limit: t.Number(),
    },
    { additionalProperties: false }
);
export type GetTopReferralsRequest = Static<typeof SchemaGetTopReferrals>;

export async function handleGetTopReferrals(
    ws: WS,
    data: GetTopReferralsRequest
): Promise<GetTopReferralsResponse> {
    console.log("handleGetTopReferrals", data);
    let tnt = await getTarantool();
    return await tnt.getTopReferrals(ws.data.userId, data.limit);
}
