import type { ServerWebSocket } from "bun";
import {
    JsonRpcBaseError,
    type AllSuccessTypes,
    type JsonRPCRequests,
    type WebSocketData,
    JsonRpcError,
    type AllErrorTypes,
    type JsonRPCResponses,
} from "./types";
import { handleSendTaps } from "./handlers/send_taps";
import { handleGetTopUsers } from "./handlers/get_top_users";
import { handleGetUser } from "./handlers/get_user";

export function parseJsonRPCMessage(message: string): JsonRPCRequests {
    const obj = JSON.parse(message);
    if (!obj || !obj.jsonrpc || !obj.method)
        throw new JsonRpcBaseError("Parse error", -32600);
    return obj;
}
