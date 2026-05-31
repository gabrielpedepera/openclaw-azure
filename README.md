# OpenClaw on Azure

Infrastructure as Code (Bicep) to deploy [OpenClaw](https://openclaw.ai/) on a cost-effective Azure VM with GitHub Copilot as the LLM provider and Telegram as the chat client.

## 💰 Estimated Cost

| Resource | Monthly Cost |
|---|---|
| Standard_B2s VM (2 vCPU, 4 GB) | ~$15/mo |
| 30 GB OS disk (Standard_LRS) | ~$1.50/mo |
| 16 GB data disk (Standard_LRS) | ~$0.80/mo |
| Public IP (Standard, static) | ~$3.60/mo |
| **Subtotal (infra)** | **~$21/mo** |
| LLM: GitHub Copilot subscription | Included in your existing plan |
| Auto-shutdown at 19:00 UTC | Saves ~60% on compute |
| Auto-start at 07:00 UTC | Via GitHub Actions |

> With auto-shutdown/start, the VM runs 12h/day (~$7.50/mo compute).

---

## 🛠 Prerequisites

1. **Azure CLI** installed ([install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli))
2. **SSH key pair** (`.pem` or `id_ed25519`)
3. **GitHub Copilot subscription** (Individual, Business, or Enterprise)
4. **Telegram bot token** from [@BotFather](https://t.me/BotFather)

---

## 📦 Deployment

### 1. Authenticate

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 2. Deploy Infrastructure

```bash
az deployment sub create \
  --name "OpenClawDeployment" \
  --location northeurope \
  --template-file main.bicep \
  --parameters \
    sshPublicKey="$(cat ~/.ssh/openclaw-key.pub)" \
    allowedSshCidr="$(curl -s ifconfig.me)/32"
```

> `allowedSshCidr` locks SSH to your current IP. Omit it to allow all (not recommended).

### 3. Configure SSH Access

Add to `~/.ssh/config`:

```text
Host openclaw
    HostName openclaw-vm.northeurope.cloudapp.azure.com
    User gabrielpedepera
    IdentityFile ~/.ssh/openclaw-key
```

### 4. Post-Deploy Setup

SSH into the VM and run the configuration script:

```bash
ssh openclaw
chmod +x ~/openclaw/configure.sh
~/openclaw/configure.sh
```

This will:
- Pull the OpenClaw Docker image
- Run initial setup (config, workspace, sessions)
- Generate a gateway token and start the container

### 5. Fix Data Disk Permissions

The Azure data disk mounts with permissive defaults. Fix permissions so OpenClaw's auth store works correctly:

```bash
ssh openclaw
sudo chown -R 1000:1000 /mnt/openclaw-data/openclaw
sudo chmod -R 700 /mnt/openclaw-data/openclaw/agents
sudo docker compose -f ~/openclaw/docker-compose.yml restart
```

### 6. Authenticate GitHub Copilot as LLM

```bash
ssh openclaw
sudo docker exec -it openclaw openclaw models auth login-github-copilot
```

Follow the browser-based device login flow to link your GitHub Copilot subscription.

### 7. Add Telegram Channel

```bash
ssh openclaw
sudo docker exec openclaw openclaw channels add --channel telegram --token "YOUR_BOT_TOKEN"
sudo docker compose -f ~/openclaw/docker-compose.yml restart
```

Then open Telegram, message your bot, and **approve the pairing code** it sends you:

```bash
sudo docker exec openclaw openclaw pairing approve telegram YOUR_PAIRING_CODE
```

---

## 💬 Chatting with OpenClaw

### Via Telegram (recommended)
Message your bot on Telegram — OpenClaw responds directly.

### Via Terminal UI
```bash
ssh openclaw
sudo docker exec -it openclaw openclaw tui --local
```

---

## ▶️ Daily Operations

### Start the VM

```bash
az vm start -g rg-openclaw -n openclaw-vm
```

### Stop the VM (save costs)

```bash
az vm deallocate -g rg-openclaw -n openclaw-vm
```

### Check OpenClaw status

```bash
ssh openclaw "sudo docker ps"
```

### View OpenClaw logs

```bash
ssh openclaw "sudo docker logs openclaw --tail 50"
```

> The VM auto-stops at **19:00 UTC** daily. Start it again each morning.

---

## 🗑 Cleanup

Delete all resources and stop all charges:

```bash
az group delete --name rg-openclaw --yes --no-wait
```

> ⚠️ The data disk is set to **Detach** on VM delete, so your OpenClaw memory persists. Delete it manually if you want a full cleanup.

---

## 📂 File Structure

| File | Purpose |
|---|---|
| `main.bicep` | Subscription-level orchestrator (RG + VM module) |
| `openclaw-vm.bicep` | VM, networking, cloud-init, auto-shutdown |
| `configure.sh` | Post-deploy setup (Docker, OpenClaw init, gateway token) |

## 🔒 Security Notes

- SSH restricted to your IP via NSG (`allowedSshCidr`)
- LLM powered by GitHub Copilot (no API keys to manage)
- OpenClaw web UI bound to `127.0.0.1` only (no public exposure)
- Data disk persists separately from VM lifecycle (mounted by label, survives reboots)

## ⏰ Auto-Start / Auto-Shutdown

| Event | Time | Mechanism |
|---|---|---|
| **Start** | 07:00 UTC daily | GitHub Actions (`.github/workflows/auto-start.yml`) |
| **Shutdown** | 19:00 UTC daily | Azure DevTest Lab schedule |
| **Manual start** | Anytime | `az vm start -g rg-openclaw -n openclaw-vm` |

### GitHub Actions Setup (required for auto-start)

1. Create an Azure AD App Registration with federated credentials for GitHub Actions
2. Assign it **Virtual Machine Contributor** role on the `rg-openclaw` resource group
3. Add these repository secrets:
   - `AZURE_CLIENT_ID`
   - `AZURE_TENANT_ID`
   - `AZURE_SUBSCRIPTION_ID`

See [Azure Login with OIDC](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure) for setup details.
- Agent auth directory must have `700` permissions (not world-readable)
