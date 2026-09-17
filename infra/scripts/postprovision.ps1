$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path

& (Join-Path $scriptDirectory 'authorize-connections.ps1')
& (Join-Path $scriptDirectory 'createlocalsettings.ps1')
