# Multi-stage build for a fully static Faro binary using musl.
#
# Usage:
#   docker build -t faro-builder .
#   docker cp $(docker create faro-builder):/build/faro .

# ── Stage 1: Build ──────────────────────────────────────────
FROM crystallang/crystal:1.20.1-alpine AS builder

RUN apk add --no-cache sqlite-dev sqlite-static

WORKDIR /build

COPY shard.yml shard.lock ./
RUN shards install --production

COPY . .
RUN crystal build src/main.cr --static --release -o faro

# ── Stage 2: Scratch ────────────────────────────────────────
FROM scratch
COPY --from=builder /build/faro /faro
ENTRYPOINT ["/faro"]
