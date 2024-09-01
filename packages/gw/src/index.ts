import { watch } from "fs";
import html from "bun-plugin-html";
import { handleGetTopUsers, SchemaGetTopUsers } from "./handlers/get_top_users";
import { handleGetUser } from "./handlers/get_user";
import { handleSendTaps, SchemaSendTaps } from "./handlers/send_taps";
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
import getTarantool from "./tnt";
import staticPlugin from "@elysiajs/static";
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

const app = new Elysia()
    .use(staticPlugin())
    .use(
        env({
            TOKEN: t.String({
                pattern: "^[0-9]+:[0-9a-zA-Z_]+$",
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
        };
    })
    .get("/", () => Bun.file("./public/index.html"))
    .get("/ui/*", (ctx) => {
        const path = new URL(ctx.request.url).pathname;
        const file = Bun.file(`./public${path}`);
        return new Response(file);
    })
    .post(
        "/api/anonymous_session",
        async (ctx) => {
            let tnt = await getTarantool();
            const user = await tnt.createAnonymousUser(ctx.body.referrer_id);
            console.log("createAnonymousUser", user);
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
            if (!verifyTelegramWebAppInitData(initData, secretKey)) {
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
    .guard((app) =>
        app.ws("/ws", {
            beforeHandle(ws) {
                console.log("beforeHandle", ws);
                if (!ws.userId) {
                    throw new Error("Unauthorized");
                }
            },
            async open(ws: WS) {
                if (!ws.data.userId) {
                    throw new Error("Unauthorized");
                }
                console.log(ws.remoteAddress, "connected", ws.data.userId);
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
                            method: t.Literal("getTopReferrals"),
                            params: SchemaGetTopReferrals,
                        }),
                    ]),
                ],
                { additionalProperties: false }
            ),
            async message(ws: WS, message) {
                console.log(
                    "message",
                    ws.remoteAddress,
                    ws.data.store,
                    ws.data.userId
                );
                // support only string messages
                console.log("JsonRPCRequest", ws.remoteAddress, message);
                let result: AllSuccessTypes | null = null;
                let response: JsonRPCResponses;
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
                if (!response.id && error === null) return;
                console.log("JsonRPCResponse", ws.remoteAddress, response);
                ws.send(response);
            },
            async close(ws) {
                console.log(ws.remoteAddress, "disconnected");
            },
        })
    )
    .onStart(async () => {
        let build = async () => {
            await Bun.build({
                entrypoints: ["./src/index.html"],
                outdir: "./public",
                // minify: true,
                target: "browser",
                format: "esm",
                plugins: [html()],
            });
        };
        await build();
        const watcher = watch(import.meta.dir, build);
    });

app.listen(3000);
