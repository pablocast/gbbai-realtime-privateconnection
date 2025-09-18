using './main.bicep'

param aiServicesConfig = [
  {
    name: 'foundry1'
    location: 'eastus2'
  }
]

param modelsConfig = [
  {
    name: 'gpt-realtime'
    publisher: 'OpenAI'
    version: '2025-08-28'
    sku: 'GlobalStandard'
    capacity: 10
  }
]

param apimSku = 'Basicv2'

param apimSubscriptionsConfig = [
  {
    name: 'subscription1'
    displayName: 'Subscription 1'
  }
]

param principalId = readEnvironmentVariable('AZURE_PRINCIPAL_ID', 'principalId')
param azureOpenAiApiVersion = '2024-10-01-preview'
