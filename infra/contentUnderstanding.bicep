@description('Name of the Microsoft Foundry resource used by Content Understanding.')
param name string
param location string
param tags object = {}

@description('Principal ID of the function app MI to grant Cognitive Services User.')
param functionAppPrincipalId string

@description('Optional. AAD object ID of the deployer for local debugging.')
param userPrincipalId string = ''

// Cognitive Services User
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

resource account 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: true
  }
}

resource functionAppContentUnderstandingRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, functionAppPrincipalId, cognitiveServicesUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource userContentUnderstandingRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(userPrincipalId)) {
  scope: account
  name: guid(account.id, userPrincipalId, cognitiveServicesUserRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: userPrincipalId
    principalType: 'User'
  }
}

@description('The endpoint of the Microsoft Foundry resource.')
output endpoint string = account.properties.endpoint
