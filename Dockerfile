#
# STAGE 1 - Build.
#
FROM rust:1.81-alpine3.20 AS builder

# Install build dependencies
RUN apk add --no-cache \
    musl-dev \
    openssl-dev \
    openssl-libs-static \
    pkgconfig \
    ca-certificates \
    alpine-sdk \
    perl \
    make \
    gcc

# Set working directory
WORKDIR /app

# Copy dependency files
COPY Cargo.toml Cargo.lock ./
COPY rust-toolchain.toml ./

# Copy source code
COPY src ./src

# Build the application
# Set environment variables for OpenSSL static linking
ENV OPENSSL_STATIC=1 \
    PKG_CONFIG_ALL_STATIC=1 \
    PKG_CONFIG_ALLOW_CROSS=1
RUN cargo build --release --locked



#
# STAGE 2 - Runtime.
#
FROM alpine:3.20

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    dumb-init

# Create non-root user
RUN addgroup -g 1000 nwr && \
    adduser -u 1000 -G nwr -s /bin/sh -D nwr

# Set working directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/target/release/nats-webhook-relay /app/bin/nats-webhook-relay

# Change ownership
RUN chown -R nwr:nwr /app

# Switch to non-root user
USER nwr

# Set environment variables
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Set entrypoint
ENTRYPOINT ["dumb-init", "--", "/app/bin/nats-webhook-relay"]

# Default command
CMD []
