<#
Deploy the Phase 6 disable approval Logic App for Lindhav Bank.

What it does
  Puts the steps from workflow.json into the Logic App lindhav-ai001-disable-approval.
  The flow is AI-001 asks, Nanna approves or denies by email, and only on Approve the
  Logic App's own managed identity turns the account off in Entra. It also makes the
  Outlook.com connection the approval email is sent from, and turns off the SAS key on
  the trigger, so the only way in is the Foundry project identity's Entra token
  (the OAuth policy foundry-project-only). The Logic App and its identity already exist.

Inputs
  workflow.json                 next to this script
  Azure CLI                     signed in to the Lindhav Bank tenant, subscription havlund-lab

Outputs
  The updated Logic App and an API connection named lindhav-outlook-approvals
  A short check in the terminal (SAS state, OAuth policy, steps, connection status)
  No secrets. The connection still has to be signed in once in the portal.

How to run
  pwsh -File tools/disable-approval/deploy.ps1
#>

$ErrorActionPreference = 'Stop'
$sub      = '7ad19269-7184-484c-ac87-eed78fe651e1'
$rg       = 'rg-lindhav-ai'
$region   = 'swedencentral'
$app      = 'lindhav-ai001-disable-approval'
$connName = 'lindhav-outlook-approvals'
$api      = '2019-05-01'

$wfId   = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Logic/workflows/$app"
$connId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Web/connections/$connName"
$apiId  = "/subscriptions/$sub/providers/Microsoft.Web/locations/$region/managedApis/outlook"

az account set --subscription $sub | Out-Null
$tmp = New-TemporaryFile

# 1. The Outlook.com connection, made only if it isn't there yet
$existing = az resource show --ids $connId 2>$null
if (-not $existing) {
    @{ location = $region; properties = @{ displayName = 'lindhav-approvals@outlook.com'; api = @{ id = $apiId } } } |
        ConvertTo-Json -Depth 5 | Set-Content $tmp -Encoding utf8
    az rest --method put --url "https://management.azure.com$($connId)?api-version=2016-06-01" --body "@$tmp" | Out-Null
    Write-Host "Made the connection $connName"
} else {
    Write-Host "Connection $connName already exists"
}

# 2. Read the Logic App, put in the steps, the connection and SAS off, write it back
$wf  = az rest --method get --url "https://management.azure.com$($wfId)?api-version=$api" | ConvertFrom-Json -Depth 50
$src = Get-Content (Join-Path $PSScriptRoot 'workflow.json') -Raw | ConvertFrom-Json -Depth 50

$wf.properties.definition = $src.definition
$wf.properties | Add-Member -Force -NotePropertyName parameters -NotePropertyValue @{
    '$connections' = @{ value = @{ outlook = @{ connectionId = $connId; connectionName = $connName; id = $apiId } } }
}
$triggers = $wf.properties.accessControl.triggers
$triggers | Add-Member -Force -NotePropertyName sasAuthenticationPolicy -NotePropertyValue @{ state = 'Disabled' }

$body = @{ location = $wf.location; identity = @{ type = 'SystemAssigned' }; properties = $wf.properties }
$body | ConvertTo-Json -Depth 50 | Set-Content $tmp -Encoding utf8
az rest --method put --url "https://management.azure.com$($wfId)?api-version=$api" --body "@$tmp" | Out-Null
Remove-Item $tmp

# 3. Read it back
$after = az rest --method get --url "https://management.azure.com$($wfId)?api-version=$api" | ConvertFrom-Json -Depth 50
$conn  = az rest --method get --url "https://management.azure.com$($connId)?api-version=2016-06-01" | ConvertFrom-Json -Depth 20
Write-Host ''
Write-Host "Managed identity     $($after.identity.principalId)"
Write-Host "SAS on the trigger   $($after.properties.accessControl.triggers.sasAuthenticationPolicy.state)"
Write-Host "OAuth policies       $(($after.properties.accessControl.triggers.openAuthenticationPolicies.policies.PSObject.Properties.Name) -join ', ')"
Write-Host "Steps                $(($after.properties.definition.actions.PSObject.Properties.Name) -join ', ')"
Write-Host "Connection status    $($conn.properties.overallStatus)"
Write-Host ''
Write-Host 'If the connection says Error or Unauthenticated, sign it in once in the portal (API connections, Edit API connection, Authorize).'
