$ErrorActionPreference = 'Stop'

Write-Host "Configuring the deployed Function App trigger..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'configure-trigger.ps1') -Target Azure

Write-Host "Checking connector authorization..." -ForegroundColor Yellow
& (Join-Path $PSScriptRoot 'authorize-connections.ps1')

Write-Host ""
Write-Host "Done. RFP intake is configured end-to-end." -ForegroundColor Green
