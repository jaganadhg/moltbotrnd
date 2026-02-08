# =============================================================================
# OpenClaw Dockerfile — Podman-compatible, security-hardened, rootless
# =============================================================================
# Multi-stage build to minimize final image size and attack surface

# ---- Stage 1: Build ----
FROM docker.io/node:22-bookworm AS builder

# Install Bun (required by OpenClaw build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /build

# Clone OpenClaw and checkout latest release
RUN git clone --depth 1 https://github.com/openclaw/openclaw.git . \
    && git fetch --tags --depth 1 \
    && LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main") \
    && git checkout "$LATEST_TAG"

# Install dependencies (frozen lockfile for reproducibility)
RUN pnpm install --frozen-lockfile || pnpm install

# Build the application
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build

# Force pnpm for UI build (Bun may fail on ARM architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Prune dev dependencies to reduce size
RUN CI=true pnpm prune --prod

# ---- Stage 2: Runtime (minimal, hardened) ----
FROM docker.io/node:22-bookworm-slim

# Metadata
LABEL maintainer="openclaw" \
      description="OpenClaw Gateway — rootless, hardened for Podman" \
      org.opencontainers.image.source="https://github.com/openclaw/openclaw"

# Install only runtime essentials (no build tools, no curl for smaller surface)
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      tini \
      ca-certificates \
      wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

WORKDIR /app

# Copy only built artifacts from builder stage
COPY --from=builder /build/dist ./dist
COPY --from=builder /build/node_modules ./node_modules
COPY --from=builder /build/package.json ./package.json

# Create non-root user directories with correct permissions
# The node user (uid 1000) already exists in the base image
RUN mkdir -p /home/node/.openclaw/workspace \
             /home/node/.openclaw/credentials \
             /home/node/.openclaw/sessions \
             /home/node/.openclaw/logs \
             /tmp/openclaw && \
    chown -R node:node /app /home/node/.openclaw /tmp/openclaw

ENV NODE_ENV=production \
    HOME=/home/node

# Security: run as non-root user (uid 1000)
USER node

# Health check using wget (smaller than curl)
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:18789/ || exit 1

EXPOSE 18789

# Use tini as PID 1 for proper signal handling and zombie reaping
ENTRYPOINT ["tini", "--"]

# Default: start gateway bound to loopback (overridden in compose for container networking)
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]