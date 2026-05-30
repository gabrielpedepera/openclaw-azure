# OpenClaw on Azure

Infrastructure as Code (Bicep) to deploy [OpenClaw](https://openclaw.ai/) on a cost-effective Azure VM with GitHub Copilot as the LLM provider.

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

> With auto-shutdown enabled, effective compute cost drops to ~$6–8/mo.

---

## 🛠 Prerequisites

1. **Azure CLI** installed ([install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli))
2. **SSH key pair** (`.pem` or `id_rsa`)
3. **GitHub Copilot subscription** (Individual, Business, or Enterprise)

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
    sshPublicKey="$(ssh-keygen -y -f ~/.ssh/your-key-pair.pem)" \
    allowedSshCidr="$(curl -s ifconfig.me)/32"
```

> `allowedSshCidr` locks SSH to your current IP. Omit it to allow all (not recommended).

### 3. Configure SSH Access

Add to `~/.ssh/config`:

```text
Host openclaw
    HostName openclaw-vm.northeurope.cloudapp.azure.com
    User gabrielpedepera
    IdentityFile ~/.ssh/your-key-pair.pem
```

### 4. Post-Deploy Setup

SSH into the VM and run the configuration script:

```bash
ssh openclaw
chmod +x ~/openclaw/configure.sh
~/openclaw/configure.sh
```

This will:
- Create the Docker Compose configuration
- Pull and start the OpenClaw container
- Guide you through GitHub Copilot authentication

### 5. Chat with OpenClaw

Use the built-in terminal UI:

```bash
ssh openclaw
sudo docker exec -it openclaw openclaw tui --local
```

Or add a chat channel (Telegram, Discord, etc.):

```bash
sudo docker exec -it openclaw openclaw channels add --channel telegram --bot-token YOUR_BOT_TOKEN
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
| `configure.sh` | Post-deploy interactive setup (Docker, OpenClaw) |

## 🔒 Security Notes

- SSH restricted to your IP via NSG (`allowedSshCidr`)
- LLM powered by GitHub Copilot (no API keys to manage)
- OpenClaw web UI bound to `127.0.0.1` only (no public exposure)
- Data disk persists separately from VM lifecycle
