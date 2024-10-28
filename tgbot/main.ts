import { Markup, Telegraf } from "telegraf";

const bot = new Telegraf(process.env.BOT_TOKEN!);

bot.command("start", async (ctx) => {
    await ctx.reply(
        `Introducing Release Kraken! 🌊 Dive into our groundbreaking tap-to-earn game built on the powerful Solana blockchain. 🎮

Collect points in the app now, complete tasks and fight for leaderboard 🏆

More surprises are on the horizon with our indie game and quest platform. Stay tuned for an adventure like no other! 🚀

Invite your friends to join the fun—together, we make the Kraken ecosystem thrive and explore endless possibilities!`,
        {
            ...Markup.inlineKeyboard([
                [Markup.button.webApp("Launch Kraken", "https://game.releasethekraken.io/")],
                [Markup.button.url("Join community", "https://t.me/releasethekraken")],
            ]),
        }
    );
});

bot.launch();

process.once("SIGINT", () => bot.stop("SIGINT"));
process.once("SIGTERM", () => bot.stop("SIGTERM"));
