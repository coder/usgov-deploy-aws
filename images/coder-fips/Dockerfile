# =============================================================================
# Coder FIPS Server Image
# =============================================================================
#
# Lightweight container image for running the Coder server binary built with
# Go's native FIPS 140-3 cryptographic module (GOFIPS140=latest).
#
# This image:
#   - Uses Alpine 3.19 as the base (matches Coder's official image pattern)
#   - Includes only runtime dependencies (no build tools, no Go)
#   - Runs as non-root user coder (UID 1000)
#   - Uses tini as PID 1 for proper signal handling
#   - Expects the FIPS-built coder binary to be COPY'd in at build time
#
# The coder binary is built separately in the CI pipeline (coder-fips:build)
# to keep the image layer minimal and the build stage cacheable.
#
# Build context expects:
#   ./coder-fips   — The FIPS-compiled Coder binary (linux/amd64)
#
# =============================================================================

FROM alpine:3.19 AS base

LABEL maintainer="platform-team@coder4gov.com" \
      description="Coder server with FIPS 140-3 (Go native) for coder4gov.com" \
      org.opencontainers.image.title="coder-fips" \
      org.opencontainers.image.description="Coder server built with GOFIPS140=latest — FIPS 140-3 compliant" \
      org.opencontainers.image.vendor="coder4gov.com"

# ---------------------------------------------------------------------------
# Runtime dependencies
# ---------------------------------------------------------------------------
# ca-certificates — TLS certificate validation for outbound connections
# curl            — Health checks (liveness/readiness probes)
# git             — Template provisioning (Coder clones Git repos)
# openssh-client  — SSH-based Git operations in templates
# tini            — Lightweight init (PID 1) for signal forwarding & zombie reaping
# ---------------------------------------------------------------------------
RUN apk add --no-cache \
        ca-certificates \
        curl \
        git \
        openssh-client \
        tini

# ---------------------------------------------------------------------------
# Coder user (non-root, UID 1000)
# ---------------------------------------------------------------------------
# Matches the UID used in Coder's official images and Kubernetes security
# contexts. The Coder process runs entirely unprivileged.
# ---------------------------------------------------------------------------
RUN addgroup -g 1000 coder && \
    adduser -D -u 1000 -G coder coder

# ---------------------------------------------------------------------------
# Coder binary
# ---------------------------------------------------------------------------
# The binary is built in the CI pipeline with:
#   GOFIPS140=latest CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
#     go build -tags enterprise \
#       -ldflags "-s -w -X github.com/coder/coder/v2/buildinfo.tag=${CODER_VERSION}" \
#       -o coder-fips ./enterprise/cmd/coder
#
# It embeds the frontend (site/out) and runs in FIPS mode by default
# (GODEBUG=fips140=on is baked in via GOFIPS140=latest at build time).
# ---------------------------------------------------------------------------
COPY --chown=coder:coder --chmod=755 coder-fips /opt/coder

# ---------------------------------------------------------------------------
# Runtime configuration
# ---------------------------------------------------------------------------
USER coder
EXPOSE 3000

# tini as PID 1 handles SIGTERM/SIGINT forwarding and zombie reaping.
# The coder binary starts in server mode by default.
ENTRYPOINT ["/sbin/tini", "--", "/opt/coder", "server"]
