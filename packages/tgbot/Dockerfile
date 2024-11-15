FROM oven/bun:1 AS base
COPY packages/tgbot /tgbot
WORKDIR /tgbot
RUN bun install 
CMD bun run main.ts
