#!/usr/bin/env bash
# configure.sh — Post-deploy configuration for OpenClaw + Signal
# Run this on the VM after deployment to set up services.
set -euo pipefail

OPENCLAW_DIR="$HOME/openclaw"
ENV_FILE="$OPENCLAW_DIR/.env"
COMPOSE_FILE="$OPENCLAW_DIR/docker-compose.yml"

echo "═══════════════════════════════════════════════"
echo "  OpenClaw Post-Deploy Configuration"
echo "═══════════════════════════════════════════════"

# ── 1. Docker Compose file ──────────────────────────────────────────
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

# ── 2. Start OpenClaw ────────────────────────────────────────────────
echo ""
echo "Pulling and starting OpenClaw..."
cd "$OPENCLAW_DIR"
docker compose pull
docker compose up -d
echo "✓ OpenClaw is running"

# ── 3. GitHub Copilot LLM Auth ──────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "  Step 1: Authenticate GitHub Copilot as LLM"
echo "═══════════════════════════════════════════════"
echo ""
echo "  Run the following command and follow the browser flow:"
echo ""
echo "    openclaw models auth login-github-copilot"
echo ""
echo "  Then set your preferred model:"
echo ""
echo "    openclaw models set github-copilot/claude-sonnet-4.5"
echo ""

# ── 4. Signal Setup ─────────────────────────────────────────────────
echo "═══════════════════════════════════════════════"
echo "  Step 2: Register your Signal number"
echo "═══════════════════════════════════════════════"
echo ""
echo "  1. Register your phone number:"
echo "     signal-cli -a +YOUR_PHONE_NUMBER register"
echo ""
echo "  2. Verify with the code you receive:"
echo "     signal-cli -a +YOUR_PHONE_NUMBER verify CODE"
echo ""
echo "  3. Test it works:"
echo "     signal-cli -a +YOUR_PHONE_NUMBER send -m 'Hello from OpenClaw!' +YOUR_PHONE_NUMBER"
echo ""
echo "  4. Configure OpenClaw to use Signal — edit /mnt/openclaw-data/openclaw/config.yaml:"
echo ""
echo '     channels:'
echo '       signal:'
echo '         enabled: true'
echo '         phone_number: "+YOUR_PHONE_NUMBER"'
echo '         signal_cli_path: "/usr/local/bin/signal-cli"'
echo '         data_dir: "/signal-cli-data"'
echo ""
echo "  5. Restart OpenClaw:"
echo "     cd ~/openclaw && docker compose restart"
echo ""
