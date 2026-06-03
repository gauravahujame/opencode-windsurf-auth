# Windsurf API Proxy - Standalone Docker Image
#
# Build context must include the parent directory so the sibling windsurf-sdk
# package is available for the local file dependency.
#
# Example build from the parent directory:
#   docker build -f opencode-windsurf-auth/Dockerfile -t windsurf-proxy .
#
# Or with docker-compose from this directory:
#   docker-compose up --build

# ── Builder stage ─────────────────────────────────────────────────────────────
FROM oven/bun:1.2.14-debian AS builder

WORKDIR /app

COPY windsurf-sdk ./windsurf-sdk
COPY opencode-windsurf-auth ./opencode-windsurf-auth

# Build the SDK first
WORKDIR /app/windsurf-sdk
RUN bun install
RUN bun run build

# Build the main project
WORKDIR /app/opencode-windsurf-auth
# Fix local file-dep path for the Docker context (relative → absolute)
RUN sed -i 's|"file:../windsurf-sdk"|"file:/app/windsurf-sdk"|g' package.json
RUN bun install
# Replace bun's symlinked @windsurf/sdk with a real copy (avoids circular symlink errors in Docker).
# We only need dist/ + package.json for tsc and runtime.
RUN rm -rf node_modules/@windsurf/sdk && \
    mkdir -p node_modules/@windsurf/sdk && \
    cp -r /app/windsurf-sdk/dist node_modules/@windsurf/sdk/dist && \
    cp /app/windsurf-sdk/package.json node_modules/@windsurf/sdk/package.json
RUN bun run build

# ── Production stage ──────────────────────────────────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

# Install GUI, VNC, browser, and runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # GUI / X11 / VNC
    xvfb \
    tigervnc-standalone-server \
    tigervnc-common \
    xfce4 \
    xfce4-terminal \
    dbus-x11 \
    # Browser (for OAuth login flows)
    firefox \
    # Electron app dependencies
    libgtk-3-0 \
    libnotify4 \
    libnss3 \
    libxss1 \
    libasound2 \
    libxtst6 \
    libgbm1 \
    fonts-liberation \
    xdg-utils \
    libappindicator3-1 \
    # Utilities
    net-tools \
    iproute2 \
    netcat-traditional \
    sqlite3 \
    jq \
    curl \
    wget \
    ca-certificates \
    # Bun runtime dependencies
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Copy built artifacts from builder
WORKDIR /app/opencode-windsurf-auth
COPY --from=builder /app/opencode-windsurf-auth/dist ./dist
COPY --from=builder /app/opencode-windsurf-auth/node_modules ./node_modules

# Copy runtime files
COPY opencode-windsurf-auth/grpc-wrapper.mjs ./grpc-wrapper.mjs
COPY opencode-windsurf-auth/scripts ./scripts
COPY opencode-windsurf-auth/package.json ./package.json

# Copy the language server binary and entrypoint script (--chmod preserves execute bit at COPY time)
COPY --chmod=755 opencode-windsurf-auth/src/bin/language_server_linux_x64 ./src/bin/language_server_linux_x64
COPY --chmod=755 opencode-windsurf-auth/scripts/start-windsurf-and-proxy.sh ./start-windsurf-and-proxy.sh

# Download and install full Windsurf IDE (Devin Desktop) for GUI mode
RUN apt-get update && apt-get install -y --no-install-recommends \
        binutils \
        xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL -o /tmp/devin.deb \
        "https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt/pool/main/d/devin-desktop/Devin-linux-x64-3.0.12.deb" \
    && cd /tmp \
    && ar -x devin.deb \
    && tar -xf data.tar.xz -C / \
    && rm -rf /tmp/devin.deb /tmp/control.tar.* /tmp/data.tar.* /tmp/debian-binary \
    && chmod +x /usr/share/devin-desktop/devin-desktop \
    && ln -sf /usr/share/devin-desktop/devin-desktop /usr/local/bin/windsurf

# Create VNC config directory and xstartup script.
# The VNC password is set at container runtime by the entrypoint (vncpasswd/tigervncpasswd).
RUN mkdir -p /root/.vnc && \
    printf '%s\n' '#!/bin/sh' 'unset SESSION_MANAGER' 'unset DBUS_SESSION_BUS_ADDRESS' 'exec startxfce4 &' > /root/.vnc/xstartup && \
    chmod +x /root/.vnc/xstartup && \
    touch /root/.vnc/passwd && \
    chmod 600 /root/.vnc/passwd

# Proxy API
EXPOSE 42100
# VNC
EXPOSE 5901

# Default environment
ENV HOST=0.0.0.0
ENV PORT=42100
ENV WINDSURF_PORT=42101
ENV EXTENSION_SERVER_PORT=42102
ENV WINDSURF_VERSION=1.9600.41
ENV DISPLAY=:1
ENV VNC_PORT=5901
ENV VNC_PASSWORD=windsurf

# Start both language server and proxy
ENTRYPOINT ["./start-windsurf-and-proxy.sh"]
