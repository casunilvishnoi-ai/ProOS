# syntax=docker/dockerfile:1
FROM node:22-alpine AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM node:22-alpine AS build
WORKDIR /app
RUN apk add --no-cache libc6-compat openssl
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN node scripts/make-postgres-schema.js && npx prisma generate --schema prisma/schema.postgres.prisma
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
RUN apk add --no-cache openssl && addgroup -S proos && adduser -S proos -G proos
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3100 HOSTNAME=0.0.0.0
COPY --from=build /app/public ./public
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
# worker + prisma CLI for migrations/seed
COPY --from=build /app/prisma ./prisma
COPY --from=build /app/scripts ./scripts
COPY --from=build /app/src ./src
COPY --from=build /app/node_modules/prisma ./node_modules/prisma
COPY --from=build /app/node_modules/tsx ./node_modules/tsx
COPY --from=build /app/node_modules/.bin ./node_modules/.bin
COPY --from=build /app/node_modules/nodemailer ./node_modules/nodemailer
COPY --from=build /app/node_modules/zod ./node_modules/zod
COPY --from=build /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=build /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=build /app/tsconfig.json ./tsconfig.json
RUN mkdir -p /app/data/uploads && chown -R proos:proos /app/data
USER proos
EXPOSE 3100
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:3100/api/health || exit 1
CMD ["node", "server.js"]
