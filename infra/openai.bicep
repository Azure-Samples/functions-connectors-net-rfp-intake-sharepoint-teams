@description('Name of the Azure OpenAI (Cognitive Services) account.')
param name string
param location string
param tags object = {}

@description('Name of the chat model deployment (e.g. gpt-5.4-mini).')
param deploymentName string = 'gpt-5.4-mini'

@description('Model name to deploy.')
param modelName string = 'gpt-5.4-mini'

@description('Model version to deploy.')
param modelVersion string = '2026-03-17'

@description('Capacity (TPM in thousands) for the deployment.')
param capacity int = 20

@description('Principal ID of the function app MI to grant Cognitive Services OpenAI User.')
param functionAppPrincipalId string

@description('Optional. AAD object ID of the deployer for local debugging.')
param userPrincipalId string = ''

// Cognitive Services OpenAI User
var openAiUserRoleId = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource deployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: account
  name: deploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource functionAppOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, functionAppPrincipalId, openAiUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource userOpenAiRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  scope: account
  name: guid(account.id, userPrincipalId, openAiUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

@description('The endpoint of the Azure OpenAI account.')
output endpoint string = account.properties.endpoint

@description('The chat model deployment name.')
output deploymentName string = deployment.name
