#!/bin/bash
# =============================================================================
# Dev Container post-start — pull Phi model and show status
# =============================================================================
set -e

echo ""
echo "============================================"
echo "  OpenClaw Dev Container — Post-Start"
echo "============================================"

# Generate token if not set
if [ "$OPENCLAW_GATEWAY_TOKEN" = "changeme" ] || [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo "[INFO]  No token set. Generate one and add to .devcontainer/.env:"
    echo "        OPENCLAW_GATEWAY_TOKEN=\$(openssl rand -hex 32)"
fi

# Wait for Ollama to be ready
echo "[INFO]  Waiting for Ollama..."
for i in $(seq 1 30); do
    if curl -sf http://ollama:11434/api/tags >/dev/null 2>&1; then
        echo "[OK]    Ollama is ready"
        break
    fi
    sleep 2
done

# Pull Phi model if not present
MODEL_CHECK=$(curl -sf http://ollama:11434/api/tags 2>/dev/null || echo '{}')
if echo "$MODEL_CHECK" | grep -q "phi4-mini"; then
    echo "[OK]    phi4-mini model already available"
else
    echo "[INFO]  Pulling phi4-mini model (first time only, ~2.5 GB)..."
    curl -sf http://ollama:11434/api/pull -d '{"name": "phi4-mini"}' | while read -r line; do
        STATUS=$(echo "$line" | grep -oP '"status"\s*:\s*"[^"]*"' | head -1)
        [ -n "$STATUS" ] && printf "\r        %s" "$STATUS"
    done
    echo ""
    echo "[OK]    phi4-mini model downloaded"
fi

# Print status
echo ""
echo "============================================"
echo "  OpenClaw is running!"
echo "============================================"
echo ""
echo "  Gateway:  http://localhost:18789"
echo "  Token:    \$OPENCLAW_GATEWAY_TOKEN"
echo "  Model:    phi4-mini (via Ollama)"
echo ""
echo "  Useful commands:"
echo "    curl http://ollama:11434/api/tags    # List models"
echo "    curl http://openclaw:18789/          # Check gateway"
echo ""
echo "============================================"
