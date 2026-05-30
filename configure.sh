#!/usr/bin/env bash
# configure.sh — Post-deploy configuration for OpenClaw + Signal
# Run this on the VM after deployment to set up secrets and start services.
set -euo pipefail

OPENCLAW_DIR="$HOME/openclaw"
ENV_FILE="$OPENCLAW_DIR/.env"
COMPOSE_FILE="$OPENCLAW_DIR/docker-compose.yml"

echo "═══════════════════════════════════════════════"
echo "  OpenClaw Post-Deploy Configuration"
echo "═══════════════════════════════════════════════"

# ── 1. LLM API Key ──────────────────────────────────────────────────
if grep -q '^LLM_API_KEY=' "$ENV_FILE" 2>/dev/null; then
  echo "✓ LLM API key already configured"
else
  echo ""
  read -rp "LLM Provider (anthropic/openai) [anthropic]: " LLM_PROVIDER
  LLM_PROVIDER="${LLM_PROVIDER:-anthropic}"

  read -rsp "LLM API Key: " LLM_API_KEY
  echo ""

  cat >> "$ENV_FILE" <<EOF
LLM_PROVIDER=${LLM_PROVIDER}
LLM_API_KEY=${LLM_API_KEY}
EOF
  echo "✓ LLM configuration saved"
fi

# ── 2. Docker Compose file ──────────────────────────────────────────
cat > "$COMPOSE_FILE" <<'COMPOSE'
services:
  openclaw:
    image: ghcr.io/steipete/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    env_file: .env
    volumes:
      - ${OPENCLAW_DATA_DIR:-/mnt/openclaw-data/openclaw}:/data
      - ${SIGNAL_CLI_DATA_DIR:-/mnt/openclaw-data/signal-cli}:/signal-cli-data
    ports:
      - "127.0.0.1:3000:3000"
COMPOSE
echo "✓ Docker Compose file created"

# ── 3. Start OpenClaw ────────────────────────────────────────────────
echo ""
echo "Starting OpenClaw..."
cd "$OPENCLAW_DIR"
docker compose pull
docker compose up -d
echo "✓ OpenClaw is running"

echo ""
echo "═══════════════════════════════════════════════"
echo "  Next: Register your Signal number"
echo "═══════════════════════════════════════════════"
echo ""
echo "  1. Register your phone number:"
echo "     signal-cli -a +YOUR_PHONE_NUMBER register"
echo ""
echo "  2. Verify with the code you receive:"
echo "     signal-cli -a +YOUR_PHONE_NUMBER verify CODE"
echo ""
echo "  3. Configure OpenClaw to use Signal"
echo "     (see README.md for details)"
echo ""
