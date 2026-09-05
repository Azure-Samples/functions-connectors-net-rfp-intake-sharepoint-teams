targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@metadata({
  azd: {
    type: 'location'
  }
})
@description('Location for all resources except the Connector Namespace.')
param location string

@description('Region for the Connector Namespace. Override via CONNECTOR_NAMESPACE_LOCATION if needed.')
param connectorNamespaceLocation string = 'westcentralus'

@description('Location for the Azure OpenAI account. Override via AZURE_OPENAI_LOCATION if needed.')
param openAiLocation string = 'eastus'

metadata name = 'RFP intake: SharePoint -> Azure OpenAI -> Teams (.NET)'
metadata description = 'Connector Namespace trigger sample that reads an RFP from SharePoint, extracts requirements with Azure OpenAI, and posts an Adaptive Card to Teams. System-key auth on the callback URL (no built-in auth).'

@description('Id of the user identity to be used for testing and debugging. Granted access to the connections + OpenAI so the same code can be debugged locally with `az login`.')
@metadata({
  azd: {
    type: 'principalId'
  }
})
param userPrincipalId string = deployer().objectId

@description('SharePoint site URL that contains the RFP library (e.g., https://contoso.sharepoint.com/sites/RFPs).')
param sharepointSiteUrl string

@description('SharePoint document library name to monitor for new RFPs (e.g., "Documents").')
param sharepointLibraryName string

@description('Optional folder path within the library to monitor (e.g., "/Shared Documents/Subfolder"). Leave blank for the whole library.')
param sharepointFolderPath string = ''

@description('Microsoft Teams team (group) ID to post the RFP summary card to.')
param teamsTeamId string

@description('Microsoft Teams channel ID to post the RFP summary card to.')
param teamsChannelId string

@description('Azure OpenAI chat model deployment name.')
param openAiDeploymentName string = 'gpt-5.4-mini'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

var functionAppName = '${abbrs.webSitesFunctions}${resourceToken}'
var functionAppPlanName = '${abbrs.webServerFarms}${resourceToken}'
var functionAppIdentityName = '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
var resourceGroupName = '${abbrs.resourcesResourceGroups}${environmentName}'
var storageAccountName = '${abbrs.storageStorageAccounts}${resourceToken}'
var logAnalyticsName = '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
var appInsightsName = '${abbrs.insightsComponents}${resourceToken}'
var connectorNamespaceName = '${abbrs.connectorNamespaces}${resourceToken}'
var sharepointConnectionName = '${abbrs.connectorNamespacesConnections}sp-${resourceToken}'
var teamsConnectionName = '${abbrs.connectorNamespacesConnections}teams-${resourceToken}'
var openAiName = '${abbrs.cognitiveServicesAccounts}${resourceToken}'

var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, environmentName)), 7)}'
var storageBlobDataOwner = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageQueueDataContributor = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributor = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

resource rg 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: '${uniqueString(deployment().name, location)}-loganalytics'
  scope: rg
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
    dataRetention: 30
  }
}

module funcUserAssignedIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.0' = {
  name: 'funcUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    name: functionAppIdentityName
  }
}

module monitoring 'br/public:avm/res/insights/component:0.7.1' = {
  name: '${uniqueString(deployment().name, location)}-appinsights'
  scope: rg
  params: {
    name: appInsightsName
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    disableLocalAuth: true
    roleAssignments: [
      {
        roleDefinitionIdOrName: monitoringMetricsPublisherRoleId
        principalId: funcUserAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: monitoringMetricsPublisherRoleId
        principalId: userPrincipalId
        principalType: 'User'
      }
    ]
  }
}

module storageAccount 'br/public:avm/res/storage/storage-account:0.32.0' = {
  scope: rg
  name: storageAccountName
  params: {
    name: storageAccountName
    location: location
    tags: tags
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    minimumTlsVersion: 'TLS1_2'
    blobServices: {
      containers: [{ name: deploymentStorageContainerName }]
    }
    roleAssignments: [
      {
        roleDefinitionIdOrName: storageBlobDataOwner
        principalId: funcUserAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: storageQueueDataContributor
        principalId: funcUserAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: storageTableDataContributor
        principalId: funcUserAssignedIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: storageBlobDataOwner
        principalId: userPrincipalId
        principalType: 'User'
      }
      {
        roleDefinitionIdOrName: storageQueueDataContributor
        principalId: userPrincipalId
        principalType: 'User'
      }
      {
        roleDefinitionIdOrName: storageTableDataContributor
        principalId: userPrincipalId
        principalType: 'User'
      }
    ]
  }
}

