# =============================================================================
# EMET Protocol — Multi-stage Docker Build
# =============================================================================
# Builds the complete EMET stack: core, cli, api, and proofs modules.
#
# Usage:
#   docker build -t emet-core .
#   docker run -p 3141:3141 emet-core           # Start API server
#   docker run emet-core emet --help            # Run CLI
#   docker run emet-core emet keygen            # Generate keys
#
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Dependencies
# -----------------------------------------------------------------------------
FROM node:20-alpine AS deps

WORKDIR /app

# Copy all package files first for better caching
COPY core/package*.json ./core/
COPY cli/package*.json ./cli/
COPY api/package*.json ./api/
COPY proofs/package*.json ./proofs/

# Install dependencies for each module
RUN cd core && npm ci --omit=dev && \
    cd ../cli && npm ci --omit=dev && \
    cd ../api && npm ci --omit=dev && \
    cd ../proofs && npm ci --omit=dev

# -----------------------------------------------------------------------------
# Stage 2: Production Image
# -----------------------------------------------------------------------------
FROM node:20-alpine AS production

LABEL org.opencontainers.image.title="EMET Protocol"
LABEL org.opencontainers.image.description="Epistemic Marker for Encoded Truth - Verifiable claims protocol"
LABEL org.opencontainers.image.source="https://github.com/clawdei-ai/emet-core"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S emet && \
    adduser -S emet -u 1001 -G emet

# Copy node_modules from deps stage
COPY --from=deps /app/core/node_modules ./core/node_modules
COPY --from=deps /app/cli/node_modules ./cli/node_modules
COPY --from=deps /app/api/node_modules ./api/node_modules
COPY --from=deps /app/proofs/node_modules ./proofs/node_modules

# Copy source code
COPY core/ ./core/
COPY cli/ ./cli/
COPY api/ ./api/
COPY proofs/ ./proofs/
COPY spec/ ./spec/
COPY examples/ ./examples/
COPY README.md ./

# Create data directory for API persistence
RUN mkdir -p /app/api/.data && chown -R emet:emet /app

# Make CLI executable and add to PATH
RUN chmod +x /app/cli/emet.js && \
    ln -s /app/cli/emet.js /usr/local/bin/emet

# Switch to non-root user
USER emet

# Environment
ENV NODE_ENV=production
ENV PORT=3141

# Expose API port
EXPOSE 3141

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:3141/ || exit 1

# Default: run the API server
CMD ["node", "api/server.js"]
