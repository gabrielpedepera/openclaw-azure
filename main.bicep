targetScope = 'subscription'

param rgName string = 'rg-openclaw'
param location string = 'northeurope'

@secure()
param sshPublicKey string

@secure()
@description('API key for the LLM provider (e.g., Anthropic, OpenAI)')
param llmApiKey string

@description('LLM provider to use (anthropic, openai, etc.)')
param llmProvider string = 'anthropic'

@description('Your IP address for SSH access (CIDR notation, e.g., 203.0.113.10/32)')
param allowedSshCidr string = '*'

// 1. Create the Resource Group
resource openclawRG 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: rgName
  location: location
}

// 2. Deploy the OpenClaw VM into that Resource Group
module openclawVm './openclaw-vm.bicep' = {
  name: 'openclaw-vm-deployment'
  scope: openclawRG
  params: {
    location: location
    sshPublicKey: sshPublicKey
    vmName: 'openclaw-vm'
    adminUsername: 'gabrielpedepera'
    llmApiKey: llmApiKey
    llmProvider: llmProvider
    allowedSshCidr: allowedSshCidr
  }
}
