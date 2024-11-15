FROM oven/bun:1 AS base
WORKDIR /app

FROM base AS release 

ENV NODE_ENV=production
COPY package.json bun.lockb /app/
COPY packages /app/packages
RUN bun install --production
# 
# # run the app
USER bun
EXPOSE 3000/tcp
ENTRYPOINT [ "bun", "run", "/app/packages/gw/src/index.ts" ]
