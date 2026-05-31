param location string
param vmName string
param adminUsername string

@secure()
param sshPublicKey string

param allowedSshCidr string

// ── Network Security Group ──────────────────────────────────────────
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSshCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// ── Virtual Network ─────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.1.0.0/16'] }
    subnets: [{ name: 'default', properties: { addressPrefix: '10.1.1.0/24' } }]
  }
}

// ── Public IP ───────────────────────────────────────────────────────
resource pip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${vmName}-ip'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'openclaw-vm'
    }
  }
}

// ── Network Interface ───────────────────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    networkSecurityGroup: { id: nsg.id }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          publicIPAddress: { id: pip.id }
        }
      }
    ]
  }
}

// ── Virtual Machine ─────────────────────────────────────────────────
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 30
        managedDisk: { storageAccountType: 'Standard_LRS' }
        deleteOption: 'Delete'
      }
      dataDisks: [
        {
          lun: 0
          name: '${vmName}-data'
          createOption: 'Empty'
          diskSizeGB: 16
          managedDisk: { storageAccountType: 'Standard_LRS' }
          deleteOption: 'Detach'
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
      customData: base64(cloudInit)
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }]
    }
  }
}

// ── Auto-Shutdown (19:00 UTC) ───────────────────────────────────────
// Auto-start is handled by GitHub Actions (.github/workflows/auto-start.yml)
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: { time: '1900' }
    timeZoneId: 'UTC'
    targetResourceId: vm.id
    notificationSettings: { status: 'Disabled' }
  }
}

// ── Cloud-Init ──────────────────────────────────────────────────────
var cloudInit = '''
#cloud-config
package_update: true
packages:
  - git
  - curl
  - docker.io
  - docker-compose-v2
  - jq
  - unzip

disk_setup:
  /dev/disk/azure/scsi1/lun0:
    table_type: gpt
    layout: true
    overwrite: false

fs_setup:
  - label: openclawdata
    filesystem: ext4
    device: /dev/disk/azure/scsi1/lun0
    partition: auto
    overwrite: false

mounts:
  - ["LABEL=openclawdata", "/data/openclaw-data", "ext4", "defaults,nofail", "0", "2"]

runcmd:
  # Enable Docker
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ${adminUsername}

  # Create OpenClaw data directories on persistent disk
  - mkdir -p /data/openclaw-data/openclaw
  - chown -R 1000:1000 /data/openclaw-data
  - chmod 700 /data/openclaw-data/openclaw

  # Prevent cloud-init from reformatting/remounting data disk on subsequent boots
  - |
    cat > /etc/cloud/cloud.cfg.d/99-disable-disk-setup.cfg <<'CLOUDINIT'
    disk_setup: {}
    fs_setup: []
    mounts: []
    CLOUDINIT

  # Ensure fstab uses LABEL (cloud-init may resolve to device path)
  - |
    sed -i '/openclaw-data/d' /etc/fstab
    echo 'LABEL=openclawdata /data/openclaw-data ext4 defaults,nofail 0 2' >> /etc/fstab

  # Create systemd service to start OpenClaw after disk mount with correct permissions
  - |
    cat > /etc/systemd/system/openclaw.service <<'SYSTEMD'
    [Unit]
    Description=OpenClaw AI Assistant
    After=docker.service data-openclaw\x2ddata.mount
    Requires=docker.service data-openclaw\x2ddata.mount

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    WorkingDirectory=/home/${adminUsername}/openclaw
    ExecStartPre=/bin/bash -c 'chown -R 1000:1000 /data/openclaw-data/openclaw && chmod -R 700 /data/openclaw-data/openclaw/agents/main/agent 2>/dev/null || true'
    ExecStart=/usr/bin/docker compose up -d
    ExecStop=/usr/bin/docker compose down

    [Install]
    WantedBy=multi-user.target
    SYSTEMD
  - systemctl daemon-reload
  - systemctl enable openclaw.service

  # Write LLM config (populated post-deploy via SSH)
  - mkdir -p /home/${adminUsername}/openclaw
  - |
    cat > /home/${adminUsername}/openclaw/.env <<'ENVEOF'
    # OpenClaw Environment Configuration
    # LLM: GitHub Copilot (configured post-deploy via `openclaw models auth login-github-copilot`)
    OPENCLAW_DATA_DIR=/data/openclaw-data/openclaw
    ENVEOF
  - chown -R ${adminUsername}:${adminUsername} /home/${adminUsername}/openclaw

  # Install GitHub CLI (for Copilot auth)
  - |
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update && apt-get install -y gh

'''
