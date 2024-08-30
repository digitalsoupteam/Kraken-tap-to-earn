import { t, Static } from "elysia";
import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetTopUsersResponse = TntUserInfo[];
export type GetTopUsersError = JsonRpcError<1003, "GetTopUsersError">;
export const SchemaGetTopUsers = t.Object(
    {
        limit: t.Number(),
    },
    { additionalProperties: false }
);
export type GetTopUsersRequest = Static<typeof SchemaGetTopUsers>;
export async function handleGetTopUsers(
    ws: WS,
    data: GetTopUsersRequest
): Promise<GetTopUsersResponse> {
    console.log("handleGetTopUsers", data);
    let tnt = await getTarantool();
    return await tnt.getTopUsers(data.limit);
}
