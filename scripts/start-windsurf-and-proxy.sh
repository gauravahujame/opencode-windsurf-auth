#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Windsurf All-in-One Container Entrypoint
#
# Two modes of operation:
#
# 1. AUTO mode (credentials provided):
#    Set WINDSURF_CSRF_TOKEN and WINDSURF_API_KEY.
#    The language server starts immediately, followed by the proxy.
#
# 2. GUI mode (manual login):
#    Omit credentials. A VNC server + XFCE desktop + Windsurf IDE are started.
#    Connect via VNC, log in to Windsurf manually, and the script will
#    auto-extract credentials and start the proxy.
#
# Required for AUTO mode:
#   WINDSURF_API_KEY     - Codeium API key
#   WINDSURF_CSRF_TOKEN  - CSRF token (UUID format)
#
# Optional environment variables:
#   WINDSURF_PORT        - gRPC port for language server (default: 42101)
#   WINDSURF_VERSION     - Version string (default: 1.96.0)
#   EXTENSION_SERVER_PORT - Extension server port (default: 42102)
#   HOST                 - Proxy HTTP bind address (default: 0.0.0.0)
#   PORT                 - Proxy HTTP port (default: 42100)
#   API_KEY              - Bearer token to protect HTTP endpoints
#   WINDSURF_IDE_PATH    - Path to Windsurf IDE binary (default: /opt/windsurf/windsurf)
#   DISPLAY              - X11 display (default: :1)
#   VNC_PORT             - VNC port (default: 5901)
#   VNC_PASSWORD         - VNC password (default: windsurf)
# ============================================================================

LANGUAGE_SERVER="${WINDSURF_LANGUAGE_SERVER_PATH:-./src/bin/language_server_linux_x64}"
WINDSURF_PORT="${WINDSURF_PORT:-42101}"
EXTENSION_SERVER_PORT="${EXTENSION_SERVER_PORT:-42102}"
WINDSURF_VERSION="${WINDSURF_VERSION:-1.9600.41}"
API_SERVER_URL="${WINDSURF_API_SERVER_URL:-https://server.self-serve.windsurf.com}"
INFERENCE_SERVER_URL="${WINDSURF_INFERENCE_URL:-https://inference.codeium.com}"
PROXY_HOST="${HOST:-0.0.0.0}"
PROXY_PORT="${PORT:-42100}"
WINDSURF_IDE="${WINDSURF_IDE_PATH:-/usr/share/devin-desktop/devin-desktop}"
DISPLAY_NUM="${DISPLAY:-:1}"
VNC_PORT="${VNC_PORT:-5901}"
VNC_PASS="${VNC_PASSWORD:-windsurf}"

log() {
  echo "[$(date -Iseconds)] [$1] $2"
}

# ============================================================================
# Common: Cleanup helper
# ============================================================================

CLEANUP_DONE=false
cleanup() {
  if [[ "$CLEANUP_DONE" == "true" ]]; then return; fi
  CLEANUP_DONE=true
  log "INFO" "Shutting down..."

  if [[ -n "${LS_PID:-}" ]]; then
    kill "$LS_PID" 2>/dev/null || true
    wait "$LS_PID" 2>/dev/null || true
  fi
  if [[ -n "${IDE_PID:-}" ]]; then
    kill "$IDE_PID" 2>/dev/null || true
    wait "$IDE_PID" 2>/dev/null || true
  fi
  if [[ -n "${VNC_PID:-}" ]]; then
    kill "$VNC_PID" 2>/dev/null || true
  fi
  if [[ -n "${X_PID:-}" ]]; then
    kill "$X_PID" 2>/dev/null || true
  fi
  if [[ -n "${EXT_SERVER_PID:-}" ]]; then
    kill "$EXT_SERVER_PID" 2>/dev/null || true
  fi

  exit 0
}
trap cleanup SIGINT SIGTERM

