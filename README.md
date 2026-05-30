# OpenClaw on Azure

Infrastructure as Code (Bicep) to deploy [OpenClaw](https://openclaw.ai/) on a cost-effective Azure VM with Signal as the secure chat client.

## 💰 Estimated Cost

| Resource | Monthly Cost |
|---|---|
| Standard_B2s VM (2 vCPU, 4 GB) | ~$15/mo |
| 30 GB OS disk (Standard_LRS) | ~$1.50/mo |
| 16 GB data disk (Standard_LRS) | ~$0.80/mo |
| Public IP (Standard, static) | ~$3.60/mo |
| **Subtotal (infra)** | **~$21/mo** |
| LLM API usage | $5–60/mo (varies) |
| Auto-shutdown at 19:00 UTC | Saves ~60% on compute |

> With auto-shutdown enabled, effective compute cost drops to ~$6–8/mo.

---

## 🛠 Prerequisites

1. **Azure CLI** installed ([install guide](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli))
2. **SSH key pair** (`.pem` or `id_rsa`)
3. **LLM API key** (Anthropic or OpenAI)
4. **Phone number** for Signal registration (dedicated number recommended)

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
    llmApiKey="your-api-key-here" \
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
- Prompt for your LLM API key and provider
- Create the Docker Compose configuration
- Pull and start the OpenClaw container

---

## 📱 Signal Registration

After OpenClaw is running, register your Signal number on the VM:

```bash
ssh openclaw

# 1. Register (you'll receive an SMS code)
signal-cli -a +YOUR_PHONE_NUMBER register

# 2. Verify with the received code
signal-cli -a +YOUR_PHONE_NUMBER verify 123-456

# 3. Verify it works
signal-cli -a +YOUR_PHONE_NUMBER send -m "Hello from OpenClaw!" +YOUR_PHONE_NUMBER
```

Then configure OpenClaw to use Signal as its chat transport by editing the OpenClaw config:

```bash
# Edit the OpenClaw configuration to add Signal
nano /mnt/openclaw-data/openclaw/config.yaml
```

Add the Signal section:

```yaml
channels:
  signal:
    enabled: true
    phone_number: "+YOUR_PHONE_NUMBER"
    signal_cli_path: "/usr/local/bin/signal-cli"
    data_dir: "/signal-cli-data"
```

Restart OpenClaw:

```bash
cd ~/openclaw && docker compose restart
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
ssh openclaw "docker ps"
```

### View OpenClaw logs

```bash
ssh openclaw "docker logs openclaw --tail 50"
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
| `configure.sh` | Post-deploy interactive setup (LLM key, Docker, Signal) |

## 🔒 Security Notes

- SSH restricted to your IP via NSG (`allowedSshCidr`)
- Signal provides end-to-end encryption for all messages
- LLM API key is stored only on the VM, never in Bicep state
- OpenClaw web UI bound to `127.0.0.1` only (no public exposure)
- Data disk persists separately from VM lifecycle
