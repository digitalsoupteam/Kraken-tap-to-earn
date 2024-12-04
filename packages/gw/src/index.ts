import { logger } from "@bogeychan/elysia-logger";
import { jwt } from "@elysiajs/jwt";
import {
    AllErrorTypes,
    AllSuccessTypes,
    JsonRPCResponses,
    JsonRpcBaseError,
    JsonRpcError,
    type WS,
} from "./types";
import { Elysia, t } from "elysia";
import { env } from "@yolk-oss/elysia-env";

import getTarantool, { TntSubscribe } from "./tnt";
import { handleGetTopUsers, SchemaGetTopUsers } from "./handlers/get_top_users";
import { handleGetUser } from "./handlers/get_user";
import { handleSendTaps, SchemaSendTaps } from "./handlers/send_taps";
import {
    createWebAppSecret,
    decodeInitData,
    verifyTelegramWebAppInitData,
} from "./initData";
import {
    handleGetTopReferrals,
    SchemaGetTopReferrals,
} from "./handlers/get_top_referrals";
import {
    handleSendUpdateProfile,
    SchemaSendUpdateProfile,
} from "./handlers/update_profile";
import {
    handleGetUsersAroundOf,
    SchemaGetUsersAroundOf,
} from "./handlers/get_around_of";

const app = new Elysia()
    .use(
        logger({
            autoLogging: true,
            level: process.env.LOG_LEVEL ?? "info",
        })
    )
    // @ts-ignore
    .onStart((ctx) => {
        if (!ctx.server) {
            return;
        }
        console.log("Listening on " + ctx.server.url);
        // @ts-ignore
        // new TntSubscribe(ctx.server).connect();
    })
    .use(
        env({
            TOKEN: t.String({
                pattern: "^[0-9]+:[0-9a-zA-Z_-]+$",
                error: "TOKEN is required for a service!",
            }),
        })
    )
    .use(
        jwt({
            name: "jwt",
            secret: process.env.TOKEN!,
        })
    )
    .derive(async ({ jwt, headers, request }) => {
        const auth = headers["authorization"];
        let token = "";
        if (auth && auth.startsWith("Bearer ")) {
            token = auth.slice(7);
        } else {
            token = new URL(request.url).searchParams.get("jwt")!;
        }
        const data = await jwt.verify(token);
        if (!data) {
            return {
                userId: null,
            };
        }
        return {
            userId: data.id,
            lastMessageAt: Date.now(),
            messageCount: 0,
        };
    })
    .post(
        "/api/anonymous_session",
        async (ctx) => {
            let tnt = await getTarantool();
            const user = await tnt.createAnonymousUser(ctx.body.referrer_id);
            return { jwt: await ctx.jwt.sign({ id: user.userId }) };
        },
        {
            body: t.Object({
                referrer_id: t.Optional(t.String()),
            }),
        }
    )
    .post(
        "/api/telegram_session",
        async (ctx) => {
            let initData = decodeInitData(ctx.body.initData);
            const secretKey = createWebAppSecret(ctx.env.TOKEN);
            if (
                !verifyTelegramWebAppInitData(
                    ctx.body.initData,
                    initData.hash!,
                    secretKey
                )
            ) {
                return new Response("Invalid initData", { status: 400 });
            }
            let tnt = await getTarantool();
            const user = await tnt.createUserFromTg(
                initData.user!.id.toString(),
                initData.user!.username,
                ctx.body.referrer_id
            );
            if (!user.userId) {
                return new Response("Internal error", { status: 500 });
            }
            return { jwt: await ctx.jwt.sign({ id: user.userId }) };
        },
        {
            body: t.Object({
                initData: t.String(),
                referrer_id: t.Optional(t.String()),
            }),
        }
    )
    .guard(
        {
            query: t.Object({
                jwt: t.String(),
            }),
        },
        (app) =>
            app.ws("/ws", {
                beforeHandle(ctx) {
                    if (!ctx.userId) {
                        return (ctx.set.status = 401);
                    }
                },
                body: t.Intersect(
                    [
                        t.Object({
                            jsonrpc: t.Const("2.0"),
                            id: t.Optional(t.Number()),
                        }),
                        t.Union([
                            t.Object({
                                method: t.Literal("ping"),
                                params: t.Optional(t.Any()),
                            }),
                            t.Object({
                                method: t.Literal("getUser"),
                            }),
                            t.Object({
                                method: t.Literal("sendTaps"),
                                params: SchemaSendTaps,
                            }),
                            t.Object({
                                method: t.Literal("updateProfile"),
                                params: SchemaSendUpdateProfile,
                            }),
                            t.Object({
                                method: t.Literal("getTopUsers"),
                                params: SchemaGetTopUsers,
                            }),
                            t.Object({
                                method: t.Literal("getUsersAround"),
                                params: SchemaGetUsersAroundOf,
                            }),
                            t.Object({
                                method: t.Literal("getTopReferrals"),
                                params: SchemaGetTopReferrals,
                            }),
                            // t.Object({
                            //     method: t.Literal("subscribe"),
                            // }),
                            // t.Object({
                            //     method: t.Literal("unsubscribe"),
                            // }),
                        ]),
                    ],
                    { additionalProperties: false }
                ),
                async message(ws: WS, message) {
                    let now = Date.now();
                    if (
                        ws.data.lastMessageAt &&
                        now - ws.data.lastMessageAt > 1000 // TODO: configurable
                    ) {
                        ws.data.lastMessageAt = now;
                        ws.data.messageCount = 1;
                        // TODO: configurable
                    } else if (ws.data.messageCount > 25) {
                        ws.send({
                            jsonrpc: "2.0",
                            id: message.id,
                            error: {
                                code: -32603,
                                message: "Too many requests",
                            },
                        });
                        ws.close();
                    } else {
                        ws.data.messageCount++;
                    }
                    // support only string messages
                    let result: AllSuccessTypes | null = null;
                    let response: JsonRPCResponses;
                    let start = process.hrtime.bigint() / 1000n;
                    let error: AllErrorTypes = new JsonRpcBaseError(
                        "Unknown error",
                        -32603
                    );
                    try {
                        switch (message.method) {
                            case "sendTaps":
                                let response = await handleSendTaps(
                                    ws,
                                    message.params
                                );
                                result = response[0];
                                break;
                            case "ping":
                                result = "pong";
                                break;
                            case "getUser":
                                result = await handleGetUser(ws, {});
                                break;
                            case "updateProfile":
                                result = await handleSendUpdateProfile(
                                    ws,
                                    message.params
                                );
                                break;
                            case "getTopUsers":
                                result = await handleGetTopUsers(
                                    ws,
                                    message.params
                                );
                                break;
                            case "getTopReferrals":
                                result = await handleGetTopReferrals(
                                    ws,
                                    message.params
                                );
                                break;
                            case "getUsersAround":
                                result = await handleGetUsersAroundOf(
                                    ws,
                                    message.params
                                );
                                break;
                            // case "subscribe":
                            //     ws.subscribe(`user:${ws.data.userId}`);
                            //     result = "ok";
                            //     break;
                            // case "unsubscribe":
                            //     ws.unsubscribe(`user:${ws.data.userId}`);
                            //     result = "ok";
                            //     break;
                            default:
                                throw new JsonRpcBaseError(
                                    // @ts-ignore
                                    `Method ${message.method} not found`,
                                    -32601
                                );
                        }
                    } catch (e) {
                        if (e instanceof JsonRpcError) {
                            error = e;
                        } else {
                            let errorMessage = (e as Error).toString();
                            if (errorMessage.startsWith("TarantoolError:")) {
                                errorMessage = errorMessage
                                    .split(":")
                                    .slice(3)
                                    .join(":")
                                    .slice(1);
                            }
                            error = new JsonRpcBaseError(errorMessage, -32603);
                        }
                    }
                    response = {
                        jsonrpc: "2.0",
                        id: message.id,
                        error: result === null ? error : undefined,
                        result: result !== null ? result : undefined,
                    };
                    ws.data.log.info({
                        responseTime:
                            Number(process.hrtime.bigint() / 1000n - start) /
                            1_000,
                        userId: ws.data.userId,
                        message,
                        error: result === null ? error : undefined,
                        result: result !== null ? result : undefined,
                        remoteAddress: ws.remoteAddress,
                    });
                    if (!response.id && error === null) return;

                    ws.send(response);
                },
            })
    );
app.listen(process.env.PORT || 8080);
