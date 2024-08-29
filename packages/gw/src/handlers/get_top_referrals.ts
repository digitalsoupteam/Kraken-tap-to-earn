import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetTopReferralsResponse = TntUserInfo[];
export type GetTopReferralsError = JsonRpcError<1010, "GetTopReferralsError">;
export type GetTopReferralsRequest = {
    limit: number;
};

export async function handleGetTopReferrals(
    ws: WS,
    data: GetTopReferralsRequest
): Promise<GetTopReferralsResponse> {
    console.log("handleGetTopReferrals", data);
    let tnt = await getTarantool();
    return await tnt.getTopReferrals(ws.data.userId, data.limit);
}
