import { JsonRpcBaseError, type JsonRPCRequests } from "./types";

export function parseJsonRPCMessage(message: string): JsonRPCRequests {
    const obj = JSON.parse(message);
    if (!obj || !obj.jsonrpc || !obj.method)
        throw new JsonRpcBaseError("Parse error", -32600);
    return obj;
}
