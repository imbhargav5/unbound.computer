# Build stage
FROM node:22-alpine AS builder

# Install pnpm
RUN corepack enable && corepack prepare pnpm@9.0.6 --activate

WORKDIR /app

# Copy workspace files
COPY pnpm-workspace.yaml pnpm-lock.yaml package.json ./
COPY packages/typescript-config ./packages/typescript-config
COPY packages/protocol ./packages/protocol
COPY apps/relay ./apps/relay

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build packages
RUN pnpm --filter @unbound/protocol build
RUN pnpm --filter @unbound/relay build

# Production stage
FROM node:22-alpine AS runner

WORKDIR /app

# Install pnpm for production
RUN corepack enable && corepack prepare pnpm@9.0.6 --activate

# Copy package files
COPY --from=builder /app/pnpm-workspace.yaml /app/pnpm-lock.yaml /app/package.json ./
COPY --from=builder /app/packages/typescript-config ./packages/typescript-config
COPY --from=builder /app/packages/protocol/package.json ./packages/protocol/
COPY --from=builder /app/packages/protocol/dist ./packages/protocol/dist
COPY --from=builder /app/apps/relay/package.json ./apps/relay/
COPY --from=builder /app/apps/relay/dist ./apps/relay/dist

# Install production dependencies only
RUN pnpm install --frozen-lockfile --prod

# Set working directory to relay app
WORKDIR /app/apps/relay

# Environment
ENV NODE_ENV=production
ENV PORT=8080

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run
CMD ["node", "dist/index.js"]