# ============================================================================
# Common: Start proxy server
# ============================================================================

start_proxy() {
  log "INFO" "Starting proxy server on $PROXY_HOST:$PROXY_PORT..."
  log "INFO" "  API key protection: ${API_KEY:+enabled}"
  exec bun run dist/src/standalone-server.js
}

# ============================================================================
# Common: Wait for language server port
# ============================================================================

wait_for_language_server() {
  local port="$1"
  local pid="$2"
  log "INFO" "Waiting for language server to be ready on port $port..."

  for _ in $(seq 1 30); do
    if ss -tlnp 2>/dev/null | grep -q ":$port " || \
       netstat -tlnp 2>/dev/null | grep -q ":$port " || \
       (command -v nc >/dev/null 2>&1 && nc -z localhost "$port" 2>/dev/null); then
      log "INFO" "Language server is ready on port $port"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      log "ERROR" "Language server exited early. Logs:"
      cat /tmp/language_server.log 2>/dev/null || true
      return 1
    fi
    sleep 1
  done

  log "ERROR" "Language server did not start listening on port $port within 30s"
  log "ERROR" "Logs:"
  cat /tmp/language_server.log 2>/dev/null || true
  kill "$pid" 2>/dev/null || true
  return 1
}

# ============================================================================
# AUTO mode: Credentials provided, start language server + proxy directly
# ============================================================================

# Start a dummy TCP listener on EXT_PORT that the language server connects back to.
# The language_server binary requires --extension_server_port to be reachable.
# We must send a proper HTTP 200 OK response for Connect-Protocol requests.
start_dummy_extension_server() {
  local port="$1"
  log "INFO" "Starting dummy extension server on port $port..."
  while true; do
    # Send a minimal HTTP 200 OK for Connect-Protocol unary responses
    printf 'HTTP/1.1 200 OK\r\nContent-Type: application/proto\r\nContent-Length: 0\r\n\r\n' | \
      nc -l -p "$port" 2>/dev/null || \
      printf 'HTTP/1.1 200 OK\r\nContent-Type: application/proto\r\nContent-Length: 0\r\n\r\n' | \
      nc -l "$port" 2>/dev/null || break
  done &
  EXT_SERVER_PID=$!
  sleep 0.3
}

run_auto_mode() {
  log "INFO" "=== AUTO MODE ==="
  log "INFO" "Using provided credentials. Starting language server and proxy..."

  if [[ -f "$LANGUAGE_SERVER" && ! -x "$LANGUAGE_SERVER" ]]; then
    chmod +x "$LANGUAGE_SERVER"
  fi

  if [[ ! -f "$LANGUAGE_SERVER" ]]; then
    log "ERROR" "Language server not found at: $LANGUAGE_SERVER"
    log "ERROR" "Set WINDSURF_LANGUAGE_SERVER_PATH to the correct path."
    exit 1
  fi

  # CSRF token via env var (Windsurf 1.96+) - not --csrf_token arg
  export WINDSURF_CSRF_TOKEN

  # Create temp dirs required by standalone language server
  LS_DB_DIR="$(mktemp -d /tmp/windsurf_ls_db_XXXXXX)"
  LS_CODEIUM_DIR="$(mktemp -d /tmp/windsurf_ls_codeium_XXXXXX)"

  # Dummy extension server must be listening before LS starts
  start_dummy_extension_server "$EXTENSION_SERVER_PORT"

  log "INFO" "Starting Windsurf language server (standalone)..."
  log "INFO" "  Binary:    $LANGUAGE_SERVER"
  log "INFO" "  gRPC port: $WINDSURF_PORT"
  log "INFO" "  Ext port:  $EXTENSION_SERVER_PORT"
  log "INFO" "  Version:   $WINDSURF_VERSION"

  # API key is protobuf-encoded and piped via stdin (--stdin_initial_metadata).
  # CSRF token is in WINDSURF_CSRF_TOKEN env var.
  bun run scripts/encode-metadata.ts | \
    "$LANGUAGE_SERVER" \
      --api_server_url           "$API_SERVER_URL" \
      --inference_api_server_url "$INFERENCE_SERVER_URL" \
      --run_child \
      --enable_lsp \
      --extension_server_port    "$EXTENSION_SERVER_PORT" \
      --ide_name                 windsurf \
      --server_port              "$WINDSURF_PORT" \
      --lsp_port                 "$((WINDSURF_PORT + 1))" \
      --windsurf_version         "$WINDSURF_VERSION" \
      --stdin_initial_metadata \
      --database_dir             "$LS_DB_DIR" \
      --codeium_dir              "$LS_CODEIUM_DIR" \
      --workspace_id             standalone_workspace \
      > /tmp/language_server.log 2>&1 &

  LS_PID=$!
  log "INFO" "Language server PID: $LS_PID"

  if ! wait_for_language_server "$WINDSURF_PORT" "$LS_PID"; then
    exit 1
  fi

  # Initialize Cascade panel state so the LS responds to chat requests
  log "INFO" "Initializing Cascade panel state..."
  bun run scripts/init-cascade.ts || log "WARN" "InitializeCascadePanelState failed (non-fatal)"

  start_proxy
}

