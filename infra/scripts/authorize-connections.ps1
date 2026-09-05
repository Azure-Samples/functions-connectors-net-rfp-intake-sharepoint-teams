param(
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'

if (-not (az extension show --name connector-namespace --query name -o tsv 2>$null)) {
    throw "The 'connector-namespace' Azure CLI extension is required."
}

$outputs = azd env get-values --output json | ConvertFrom-Json
$resourceGroupName = $outputs.resourceGroupName
$connectorNamespaceName = $outputs.connectorNamespaceName
$sharepointConnectionName = $outputs.sharepointConnectionName
$teamsConnectionName = $outputs.teamsConnectionName

if (-not $resourceGroupName -or -not $connectorNamespaceName -or
    -not $sharepointConnectionName -or -not $teamsConnectionName) {
    throw "Required azd outputs are missing. Run 'azd provision' first."
}

function Invoke-AuthorizeConnection {
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionName,
        [Parameter(Mandatory)]
        [string]$FriendlyHint
    )

    Write-Host ""
    Write-Host "Authorizing connection '$ConnectionName'..." -ForegroundColor Yellow

    $currentStatus = az connector-namespace connection show `
        -g $resourceGroupName --namespace $connectorNamespaceName `
        -n $ConnectionName --query "properties.overallStatus" -o tsv 2>$null

    if ($currentStatus -eq 'Connected') {
        Write-Host "Connection '$ConnectionName' is already authorized." -ForegroundColor Green
        return
    }

    $consentLink = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $consentLink = az connector-namespace connection list-consent-links `
            -g $resourceGroupName --namespace $connectorNamespaceName `
            --connection-name $ConnectionName `
            --parameters "[{parameterName:token,redirectUrl:'https://portal.azure.com'}]" `
            --query "value[0].link" -o tsv 2>$null

        if (-not $consentLink) {
            $consentLink = az connector-namespace connection list-consent-links `
                -g $resourceGroupName --namespace $connectorNamespaceName `
                --connection-name $ConnectionName `
                --parameters "[{parameterName:token,redirectUrl:'https://portal.azure.com'}]" `
                --query "link" -o tsv 2>$null
        }

        if ($consentLink) {
            break
        }

        if ($attempt -lt 5) {
            Write-Host "Consent-link attempt $attempt failed. Retrying in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
    }

    if (-not $consentLink) {
        throw "Failed to create a consent link for '$ConnectionName'."
    }

    Write-Host "Consent URL: $consentLink" -ForegroundColor Cyan
    Write-Host $FriendlyHint -ForegroundColor Cyan

    if (-not $NonInteractive) {
        try {
            Start-Process $consentLink | Out-Null
        }
        catch {
            Write-Host "Unable to open a browser automatically. Paste the consent URL into your browser." -ForegroundColor Yellow
        }
    }

    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 3
        $currentStatus = az connector-namespace connection show `
            -g $resourceGroupName --namespace $connectorNamespaceName `
            -n $ConnectionName --query "properties.overallStatus" -o tsv 2>$null
    } while ($currentStatus -ne 'Connected' -and (Get-Date) -lt $deadline)

    if ($currentStatus -ne 'Connected') {
        throw "Timed out waiting for '$ConnectionName' to reach Connected status."
    }

    Write-Host "Connection '$ConnectionName' is authorized." -ForegroundColor Green
}

Invoke-AuthorizeConnection `
    -ConnectionName $sharepointConnectionName `
    -FriendlyHint "Sign in with an account that can access the SharePoint site."
Invoke-AuthorizeConnection `
    -ConnectionName $teamsConnectionName `
    -FriendlyHint "Sign in with an account that can post to the target Teams channel."
