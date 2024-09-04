import { t, Static } from "elysia";
import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type GetUsersAroundOfResponse = {
    above: TntUserInfo[];
    below: TntUserInfo[];
};
export type GetUsersAroundOfError = JsonRpcError<1002, "GetUsersAroundOfError">;
export const SchemaGetUsersAroundOf = t.Object(
    {
        limit: t.Number(),
    },
    { additionalProperties: false }
);
export type GetUsersAroundOfRequest = Static<typeof SchemaGetUsersAroundOf>;

export async function handleGetUsersAroundOf(
    ws: WS,
    data: GetUsersAroundOfRequest
): Promise<GetUsersAroundOfResponse> {
    console.log("handleGetUsersAroundOf", data);
    let tnt = await getTarantool();
    return await tnt.getUsersAround(ws.data.userId, data.limit);
}
