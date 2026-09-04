param name string
param location string
param tags object = {}
param sharepointConnectionName string
param teamsConnectionName string
@description('Object (principal) ID of the function app user-assigned MI. Granted access to both connections so it can poll trigger callbacks and call connector actions at runtime.')
param functionAppPrincipalId string
@description('Optional. AAD object ID of a user (typically the deployer) to also grant access to the connections, so the same code can be debugged locally with `az login` credentials.')
param userPrincipalId string = ''
param tenantId string = tenant().tenantId

resource connectorNamespace 'Microsoft.Web/connectorGateways@2026-05-01-preview' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

// ---------------------------------------------------------------------------
// SharePoint Online connection (RFP trigger + Get file content action)
// ---------------------------------------------------------------------------
resource sharepointConnection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: connectorNamespace
  name: sharepointConnectionName
  properties: {
    connectorName: 'sharepointonline'
  }
}

resource sharepointFunctionAppAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: sharepointConnection
  name: 'functionapp-msi'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: functionAppPrincipalId
        tenantId: tenantId
      }
    }
  }
}

resource sharepointNamespaceAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: sharepointConnection
  name: 'connector-namespace-msi'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: connectorNamespace.identity.principalId
        tenantId: tenantId
      }
    }
  }
}

resource sharepointUserAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = if (!empty(userPrincipalId)) {
  parent: sharepointConnection
  name: 'dev-user'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: userPrincipalId
        tenantId: tenantId
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Teams connection (Post card in a chat or channel action)
// ---------------------------------------------------------------------------
resource teamsConnection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: connectorNamespace
  name: teamsConnectionName
  properties: {
    connectorName: 'teams'
  }
}

resource teamsFunctionAppAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: teamsConnection
  name: 'functionapp-msi'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: functionAppPrincipalId
        tenantId: tenantId
      }
    }
  }
}

resource teamsNamespaceAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: teamsConnection
  name: 'connector-namespace-msi'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: connectorNamespace.identity.principalId
        tenantId: tenantId
      }
    }
  }
}

resource teamsUserAccessPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = if (!empty(userPrincipalId)) {
  parent: teamsConnection
  name: 'dev-user'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: userPrincipalId
        tenantId: tenantId
      }
    }
  }
}

@description('The resource ID of the Connector Namespace.')
output resourceId string = connectorNamespace.id

@description('The name of the Connector Namespace.')
output name string = connectorNamespace.name

@description('The name of the SharePoint connection on the namespace.')
output sharepointConnectionName string = sharepointConnection.name

@description('Runtime URL for the SharePoint connection.')
output sharepointConnectionRuntimeUrl string = sharepointConnection.properties.connectionRuntimeUrl

@description('The name of the Teams connection on the namespace.')
output teamsConnectionName string = teamsConnection.name

@description('Runtime URL for the Teams connection.')
output teamsConnectionRuntimeUrl string = teamsConnection.properties.connectionRuntimeUrl
