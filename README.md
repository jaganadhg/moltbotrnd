# OpenClaw — Secure Podman Deployment with Ollama (Phi)

Run [OpenClaw](https://github.com/openclaw/openclaw) as a local AI assistant using **Podman** (rootless) with **Ollama** serving the **Phi** model. This setup prioritizes security with zero host-level privileges.

## Security Measures

| Layer | Hardening |
|---|---|
| **Host** | Rootless Podman — no root daemon, no root on host |
| **Capabilities** | `cap_drop: ALL` — every Linux capability dropped |
| **Privilege escalation** | `no-new-privileges:true` on all containers |
| **Filesystem** | Read-only root FS on OpenClaw; writable via tmpfs only |
| **Network** | Gateway bound to `127.0.0.1` only; internal pod network `/28` |
| **Authentication** | Gateway token required (`OPENCLAW_GATEWAY_TOKEN`) |
| **Resources** | Memory + CPU limits enforced per container |
| **Process** | `tini` as PID 1 for proper signal handling |
| **User** | Runs as `node` (uid 1000) inside container |
| **Browser** | Disabled — no remote browser control |

## Prerequisites

- **Podman** (rootless) — [Install guide](https://podman.io/docs/installation)
- **podman-compose** — `pip install podman-compose` or `dnf install podman-compose`
- ~8 GB RAM (4 GB for Ollama/Phi, 1 GB for OpenClaw, rest for OS)
- ~5 GB disk for the Phi model

## Quick Start

```bash
cd docker/

# One-command setup (builds, pulls model, starts everything)
chmod +x setup.sh
./setup.sh
```

The script will:
1. Verify rootless Podman
2. Generate a cryptographic gateway token (saved in `.env`)
3. Build the OpenClaw image
4. Pull the `phi4-mini` model into Ollama
5. Start all services

## Manual Start

```bash
cd docker/

# Create .env with your token
cp .env.example .env
# Edit .env — set OPENCLAW_GATEWAY_TOKEN (or run: openssl rand -hex 32)

# Build and start
podman-compose build
podman-compose up -d

# Pull the Phi model
podman-compose exec ollama ollama pull phi4-mini

# Check logs
podman-compose logs -f
```

## Access

- **Gateway**: http://127.0.0.1:18789 (loopback only)
- **WebChat**: http://127.0.0.1:18789 (served from gateway)

## Commands

```bash
# View logs
podman-compose logs -f

# Stop everything
podman-compose down

# Run CLI commands (uses the 'cli' profile)
podman-compose --profile cli run --rm openclaw-cli doctor
podman-compose --profile cli run --rm openclaw-cli config get agent.model

# Switch Phi model variant
podman-compose exec ollama ollama pull phi4        # Full Phi-4 (larger)
podman-compose exec ollama ollama pull phi3.5      # Phi-3.5

# List loaded models
podman-compose exec ollama ollama list

# Rebuild after updates
podman-compose build --no-cache
podman-compose up -d
```

## File Structure

```
docker/
  docker-compose.yml   # Podman compose — security-hardened
  Dockerfile           # Multi-stage build, non-root, minimal image
  setup.sh             # Automated setup script
  .env                 # Secrets (auto-generated, git-ignored)
  .env.example         # Template for .env
  config/
    openclaw.json      # OpenClaw configuration (Ollama + Phi)
```

## Verify Security

```bash
# Confirm rootless
podman info | grep -i rootless

# Confirm non-root inside container
podman-compose exec openclaw id
# Should show: uid=1000(node)

# Confirm capabilities dropped
podman-compose exec openclaw cat /proc/1/status | grep -i cap

# Confirm read-only filesystem
podman-compose exec openclaw touch /test 2>&1
# Should fail: Read-only file system
```

## Dev Containers (VS Code)

You can run the entire stack inside [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers) for a fully isolated, reproducible environment.

### Prerequisites

- VS Code with the **Dev Containers** extension (`ms-vscode-remote.remote-containers`)
- Docker or Podman running on the host

### Quick Start

```bash
# 1. Generate a token for the dev container
cd .devcontainer
cp .env.example .env
# Edit .env — set OPENCLAW_GATEWAY_TOKEN (e.g., openssl rand -hex 32)

# 2. Open in VS Code and reopen in container
#    Press Ctrl+Shift+P → "Dev Containers: Reopen in Container"
```

VS Code will:
1. Build the OpenClaw gateway image
2. Start Ollama + OpenClaw + a dev workspace container
3. Pull the `phi4-mini` model automatically
4. Forward port 18789 to your host

### Dev Container File Structure

```
.devcontainer/
  devcontainer.json                  # VS Code dev container config
  docker-compose.devcontainer.yml    # Compose with 3 services
  post-start.sh                      # Auto-pulls model, prints status
  .env.example                       # Token template
  .env                               # Your token (git-ignored)
```