# ============================================================================
# GUI mode: Start VNC + Windsurf IDE, poll for credentials, then start proxy
# ============================================================================

run_gui_mode() {
  log "INFO" "=== GUI MODE ==="
  log "INFO" "No credentials provided. Starting Windsurf IDE via VNC for manual login."

  # Check if Windsurf IDE exists
  if [[ ! -f "$WINDSURF_IDE" ]]; then
    log "WARN" "Windsurf IDE not found at: $WINDSURF_IDE"
    log "WARN" ""
    log "WARN" "To use GUI mode, provide the Windsurf IDE Linux binary:"
    log "WARN" "  1. Download Windsurf for Linux from https://windsurf.com/download"
    log "WARN" "  2. Mount it into the container:"
    log "WARN" "     -v /path/to/windsurf:/opt/windsurf/windsurf"
    log "WARN" "  3. Or set WINDSURF_IDE_PATH to the correct path"
    log "WARN" ""
    log "WARN" "Alternatively, use AUTO mode by setting WINDSURF_CSRF_TOKEN and WINDSURF_API_KEY."
    exit 1
  fi

  chmod +x "$WINDSURF_IDE" 2>/dev/null || true

  # Start Xvfb (virtual framebuffer)
  log "INFO" "Starting Xvfb on display $DISPLAY_NUM..."
  Xvfb "$DISPLAY_NUM" -screen 0 1920x1080x24 +extension RANDR > /tmp/xvfb.log 2>&1 &
  X_PID=$!
  sleep 2
  if ! kill -0 "$X_PID" 2>/dev/null; then
    log "ERROR" "Xvfb failed to start. Logs:"
    cat /tmp/xvfb.log 2>/dev/null || true
    exit 1
  fi

  # Start VNC server
  log "INFO" "Starting VNC server on port $VNC_PORT..."
  printf '%s\n' "$VNC_PASS" | vncpasswd -f > /root/.vnc/passwd 2>/dev/null || \
    printf '%s\n' "$VNC_PASS" | tigervncpasswd -f > /root/.vnc/passwd 2>/dev/null || true
  chmod 600 /root/.vnc/passwd 2>/dev/null || true

  vncserver "$DISPLAY_NUM" \
    -rfbport "$VNC_PORT" \
    -rfbauth /root/.vnc/passwd \
    -geometry 1920x1080 \
    -depth 24 \
    -noxstartup \
    > /tmp/vnc.log 2>&1 &
  VNC_PID=$!
  sleep 2

  # Start XFCE desktop session
  DISPLAY="$DISPLAY_NUM" startxfce4 > /tmp/xfce.log 2>&1 &

  # Start Windsurf IDE
  log "INFO" "Starting Windsurf IDE..."
  DISPLAY="$DISPLAY_NUM" "$WINDSURF_IDE" > /tmp/windsurf_ide.log 2>&1 &
  IDE_PID=$!
  log "INFO" "Windsurf IDE PID: $IDE_PID"

  # Print connection info
  log "INFO" ""
  log "INFO" "╔══════════════════════════════════════════════════════════════════╗"
  log "INFO" "║  VNC server running on port $VNC_PORT                               ║"
  log "INFO" "║  Password: $VNC_PASS                                    ║"
  log "INFO" "║                                                                  ║"
  log "INFO" "║  Connect with any VNC client:                                    ║"
  log "INFO" "║    docker-host:$VNC_PORT                                         ║"
  log "INFO" "║                                                                  ║"
  log "INFO" "║  Or use built-in VNC viewer:                                     ║"
  log "INFO" "║    open vnc://docker-host:$VNC_PORT                                ║"
  log "INFO" "║                                                                  ║"
  log "INFO" "║  Then log in to Windsurf IDE manually.                           ║"
  log "INFO" "║  The proxy will start automatically after login.                   ║"
  log "INFO" "╚══════════════════════════════════════════════════════════════════╝"
  log "INFO" ""

  # Poll for credentials in Windsurf's state database
  log "INFO" "Polling for credentials (checking every 5 seconds)..."
  log "INFO" "Waiting for you to log in to Windsurf IDE via VNC..."

  local state_db="/root/.config/Windsurf/User/globalStorage/state.vscdb"
  local found_api_key=""
  local found_csrf=""

  for _ in $(seq 1 360); do  # 30 minutes timeout
    # Check if IDE is still running
    if ! kill -0 "$IDE_PID" 2>/dev/null; then
      log "WARN" "Windsurf IDE exited. Checking if language server started..."
    fi

    # Try to extract API key from state.vscdb
    if [[ -f "$state_db" ]]; then
      found_api_key=$(sqlite3 "$state_db" \
        "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus';" 2>/dev/null | \
        jq -r '.apiKey // empty' 2>/dev/null || true)
    fi

    # Try to extract CSRF token from running language server process
    local ls_pid
    ls_pid=$(pgrep -f "language_server" | head -1 || true)
    if [[ -n "$ls_pid" ]]; then
      found_csrf=$(ps ewww -p "$ls_pid" 2>/dev/null | \
        grep -o 'WINDSURF_CSRF_TOKEN=[^ ]*' | cut -d= -f2 | head -1 || true)
    fi

    if [[ -n "$found_api_key" && -n "$found_csrf" ]]; then
      log "INFO" "Credentials found!"
      log "INFO" "  API Key: ${found_api_key:0:20}..."
      log "INFO" "  CSRF:    $found_csrf"

      # Export for proxy
      export WINDSURF_API_KEY="$found_api_key"
      export WINDSURF_CSRF_TOKEN="$found_csrf"

      # Wait for language server port
      if wait_for_language_server "$WINDSURF_PORT" "$ls_pid"; then
        start_proxy
      else
        log "ERROR" "Language server found but port not responding."
        exit 1
      fi
    fi

    sleep 5
  done

  log "ERROR" "Timed out waiting for credentials (30 minutes)."
  log "ERROR" "Please log in to Windsurf IDE via VNC and try again."
  exit 1
}

# ============================================================================
# Main: Detect mode and run
# ============================================================================

log "INFO" "Windsurf All-in-One Container Starting..."
log "INFO" "  Proxy will bind to: $PROXY_HOST:$PROXY_PORT"

if [[ -n "${WINDSURF_API_KEY:-}" && -n "${WINDSURF_CSRF_TOKEN:-}" ]]; then
  run_auto_mode
else
  run_gui_mode
fi
