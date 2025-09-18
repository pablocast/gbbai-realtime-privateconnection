// ------------------
//    PARAMETERS
// ------------------

param aiServicesConfig array = []
param modelsConfig array = []
param apimSku string
param apimSubscriptionsConfig array = []
param inferenceAPIPath string = 'inference' // Path to the inference API in the APIM service
param inferenceAPIType string = 'websocket'
param foundryProjectName string = 'demo-realtime'
param principalId string

// ------------------
//    VARIABLES
// ------------------

var resourceSuffix = uniqueString(subscription().id, resourceGroup().id)

// ------------------
//    RESOURCES
// ------------------

// 1. Log Analytics Workspace
module lawModule './modules/workspaces.bicep' = {
  name: 'lawModule'
}

// 2. Application Insights
module appInsightsModule './modules/appinsights.bicep' = {
  name: 'appInsightsModule'
  params: {
    lawId: lawModule.outputs.id
    customMetricsOptedInType: 'WithDimensions'
  }
}

// 3. API Management
module apimModule './modules/apim.bicep' = {
  name: 'apimModule'
  params: {
    apimSku: apimSku
    apimSubscriptionsConfig: apimSubscriptionsConfig
    lawId: lawModule.outputs.id
    appInsightsId: appInsightsModule.outputs.id
    appInsightsInstrumentationKey: appInsightsModule.outputs.instrumentationKey
  }
}

// 4. AI Foundry
module foundryModule './modules/foundry.bicep' = {
    name: 'foundryModule'
    params: {
      aiServicesConfig: aiServicesConfig
      modelsConfig: modelsConfig
      apimPrincipalId: apimModule.outputs.principalId
      foundryProjectName: foundryProjectName
      principalId: principalId
    }
  }

resource apimService 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: 'apim-${resourceSuffix}'
}

// 5. APIM OpenAI-RT Websocket API
// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis
resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  name: 'realtime-audio'
  parent: apimService
  properties: {
    apiType: 'websocket'
    description: 'Inference API for Azure OpenAI Realtime'
    displayName: 'InferenceAPI'
    path: '${inferenceAPIPath}/openai/realtime'
    serviceUrl: '${replace(foundryModule.outputs.extendedAIServicesConfig[0].endpoint, 'https:', 'wss:')}openai/realtime'
    type: inferenceAPIType
    protocols: [
      'wss'
    ]
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    subscriptionRequired: true
  }
}

resource rtOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' existing = {
  name: 'onHandshake'
  parent: api
}

// https://learn.microsoft.com/azure/templates/microsoft.apimanagement/service/apis/policies
resource rtPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  name: 'policy'
  parent: rtOperation
  properties: {
    format: 'rawxml'
    value: loadTextContent('policy.xml')
  }
}

resource apiDiagnostics 'Microsoft.ApiManagement/service/apis/diagnostics@2024-06-01-preview' = {
  parent: api
  name: 'azuremonitor'
  properties: {
    alwaysLog: 'allErrors'
    verbosity: 'verbose'
    logClientIp: true
    loggerId: apimModule.outputs.loggerId
    sampling: {
      samplingType: 'fixed'
      percentage: json('100')
    }
    frontend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    largeLanguageModel: {
      logs: 'enabled'
      requests: {
        messages: 'all'
        maxSizeInBytes: 262144
      }
      responses: {
        messages: 'all'
        maxSizeInBytes: 262144
      }
    }
  }
} 

// ------------------
//    OUTPUTS
// ------------------

output logAnalyticsWorkspaceId string = lawModule.outputs.customerId
output apimServiceId string = apimModule.outputs.id
output apimResourceGatewayURL string = apimModule.outputs.gatewayUrl
output apiKey string = apimModule.outputs.apimSubscriptions[0].key
output apimSubscriptions array = apimModule.outputs.apimSubscriptions
