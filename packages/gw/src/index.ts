import { watch } from "fs";
import html from "bun-plugin-html";
import { handleGetTopUsers } from "./handlers/get_top_users";
import { handleGetUser } from "./handlers/get_user";
import { handleSendTaps } from "./handlers/send_taps";
import {
    AllErrorTypes,
    AllSuccessTypes,
    JsonRPCResponses,
    JsonRpcBaseError,
    JsonRpcError,
    type WebSocketData,
} from "./types";
import { Elysia, t } from "elysia";
import staticPlugin from "@elysiajs/static";

const app = new Elysia()
    .use(staticPlugin())
    .derive(({ headers }) => {
        const auth = headers["authorization"];

        return {
            bearer: auth?.startsWith("Bearer ") ? auth.slice(7) : null,
        };
    })
    .get("/", () => Bun.file("./public/index.html"))
    .get("/ui/*", (ctx) => {
        const path = new URL(ctx.request.url).pathname;
        const file = Bun.file(`./public${path}`);
        return new Response(file);
    })
    .post(
        "/api/telegram_verify",
        (ctx) => {
            console.log("ctx", ctx);
            return new Response();
        },
        {
            body: t.Object({ initData: t.String() }),
        }
    )
    .ws("/ws", {
        async open(ws) {
            console.log(ws.remoteAddress, "connected");
        },
        body: t.Object({
            jsonrpc: t.Const("2.0"),
            id: t.Optional(t.Number()),
            method: t.String(),
            params: t.Optional(t.Any()),
        }),
        async message(ws, message) {
            console.log("message", ws.remoteAddress, message);
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
                        result = await handleSendTaps(ws, message.params);
                        break;
                    case "ping":
                        result = message.params;
                        break;
                    case "getUser":
                        result = await handleGetUser(ws, message.params);
                        break;
                    case "getTopUsers":
                        result = await handleGetTopUsers(ws, message.params);
                        break;
                    default:
                        throw new JsonRpcBaseError(
                            `Method ${message.method} not found`,
                            -32601
                        );
                }
            } catch (e) {
                if (e instanceof JsonRpcError) {
                    error = e;
                } else {
                    error = new JsonRpcBaseError(
                        (e as Error).toString(),
                        -32603
                    );
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
