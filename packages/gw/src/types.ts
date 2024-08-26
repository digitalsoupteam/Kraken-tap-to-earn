// Websocket types

import type {
    GetTopUsersError,
    GetTopUsersRequest,
    GetTopUsersResponse,
} from "./handlers/get_top_users";
import type {
    GetUserError,
    GetUserRequest,
    GetUserResponse,
} from "./handlers/get_user";
import type {
    SendTapsError,
    SendTapsRequest,
    SendTapsResponse,
} from "./handlers/send_taps";

//
export type WebSocketData = {
    createdAt: number;
    channelId: string;
    userId: string;
    authToken: string;
};

// JsonRPC types

export type JsonRPCResponse<S, E> = {
    jsonrpc: "2.0";
    id?: number;
} & ({ result: S } | { error: E });

export type JsonRPCRequest<T extends string, P> = {
    jsonrpc: "2.0";
    id?: number;
    method: T;
    params: P;
};

export class JsonRpcBaseError extends Error {
    code: number;
    message: string;
    constructor(message: string, code: number) {
        super(message);
        this.message = message;
        this.code = code;
    }
}
export class JsonRpcError<
    C extends number,
    M extends string
> extends JsonRpcBaseError {
    constructor(message: M, code: C) {
        super(message, code);
    }
}

export type Echo = {};
export type EchoRequest = Echo;
export type EchoResponse = Echo;

export type MethodToRequestMap = {
    sendTaps: SendTapsRequest;
    getUser: GetUserRequest;
    getTopUsers: GetTopUsersRequest;
    ping: EchoRequest;
    any: any;
};
export type JsonRPCRequests = {
    [K in keyof MethodToRequestMap]: JsonRPCRequest<K, MethodToRequestMap[K]>;
}[keyof MethodToRequestMap];

export type MethodToResponseMap = {
    sendTaps: { Success: SendTapsResponse; Error: SendTapsError };
    ping: { Success: EchoResponse; Error: JsonRpcBaseError };
    getUser: { Success: GetUserResponse; Error: GetUserError };
    getTopUsers: { Success: GetTopUsersResponse; Error: GetTopUsersError };
    any: any;
};
export type JsonRPCResponses = {
    [K in keyof MethodToResponseMap]: JsonRPCResponse<
        MethodToResponseMap[K]["Success"],
        MethodToResponseMap[K]["Error"]
    >;
}[keyof MethodToResponseMap];
export type AllSuccessTypes =
    MethodToResponseMap[keyof MethodToResponseMap]["Success"];
export type AllErrorTypes =
    MethodToResponseMap[keyof MethodToResponseMap]["Error"];

// Tarantool types

export type TntRegisterTaps = {
    user_id: string;
    taps: {
        x: number;
        y: number;
    }[];
};

export type TntLevel = {
    id: string;
    quotaPeriod: number;
    quotaAmount: number;
    calmPeriod: number;
};

export type TntUserInfo = {
    id: string;
    userId: string;
    isBlocked: boolean;
    level: TntLevel;
    nickname: string;
    sessionStart: number;
    sessionLeft: number;
    sessionUntil: number;
    sessionTaps: number;
    sessionTapsLeft: number;
    taps: number;
    calmUntil: number;
};
