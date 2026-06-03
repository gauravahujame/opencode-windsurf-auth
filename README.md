# 🌊 OpenCode Windsurf Auth Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bun](https://img.shields.io/badge/Bun-1.0+-black?logo=bun)](https://bun.sh)
[![Windsurf](https://img.shields.io/badge/Windsurf-Compatible-blue)](https://codeium.com/windsurf)
[![OpenCode](https://img.shields.io/badge/OpenCode-Plugin-green)](https://github.com/opencode-ai/opencode)

> **Unlock 90+ AI models from Windsurf/Codeium in OpenCode** — Claude 4.5 Sonnet, GPT-5.2, Gemini 3.0, SWE-1.5, and many more!

This plugin exposes Windsurf's local language server as an **OpenAI-compatible REST API**, enabling OpenCode to use Windsurf's premium models without additional API keys or cloud authentication.

## ✨ Features

- 🚀 **90+ Models**: Claude 4.5, GPT-5.2, Gemini 3.0, SWE-1.5, Kimi, Grok, and more
- 🔌 **OpenAI-Compatible**: Drop-in replacement for OpenAI API (`/v1/chat/completions`)
- 🔄 **Auto-Discovery**: Automatically finds Windsurf credentials from running process
- 🛡️ **Auto-Retry**: Handles Windsurf restarts gracefully with automatic reconnection
- 📡 **Streaming**: Full SSE streaming support for real-time responses
- 🎯 **Tool Calling**: Prompt-based tool calling support

## 📋 Requirements

- [Bun](https://bun.sh) runtime (Node.js not supported)
- [Windsurf](https://codeium.com/windsurf) IDE running
- [OpenCode](https://github.com/opencode-ai/opencode) CLI

## 🚀 Quick Start

### One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/gabslocked/opencode-windsurf-auth/main/install.sh | bash
```

### Manual Installation

1. **Clone the repository:**
```bash
git clone https://github.com/gabslocked/opencode-windsurf-auth.git
cd opencode-windsurf-auth
```

2. **Install dependencies:**
```bash
bun install
```

3. **Build the plugin:**
```bash
bun run build
```

4. **Deploy to OpenCode:**
```bash
mkdir -p ~/.config/opencode/node_modules/opencode-windsurf-auth
cp -r dist ~/.config/opencode/node_modules/opencode-windsurf-auth/
```

5. **Configure OpenCode** (~/.config/opencode/opencode.json):
```json
{
  "provider": {
    "windsurf": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Windsurf",
      "options": {
        "baseURL": "http://127.0.0.1:42100/v1"
      },
      "models": {
        "claude-4.5-sonnet": {
          "name": "Claude 4.5 Sonnet"
        },
        "gpt-5.2": {
          "name": "GPT 5.2"
        },
        "swe-1.6": {
          "name": "SWE 1.6"
        },
        "gemini-3.0-pro": {
          "name": "Gemini 3.0 Pro"
        }
      }
    }
  }
}
```

6. **Restart OpenCode** and start using Windsurf models!

## 🐳 Docker Deployment (All-in-One)

Run **both the Windsurf language server and the proxy** inside a single container. No external Windsurf instance needed.

The container supports **two modes**:

| Mode | Credentials | Use Case |
|------|-------------|----------|
| **AUTO** | Provide `WINDSURF_CSRF_TOKEN` + `WINDSURF_API_KEY` | Fastest. Language server starts immediately. |
| **GUI** | Omit credentials | Run full Windsurf IDE inside container via VNC, log in manually. |

### Prerequisites

- Docker & Docker Compose
- A Codeium/Windsurf account

### Build

The Dockerfile is in this repo but the build context must be the **parent directory** (it includes the `windsurf-sdk` sibling project):

```bash
# Clone the main project (windsurf-sdk is a local sibling dependency)
git clone https://github.com/gabslocked/opencode-windsurf-auth.git
cd opencode-windsurf-auth

# The Dockerfile expects windsurf-sdk in the parent directory.
# If you don't have it, the build will fail. Ensure you have:
#   ../windsurf-sdk/     (local package dependency)
#
# Build from the parent directory:
docker build --platform linux/amd64 -f Dockerfile -t windsurf-proxy ../
```

> **Note for ARM hosts (Apple Silicon, Raspberry Pi):** The `--platform linux/amd64` flag is required because the Windsurf language server binary is x86-64. Colima/Docker Desktop will use QEMU emulation.

---

### Mode 1: AUTO (Credentials Provided)

Best for when you already have credentials from a running Windsurf IDE.

#### Extract Credentials from Windsurf (one-time)

**macOS:**
```bash
# Find the Windsurf language server PID
PID=$(pgrep -f language_server_macos)

# CSRF token (Windsurf 1.96+)
WINDSURF_CSRF_TOKEN=$(ps ewww -p $PID | grep -o 'WINDSURF_CSRF_TOKEN=[^ ]*' | cut -d= -f2)

# API key from Windsurf's state database
WINDSURF_API_KEY=$(sqlite3 "$HOME/Library/Application Support/Windsurf/User/globalStorage/state.vscdb" \
  "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus';" | jq -r '.apiKey')

echo "WINDSURF_CSRF_TOKEN=$WINDSURF_CSRF_TOKEN"
echo "WINDSURF_API_KEY=$WINDSURF_API_KEY"
```

**Linux:**
```bash
PID=$(pgrep -f language_server_linux)
WINDSURF_CSRF_TOKEN=$(cat /proc/$PID/environ | tr '\0' '\n' | grep WINDSURF_CSRF_TOKEN | cut -d= -f2)
WINDSURF_API_KEY=$(sqlite3 "$HOME/.config/Windsurf/User/globalStorage/state.vscdb" \
  "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus';" | jq -r '.apiKey')
```

#### Run with Docker Compose

```bash
export WINDSURF_CSRF_TOKEN="your-csrf-token"
export WINDSURF_API_KEY="your-api-key"
export WINDSURF_VERSION="1.9600.41"
export API_KEY="<your-api-token>"  # optional: protects the HTTP API

docker-compose up -d
```

#### Run with Docker (without Compose)

```bash
docker run -d \
  --name windsurf-proxy \
  --platform linux/amd64 \
  -p 42100:42100 \
  -e WINDSURF_CSRF_TOKEN="your-token" \
  -e WINDSURF_API_KEY="your-key" \
  -e WINDSURF_VERSION="1.9600.41" \
  -e HOST=0.0.0.0 \
  windsurf-proxy
```

---

### Mode 2: GUI (Manual Login via VNC)

Best when you don't want to extract credentials or want a fully self-contained setup.

The container includes the **full Windsurf IDE** (Devin Desktop) and starts:
- **Xvfb** + **TigerVNC** on port `5901`
- **XFCE desktop**
- **Windsurf IDE** inside the container

```bash
# Do NOT set WINDSURF_CSRF_TOKEN or WINDSURF_API_KEY
docker run -d \
  --name windsurf-proxy \
  --platform linux/amd64 \
  -p 42100:42100 \
  -p 5901:5901 \
  -e HOST=0.0.0.0 \
  -e VNC_PASSWORD=myvncpass \
  windsurf-proxy
```

#### 1. Connect via VNC

The container prints the VNC connection details on startup:

```
VNC server running on port 5901
Password: windsurf
Connect with: vnc://localhost:5901
```

Using macOS built-in VNC viewer:
```bash
open vnc://localhost:5901
```

Or any VNC client (TigerVNC, RealVNC, Remmina, etc.).

#### 2. Log in to Windsurf

Inside the VNC desktop:
1. Open the Windsurf IDE from the desktop
2. Click **Sign In** and complete the login flow
3. The container script detects the credentials automatically

#### 3. Proxy starts automatically

Once login is complete, the script:
- Extracts credentials from the Windsurf state database
- Starts the language server
- Starts the proxy on port 42100

---

## 🏠 Debian Homelab Deployment

Deploy on a headless Debian/Ubuntu server and access the proxy from any machine on your network.

### 1. Clone & Build on the Server

```bash
# SSH into your homelab
ssh user@homelab

# Clone the project. The build context must include the local windsurf-sdk
# sibling directory. If you don't have it, download/copy it to the parent.
cd /opt
git clone https://github.com/gabslocked/opencode-windsurf-auth.git

# Build (context is parent dir to include ../windsurf-sdk)
cd opencode-windsurf-auth
docker build --platform linux/amd64 -f Dockerfile -t windsurf-proxy ../
```

### 2. Create a systemd Service (optional, for auto-start)

```bash
sudo tee /etc/systemd/system/windsurf-proxy.service << 'EOF'
[Unit]
Description=Windsurf Proxy
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker run -d \
  --name windsurf-proxy \
  --platform linux/amd64 \
  --restart unless-stopped \
  -p 42100:42100 \
  -e WINDSURF_CSRF_TOKEN=%i \
  -e WINDSURF_API_KEY=%i \
  -e HOST=0.0.0.0 \
  -e API_KEY=${API_KEY} \
  windsurf-proxy
ExecStop=/usr/bin/docker stop windsurf-proxy
ExecStopPost=/usr/bin/docker rm windsurf-proxy

[Install]
WantedBy=multi-user.target
EOF

# You will need to set credentials separately or use a .env file
```

Better: use Docker Compose with a `.env` file:

```bash
cd /opt/opencode-windsurf-auth
# Create .env file with your credentials
cat > .env << 'EOF'
WINDSURF_CSRF_TOKEN=your-csrf-token
WINDSURF_API_KEY=your-api-key
WINDSURF_VERSION=1.9600.41
API_KEY=<your-api-token>
EOF

# Start
docker-compose up -d
```

### 3. Access from Any Machine

```bash
# Health check
curl http://homelab-ip:42100/health

# List models
curl http://homelab-ip:42100/v1/models
```

---

## 🔌 API Usage (cURL Examples)

The proxy exposes an **OpenAI-compatible API** at `http://host:42100/v1`.

### Health Check

```bash
curl http://localhost:42100/health
# {"ok":true,"windsurf":true,"mode":"auto-discovery"}
```

### List Available Models

```bash
curl http://localhost:42100/v1/models
```

With API key protection:
```bash
curl http://localhost:42100/v1/models \
  -H "Authorization: Bearer <your-api-token>"
```

### Non-Streaming Chat Completion

```bash
curl -X POST http://localhost:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-4.5-sonnet",
    "messages": [{"role": "user", "content": "Explain quantum computing in one paragraph"}]
  }'
```

### Streaming Chat Completion (SSE)

```bash
curl -X POST http://localhost:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-4.5-sonnet",
    "messages": [{"role": "user", "content": "Write a haiku about code"}],
    "stream": true
  }'
```

### With API Key Protection

```bash
curl -X POST http://localhost:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-api-token>" \
  -d '{
    "model": "gpt-5.2",
    "messages": [{"role": "user", "content": "What is the capital of France?"}]
  }'
```

### Model Variants

Many models support performance tiers. Use the `:` separator:

```bash
# GPT-5.2 with high reasoning budget
curl -X POST http://localhost:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5.2:high",
    "messages": [{"role": "user", "content": "Debug this Python script"}]
  }'

# Claude with thinking mode
curl -X POST http://localhost:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-4.5-sonnet:thinking",
    "messages": [{"role": "user", "content": "Solve this math problem step by step"}]
  }'
```

---

### Using with OpenCode or Other Clients

Point your client to the Docker-exposed endpoint:

```json
{
  "provider": {
    "windsurf": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Windsurf",
      "options": {
        "baseURL": "http://homelab-ip:42100/v1",
        "apiKey": "<your-api-token>"
      }
    }
  }
}
```

## 🧪 Testing

Run the built-in tests to verify everything works:

```bash
bun test
```

Test specific models:
```bash
# Test Claude 4.5 Sonnet
curl -X POST http://127.0.0.1:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-4.5-sonnet",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Test SWE-1.5
curl -X POST http://127.0.0.1:42100/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "swe-1.5",
    "messages": [{"role": "user", "content": "Review this code"}]
  }'
```

## 🎯 Supported Models

| Category | Models |
|----------|--------|
| **Claude** | claude-4.5-sonnet, claude-4.5-opus, claude-4.6-opus, claude-3.7-sonnet, claude-3.5-sonnet |
| **GPT** | gpt-5.2, gpt-5.2-codex, gpt-5, gpt-4.5, gpt-4o, gpt-4o-mini |
| **Gemini** | gemini-3.0-pro, gemini-3.0-flash, gemini-2.5-pro, gemini-2.5-flash |
| **SWE** | swe-1.5, swe-1.6 |
| **O-Series** | o3, o3-pro, o4-mini |
| **Other** | kimi-k2, kimi-k2.5, grok-3, grok-code-fast, minimax-m2.1, glm-5 |

### Model Variants

Many models support performance variants:

```bash
# GPT-5.2 with different reasoning budgets
gpt-5.2:low
gpt-5.2:medium        # default
gpt-5.2:high
gpt-5.2:xhigh

# Claude with thinking mode
claude-4.5-sonnet:thinking
claude-4.5-opus:thinking

# Gemini with reasoning budgets
gemini-3.0-flash:minimal
gemini-3.0-flash:low
gemini-3.0-flash:medium
gemini-3.0-flash:high
```

## 🔧 How It Works

```
┌─────────────┐      OpenAI API      ┌──────────────┐
│   OpenCode  │ ◄──────────────────► │  Plugin      │
│   CLI       │    localhost:42100   │  (Bun HTTP)  │
└─────────────┘                      └──────┬───────┘
                                            │
                                            │ gRPC
                                            │
┌─────────────┐                      ┌──────▼───────┐
│  Windsurf   │ ◄──────────────────► │  Language    │
│  IDE        │   local process      │  Server      │
└─────────────┘                      └──────────────┘
```

1. **Discovery**: Plugin scans for running Windsurf process to extract CSRF token (from `WINDSURF_CSRF_TOKEN` environment variable for Windsurf 1.96+, or `--csrf_token` argument for older versions) and gRPC port
2. **Translation**: Converts OpenAI REST API calls to Windsurf gRPC messages
3. **Streaming**: Returns SSE chunks as they arrive from the language server
4. **Auto-Recovery**: Retries with fresh credentials if Windsurf restarts

## 📁 Project Structure

```
opencode-windsurf-auth/
├── src/
│   ├── plugin.ts              # Main HTTP server & OpenAI API endpoints
│   ├── standalone-server.ts   # Docker/external access server (0.0.0.0, env var auth)
│   ├── server.ts              # Standalone server entry point (local only)
│   ├── index.ts               # Package exports
│   ├── bin/
│   │   └── language_server_linux_x64  # Windsurf language server binary
│   └── plugin/
│       ├── auth.ts            # Credential discovery (CSRF, port, API key)
│       ├── discovery.ts       # Dynamic protobuf field number discovery
│       ├── grpc-client.ts     # gRPC encoding/decoding + Cascade flow
│       ├── models.ts          # Model name -> enum mappings (90+)
│       └── types.ts           # TypeScript interfaces & enum values
├── dist/                      # Compiled output
├── tests/                     # Unit tests
├── Dockerfile                 # Docker image build (GUI + VNC + Windsurf IDE)
├── docker-compose.yml         # Docker Compose orchestration
├── .dockerignore              # Docker build exclusions
├── grpc-wrapper.mjs           # Node.js gRPC wrapper for Bun HTTP/2 compat
├── scripts/
│   ├── start-windsurf-and-proxy.sh  # Entrypoint: dual-mode (auto / GUI+VNC)
│   ├── encode-metadata.ts     # Protobuf Metadata encoder for stdin injection
│   ├── init-cascade.ts        # InitializeCascadePanelState gRPC call
│   └── download-windsurf-linux.sh   # Download Windsurf Linux .deb helper
├── install.sh                 # One-line installer
└── README.md                  # This file
```

**Architecture**: This plugin depends on `@windsurf/sdk` (local sibling package in `../windsurf-sdk/`) for core functionality including:
- Credential discovery (auth module)
- Model resolution (models module)
- Protobuf encoding (grpc module)
- Dynamic field discovery (discovery module)

## 🛠️ Development

```bash
# Install dependencies
bun install

# Type check
bun run typecheck

# Run tests
bun test

# Build for production
bun run build

# Watch mode for development
bun run dev
```

## 🐛 Troubleshooting

### "Connection failed: connect ECONNREFUSED"
- Make sure Windsurf is running
- Plugin will auto-retry with fresh credentials

### "StartCascade returned empty cascade_id"
- Windsurf may have restarted - plugin will auto-recover
- Check if your Windsurf subscription is active

### "gRPC error 12: unimplemented"
- Some models may not be available in your region/subscription

### Model not working?
- Check ~/.config/opencode/opencode.json has correct proxy URL
- Verify Windsurf is running: pgrep -f language_server
- Check plugin logs in OpenCode output

## 🔒 Security

- Plugin only connects to **localhost** (127.0.0.1) by default
- Uses Windsurf's existing authentication (no additional API keys)
- Credentials are read from Windsurf's process, never stored
- All communication stays on your machine
- **Docker mode**: Set `API_KEY` environment variable to protect external endpoints with Bearer token authentication

## 📄 License

MIT License — see LICENSE file

## 🙏 Credits

- Original project by [rsvedant/opencode-windsurf-auth](https://github.com/rsvedant/opencode-windsurf-auth)
- Fork maintained by [gabslocked](https://github.com/gabslocked)

- Built for [OpenCode](https://github.com/opencode-ai/opencode)
- Powered by [Windsurf](https://codeium.com/windsurf) / Codeium
- Uses [Bun](https://bun.sh) runtime

---

**Enjoy coding with premium AI models!** 🚀