module functionAppPlan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  scope: rg
  name: functionAppPlanName
  params: {
    name: functionAppPlanName
    location: location
    tags: tags
    skuName: 'FC1'
    reserved: true
  }
}

// Connector Namespace + sharepointonline & teams connections.
module connectorNamespace './connectorNamespace.bicep' = {
  scope: rg
  name: connectorNamespaceName
  params: {
    name: connectorNamespaceName
    location: connectorNamespaceLocation
    tags: tags
    sharepointConnectionName: sharepointConnectionName
    teamsConnectionName: teamsConnectionName
    functionAppPrincipalId: funcUserAssignedIdentity.outputs.principalId
    userPrincipalId: userPrincipalId
  }
}

// Azure OpenAI account + chat deployment + role assignments.
module openAi './openai.bicep' = {
  scope: rg
  name: openAiName
  params: {
    name: openAiName
    location: openAiLocation
    tags: tags
    deploymentName: openAiDeploymentName
    functionAppPrincipalId: funcUserAssignedIdentity.outputs.principalId
    userPrincipalId: userPrincipalId
  }
}

var allAppSettings = {
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: funcUserAssignedIdentity.outputs.clientId
  AzureWebJobsStorage__accountName: storageAccount.outputs.name
  APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${funcUserAssignedIdentity.outputs.clientId};Authorization=AAD'
  APPLICATIONINSIGHTS_CONNECTION_STRING: monitoring.outputs.connectionString
  AZURE_CLIENT_ID: funcUserAssignedIdentity.outputs.clientId
  SHAREPOINTONLINE_CONNECTION_RUNTIME_URL: connectorNamespace.outputs.sharepointConnectionRuntimeUrl
  SHAREPOINT_SITE_URL: sharepointSiteUrl
  TEAMS_CONNECTION_RUNTIME_URL: connectorNamespace.outputs.teamsConnectionRuntimeUrl
  TEAMS_TEAM_ID: teamsTeamId
  TEAMS_CHANNEL_ID: teamsChannelId
  TEAMS_POST_AS: 'Flow bot'
  TEAMS_POST_IN: 'Channel'
  AZURE_OPENAI_ENDPOINT: openAi.outputs.endpoint
  AZURE_OPENAI_DEPLOYMENT: openAi.outputs.deploymentName
}

module functionApp 'br/public:avm/res/web/site:0.22.0' = {
  scope: rg
  name: functionAppName
  params: {
    name: functionAppName
    location: location
    tags: union(tags, { 'azd-service-name': 'function-app' })
    kind: 'functionapp,linux'
    serverFarmResourceId: functionAppPlan.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
      userAssignedResourceIds: [
        '${funcUserAssignedIdentity.outputs.resourceId}'
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.outputs.primaryBlobEndpoint}${deploymentStorageContainerName}'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: funcUserAssignedIdentity.outputs.resourceId
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 100
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '10.0'
      }
    }
    siteConfig: {
      alwaysOn: false
    }
    configs: [
      {
        name: 'appsettings'
        properties: allAppSettings
      }
    ]
  }
}

@description('The resource ID of the created Resource Group.')
output resourceGroupResourceId string = rg.id

@description('The name of the created Resource Group.')
output resourceGroupName string = rg.name

@description('The name of the created Function App.')
output functionAppName string = functionApp.outputs.name

@description('The default hostname of the created Function App.')
output functionAppDefaultHostname string = functionApp.outputs.defaultHostname

@description('The name of the created Connector Namespace.')
output connectorNamespaceName string = connectorNamespace.outputs.name

@description('The name of the created SharePoint connection on the Connector Namespace.')
output sharepointConnectionName string = connectorNamespace.outputs.sharepointConnectionName

@description('The name of the created Teams connection on the Connector Namespace.')
output teamsConnectionName string = connectorNamespace.outputs.teamsConnectionName

@description('SharePoint site URL that contains the RFP library.')
output sharepointSiteUrl string = sharepointSiteUrl

@description('SharePoint document library name being monitored.')
output sharepointLibraryName string = sharepointLibraryName

@description('SharePoint folder path being monitored (blank = whole library).')
output sharepointFolderPath string = sharepointFolderPath
