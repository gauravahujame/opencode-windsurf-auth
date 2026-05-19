#!/usr/bin/env bash
#
# OpenCode Windsurf Auth Plugin - Installer
#
# This script:
# 1. Checks for Bun runtime
# 2. Clones/updates the repository
# 3. Builds the project
# 4. Starts the proxy server
# 5. Configures OpenCode using the OFFICIAL provider format
#
# Usage:
#   bash install.sh
#
# Recommended:
#   curl -fsSL https://raw.githubusercontent.com/gabslocked/opencode-windsurf-auth/main/install.sh | bash
#

set -euo pipefail

# =========================================================
# Colors
# =========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =========================================================
# Configuration
# =========================================================

REPO_URL="https://github.com/gabslocked/opencode-windsurf-auth.git"

INSTALL_DIR="$HOME/.opencode-windsurf-auth"

CONFIG_DIR="$HOME/.config/opencode"
CONFIG_FILE="$CONFIG_DIR/opencode.json"

PROXY_PORT="42100"
PROXY_URL="http://127.0.0.1:${PROXY_PORT}"

# =========================================================
# Logging
# =========================================================

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
  echo -e "${RED}[✗]${NC} $1"
}

# =========================================================
# Utilities
# =========================================================

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# =========================================================
# Bun
# =========================================================

check_bun() {
  log_info "Checking Bun runtime..."

  if command_exists bun; then
    local version
    version=$(bun --version)

    log_success "Found Bun ${version}"
    return
  fi

  log_warn "Bun not found. Installing..."

  curl -fsSL https://bun.sh/install | bash

  export PATH="$HOME/.bun/bin:$PATH"

  if command_exists bun; then
    local version
    version=$(bun --version)

    log_success "Installed Bun ${version}"
  else
    log_error "Failed to install Bun"
    exit 1
  fi
}

# =========================================================
# Windsurf
# =========================================================

check_windsurf() {
  log_info "Checking Windsurf..."

  if pgrep -f "windsurf" >/dev/null 2>&1 || \
     pgrep -f "language_server" >/dev/null 2>&1; then

    log_success "Windsurf appears to be running"
    return
  fi

  log_warn "Windsurf does not appear to be running"
  echo "Start Windsurf before using the proxy."
}

# =========================================================
# Clone repo
# =========================================================

clone_repo() {
  log_info "Preparing repository..."

  if [ -d "$INSTALL_DIR/.git" ]; then
    log_info "Updating existing repository..."

    git -C "$INSTALL_DIR" pull || \
      log_warn "Failed to update repository. Continuing..."
  else
    log_info "Cloning repository..."

    git clone "$REPO_URL" "$INSTALL_DIR"
  fi

  log_success "Repository ready"
}

# =========================================================
# Build
# =========================================================

build_project() {
  log_info "Installing dependencies..."

  cd "$INSTALL_DIR"

  bun install

  log_info "Building project..."

  bun run build

  log_info "Copying necessary files..."

  # Copy grpc-wrapper.mjs to dist directory for runtime access
  cp grpc-wrapper.mjs dist/

  # Copy package.json to dist directory for npm operations
  cp package.json dist/

  log_success "Build completed"
}

# =========================================================
# Start proxy
# =========================================================

start_proxy() {
  cd "$INSTALL_DIR"

  log_info "Checking proxy health..."

  if curl -fsS "${PROXY_URL}/health" >/dev/null 2>&1; then
    log_success "Proxy already running"
    return
  fi

  log_info "Starting proxy server..."

  if bun run start >/tmp/opencode-windsurf.log 2>&1 & then
    sleep 3
  else
    log_error "Failed to start proxy"
    exit 1
  fi

  if curl -fsS "${PROXY_URL}/health" >/dev/null 2>&1; then
    log_success "Proxy started successfully"
  else
    log_warn "Proxy health endpoint not responding yet"
    log_warn "Check logs: /tmp/opencode-windsurf.log"
  fi
}

# =========================================================
# Configure OpenCode
# =========================================================

configure_opencode() {
  log_info "Configuring OpenCode..."

  mkdir -p "$CONFIG_DIR"

  if [ -f "$CONFIG_FILE" ]; then
    local backup
    backup="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

    cp "$CONFIG_FILE" "$backup"

    log_success "Backed up existing config"
  fi

  cat > "$CONFIG_FILE" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",

  "provider": {
    "windsurf": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Windsurf",

      "options": {
        "baseURL": "${PROXY_URL}/v1"
      },

      "models": {
        "claude-4.5-sonnet": {
          "name": "Claude 4.5 Sonnet"
        },

        "gpt-5.2": {
          "name": "GPT 5.2"
        },

        "swe-1.5": {
          "name": "SWE 1.5"
        },

        "gemini-3.0-pro": {
          "name": "Gemini 3.0 Pro"
        }
      }
    }
  }
}
EOF

  log_success "OpenCode configured"
}

# =========================================================
# Validate
# =========================================================

validate_setup() {
  log_info "Validating installation..."

  if curl -fsS "${PROXY_URL}/health" >/dev/null 2>&1; then
    log_success "Health endpoint OK"
  else
    log_warn "Health endpoint failed"
  fi

  if curl -fsS "${PROXY_URL}/v1/models" >/dev/null 2>&1; then
    log_success "OpenAI-compatible API detected"
  else
    log_warn "Could not validate /v1/models"
  fi
}

# =========================================================
# Completion
# =========================================================

print_completion() {
  echo ""
  echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
  echo -e "${GREEN}   OpenCode Windsurf Setup Complete${NC}"
  echo -e "${GREEN}═══════════════════════════════════════════════${NC}"
  echo ""

  echo -e "${BLUE}Proxy:${NC}"
  echo "  ${PROXY_URL}"
  echo ""

  echo -e "${BLUE}OpenCode Config:${NC}"
  echo "  ${CONFIG_FILE}"
  echo ""

  echo -e "${BLUE}Available Models:${NC}"
  echo "  @windsurf/claude-4.5-sonnet"
  echo "  @windsurf/gpt-5.2"
  echo "  @windsurf/swe-1.5"
  echo "  @windsurf/gemini-3.0-pro"
  echo ""

  echo -e "${BLUE}Health Check:${NC}"
  echo "  curl ${PROXY_URL}/health"
  echo ""

  echo -e "${BLUE}Logs:${NC}"
  echo "  tail -f /tmp/opencode-windsurf.log"
  echo ""

  echo -e "${YELLOW}Restart OpenCode after installation.${NC}"
  echo ""
}

# =========================================================
# Main
# =========================================================

main() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   OpenCode Windsurf Auth Installer          ║${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  check_bun
  check_windsurf
  clone_repo
  build_project
  start_proxy
  configure_opencode
  validate_setup
  print_completion
}

main "$@"
