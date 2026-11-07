# syntax=docker/dockerfile:1

FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run typecheck

FROM node:22-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# The start script runs TypeScript through tsx, so keep the full install
# (tsx is a dev dependency) and copy the sources and migrations.
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/src ./src
COPY --from=build /app/db ./db
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/tsconfig.json ./tsconfig.json

USER node
EXPOSE 4747

HEALTHCHECK --interval=30s --timeout=3s --start-period=25s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4747/health || exit 1

# Runs pending migrations, then starts the API on 0.0.0.0:4747.
CMD ["npm", "start"]
