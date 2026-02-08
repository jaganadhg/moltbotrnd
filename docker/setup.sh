#!/usr/bin/env bash
# =============================================================================
# OpenClaw + Ollama — Podman Setup Script (rootless, secure)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_CMD=""

# --- Color output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { printf "${CYAN}[INFO]${NC}  %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

# --- Detect container runtime ---
detect_runtime() {
  if command -v podman-compose &>/dev/null; then
    COMPOSE_CMD="podman-compose"
    info "Detected: podman-compose"
  elif command -v podman &>/dev/null && podman compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="podman compose"
    info "Detected: podman compose (plugin)"
  elif command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    warn "Podman not found — falling back to docker compose"
  else
    err "Neither podman-compose nor docker compose found."
    err "Install podman-compose:  pip install podman-compose"
    err "  or:                    sudo dnf install podman-compose"
    exit 1
  fi
}

# --- Verify rootless mode ---
check_rootless() {
  if [[ "$(id -u)" -eq 0 ]]; then
    err "Do NOT run this script as root."
    err "Podman rootless runs under your regular user account."
    exit 1
  fi

  if command -v podman &>/dev/null; then
    if podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | grep -qi true; then
      ok "Podman is running in rootless mode"
    else
      warn "Podman may not be in rootless mode — verify with: podman info | grep -i rootless"
    fi
  fi
}

# --- Generate cryptographic token ---
generate_token() {
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  elif command -v python3 &>/dev/null; then
    python3 -c 'import secrets; print(secrets.token_hex(32))'
  else
    head -c 32 /dev/urandom | xxd -p | tr -d '\n'
  fi
}

# --- Create .env file with secrets ---
setup_env() {
  if [[ -f "$ENV_FILE" ]]; then
    info "Existing .env found — preserving gateway token"
    # Source to check if token exists
    set +u
    source "$ENV_FILE" 2>/dev/null || true
    set -u
  fi

  if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    OPENCLAW_GATEWAY_TOKEN="$(generate_token)"
    ok "Generated new gateway authentication token"
  fi

  cat > "$ENV_FILE" <<EOF
# OpenClaw Podman Environment — AUTO-GENERATED
# Keep this file secure (chmod 600). Never commit to version control.

# Gateway authentication token (REQUIRED)
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
EOF

  chmod 600 "$ENV_FILE"
  ok "Environment file created: $ENV_FILE (mode 600)"
}

# --- Build the OpenClaw image ---
build_image() {
  info "Building OpenClaw image (this may take several minutes on first run)..."
  cd "$SCRIPT_DIR"
  if ! $COMPOSE_CMD build openclaw; then
    err "OpenClaw image build failed. Check the output above."
    exit 1
  fi
  ok "OpenClaw image built successfully"
}

# --- Pull and start Ollama, then download Phi model ---
setup_ollama() {
  info "Cleaning up any existing containers..."
  cd "$SCRIPT_DIR"
  $COMPOSE_CMD down --remove-orphans 2>/dev/null || true

  info "Starting Ollama service..."
  $COMPOSE_CMD up -d ollama

  info "Waiting for Ollama to become healthy..."
  local retries=30
  while (( retries > 0 )); do
    if $COMPOSE_CMD exec ollama ollama list &>/dev/null; then
      break
    fi
    sleep 3
    (( retries-- ))
  done

  if (( retries == 0 )); then
    err "Ollama failed to start. Check logs: $COMPOSE_CMD logs ollama"
    exit 1
  fi
  ok "Ollama is healthy"

  info "Pulling Phi model (phi4-mini)... this may take a while on first run"
  $COMPOSE_CMD exec ollama ollama pull phi4-mini
  ok "Phi model (phi4-mini) downloaded"

  info "Available models:"
  $COMPOSE_CMD exec ollama ollama list
}

# --- Start all services ---
start_services() {
  info "Starting OpenClaw gateway..."
  cd "$SCRIPT_DIR"
  if ! $COMPOSE_CMD up -d ollama openclaw 2>&1; then
    err "Failed to start services. Check: $COMPOSE_CMD logs"
    exit 1
  fi

  # Verify gateway is running
  sleep 5
  if podman ps --filter name=openclaw-gateway --format '{{.Status}}' 2>/dev/null | grep -qi 'up'; then
    ok "All services started"
  else
    warn "Gateway container may not be running. Check: podman logs openclaw-gateway"
  fi
}

# --- Print summary ---
print_summary() {
  echo ""
  echo "============================================================================="
  printf "${GREEN} OpenClaw is running securely with Podman!${NC}\n"
  echo "============================================================================="
  echo ""
  printf "  Gateway:    ${CYAN}http://127.0.0.1:18789${NC}\n"
  printf "  Auth Token: ${YELLOW}${OPENCLAW_GATEWAY_TOKEN}${NC}\n"
  printf "  LLM Model:  ${CYAN}phi4-mini (via Ollama)${NC}\n"
  echo ""
  echo "  Security highlights:"
  echo "    - Rootless Podman (no host root privileges)"
  echo "    - All Linux capabilities dropped (cap_drop: ALL)"
  echo "    - no-new-privileges enabled"
  echo "    - Read-only root filesystem (OpenClaw container)"
  echo "    - Gateway bound to 127.0.0.1 only (not exposed externally)"
  echo "    - Token authentication required"
  echo "    - Resource limits enforced (memory + CPU)"
  echo "    - Minimal /28 network subnet"
  echo ""
  echo "  Commands:"
  printf "    Logs:       ${CYAN}cd $SCRIPT_DIR && $COMPOSE_CMD logs -f${NC}\n"
  printf "    Stop:       ${CYAN}$COMPOSE_CMD down${NC}\n"
  printf "    Restart:    ${CYAN}$COMPOSE_CMD restart${NC}\n"
  printf "    CLI:        ${CYAN}$COMPOSE_CMD --profile cli run --rm openclaw-cli doctor${NC}\n"
  printf "    Pull model: ${CYAN}$COMPOSE_CMD exec ollama ollama pull <model>${NC}\n"
  echo ""
  echo "  Alternative Phi models you can pull:"
  echo "    podman-compose exec ollama ollama pull phi4          # Full Phi-4"
  echo "    podman-compose exec ollama ollama pull phi3.5        # Phi-3.5"
  echo "    podman-compose exec ollama ollama pull phi4-mini:3.8b # Phi-4 Mini 3.8B"
  echo ""
  echo "============================================================================="
}

# --- Main ---
main() {
  echo ""
  echo "============================================"
  echo "  OpenClaw + Ollama — Secure Podman Setup"
  echo "============================================"
  echo ""

  detect_runtime
  check_rootless
  setup_env
  build_image
  setup_ollama
  start_services
  print_summary
}

main "$@"