#!/usr/bin/env bash
# configure.sh — Post-deploy configuration for OpenClaw
# Run this on the VM after deployment to set up services.
set -euo pipefail

OPENCLAW_DIR="$HOME/openclaw"
COMPOSE_FILE="$OPENCLAW_DIR/docker-compose.yml"

echo "═══════════════════════════════════════════════"
echo "  OpenClaw Post-Deploy Configuration"
echo "═══════════════════════════════════════════════"

# ── 1. Docker Compose file ──────────────────────────────────────────
cat > "$COMPOSE_FILE" <<'COMPOSE'
services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - /mnt/openclaw-data/openclaw:/home/node/.openclaw
    mem_limit: 2g
COMPOSE
echo "✓ Docker Compose file created"

# ── 2. Run OpenClaw setup ────────────────────────────────────────────
echo ""
echo "Running OpenClaw setup..."
cd "$OPENCLAW_DIR"
sudo docker compose pull
sudo docker run --rm \
  -v /mnt/openclaw-data/openclaw:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest \
  openclaw setup
echo "✓ OpenClaw configured"

# ── 3. Generate gateway token and start ──────────────────────────────
GATEWAY_TOKEN=$(openssl rand -hex 32)
cat > "$COMPOSE_FILE" <<EOF
services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:latest
    container_name: openclaw
    restart: unless-stopped
    ports:
      - "127.0.0.1:3000:3000"
    volumes:
      - /mnt/openclaw-data/openclaw:/home/node/.openclaw
    environment:
      - OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}
    mem_limit: 2g
EOF

sudo docker compose up -d
echo "✓ OpenClaw is running"

# ── 4. Fix data disk permissions ─────────────────────────────────────
echo ""
echo "Fixing data disk permissions..."
sudo chown -R 1000:1000 /mnt/openclaw-data/openclaw
sudo chmod -R 700 /mnt/openclaw-data/openclaw/agents 2>/dev/null || true
sudo docker compose restart
echo "✓ Permissions fixed"

# ── 4. Next steps ───────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "  Next: Authenticate GitHub Copilot as LLM"
echo "═══════════════════════════════════════════════"
echo ""
echo "  Run the following and follow the browser flow:"
echo ""
echo "    sudo docker exec -it openclaw openclaw models auth login-github-copilot"
echo ""
echo "  Then set your preferred model:"
echo ""
echo "    sudo docker exec -it openclaw openclaw models set github-copilot/claude-sonnet-4.5"
echo ""
echo "  To chat with OpenClaw:"
echo ""
echo "    sudo docker exec -it openclaw openclaw tui --local"
echo ""
echo "  To add Telegram as a chat channel:"
echo ""
echo "    sudo docker exec openclaw openclaw channels add --channel telegram --token YOUR_BOT_TOKEN"
echo "    sudo docker compose -f ~/openclaw/docker-compose.yml restart"
echo ""
echo "  Then message your bot on Telegram and approve the pairing code:"
echo ""
echo "    sudo docker exec openclaw openclaw pairing approve telegram YOUR_CODE"
echo ""
