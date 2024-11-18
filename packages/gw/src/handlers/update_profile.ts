import { t, Static } from "elysia";

import type { TntUserInfo, JsonRpcError, WS } from "../types";
import getTarantool from "../tnt";

export type SendUpdateProfileResponse = {
    userInfo: TntUserInfo;
    error?: string;
}[];
export type SendUpdateProfileError = JsonRpcError<
    1006,
    "SendUpdateProfileError"
>;
export const SchemaSendUpdateProfile = t.Object(
    {
        nickname: t.Optional(t.String()),
        wallet: t.Optional(t.String({ pattern: "^[1-9A-HJ-NP-Za-km-z]{32,44}$" })),
    },
    { additionalProperties: false }
);
export type SendUpdateProfileRequest = Static<typeof SchemaSendUpdateProfile>;

export async function handleSendUpdateProfile(
    ws: WS,
    data: SendUpdateProfileRequest
): Promise<SendUpdateProfileResponse> {
    data.wallet = data.wallet?.toLowerCase();
    let tnt = await getTarantool();
    return await tnt.updateProfile(ws.data.userId, data);
}
