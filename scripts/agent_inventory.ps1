<#
Agent inventory for Lindhav Bank.

What it does
  Lists every Entra agent identity in the Lindhav Bank tenant and adds what each
  one can reach. That's its sponsors, owners, Graph permissions, Azure roles and
  credentials. If its intake record names a tool app, the tool app's delegated
  grants and secrets go on the agent's row too. Then it joins the intake records
  in docs/agent-intake.md by object ID and flags anything that breaks the agent
  standard. It only reads. It never changes anything in Entra or Azure.

Inputs
  docs/agent-intake.md          the rows from "Agent identity object ID" to "Approved Azure roles"
  Microsoft Graph               signed in as me with read scopes only
  Azure CLI                     signed in to the same tenant, subscription havlund-lab

Outputs
  reports/agent_inventory.csv   one row per agent identity
  A short summary in the terminal

Flags
  NO_INTAKE              no intake record has the object ID
  NO_SPONSOR             Entra shows no sponsor
  SPONSOR_UNREADABLE     none of the sponsor calls worked, so the sponsor is unknown
  SPONSOR_DISABLED       a sponsor's account is turned off
  ACCESS_NOT_IN_INTAKE   a Graph permission, tool app grant or Azure role isn't approved in the intake record
  SECRET_EXPIRES_SOON    a secret or certificate ends within 30 days (or already ended)
  SECRET_TOO_LONG        a secret or certificate lasts more than 90 days (agent standard rule 6)
  REVIEW_OVERDUE         the next review date has passed
  DISABLED               the identity is turned off. Information only, not a problem

How to run
  pwsh -File scripts/agent_inventory.ps1
  A browser window opens for the Graph sign-in the first time.
#>

param(
    [string]$TenantId     = 'dd8d5970-0f8f-4b44-87c3-81181e38978b',
    [string]$Subscription = 'havlund-lab',
    [string]$IntakePath   = (Join-Path $PSScriptRoot '..\docs\agent-intake.md'),
    [string]$OutPath      = (Join-Path $PSScriptRoot '..\reports\agent_inventory.csv')
)

$ErrorActionPreference = 'Stop'
$today = (Get-Date).Date

# The Graph module is installed for Windows PowerShell, and the Azure CLI folder
# isn't always on PATH in VS Code. Add both so PowerShell 7 finds them.
$winModules = Join-Path $HOME 'Documents\WindowsPowerShell\Modules'
if ((Test-Path $winModules) -and ($env:PSModulePath -notlike "*$winModules*")) { $env:PSModulePath += ";$winModules" }
$azFolder = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin'
if (-not (Get-Command az -ErrorAction SilentlyContinue) -and (Test-Path $azFolder)) { $env:PATH += ";$azFolder" }

# ---------- Sign in, read only ----------

Import-Module Microsoft.Graph.Authentication
$scopes = 'AgentIdentity.Read.All', 'Application.Read.All', 'User.Read.All', 'DelegatedPermissionGrant.Read.All'
try {
    Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome
} catch {
    # The Windows sign-in popup fails when there's no window to attach to, like
    # in the VS Code terminal. Then sign in with a code at microsoft.com/devicelogin.
    Write-Host 'The sign-in popup did not open. Using a device code instead.'
    Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome -UseDeviceCode
}

$azAccount = az account show -o json 2>$null | ConvertFrom-Json
if (-not $azAccount -or $azAccount.tenantId -ne $TenantId) {
    az login --tenant $TenantId -o none
}
az account set --subscription $Subscription

# ---------- Helpers ----------

function Get-Graph([string]$Uri) {
    # GET with paging. Returns every item in "value", or the object itself.
    $items = @()
    $next = $Uri
    while ($next) {
        $page = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($null -ne $page.PSObject.Properties['value']) {
            $items += $page.value
            $next = $page.'@odata.nextLink'
        } else {
            return $page
        }
    }
    return $items
}

function Split-List([string]$Text) {
    # "A, B (note)" becomes @('A','B'). "none" or "none, because..." becomes @().
    if (-not $Text -or $Text -match '^\s*none\b') { return @() }
    $clean = $Text -replace '\s*\(.*\)\s*$', ''
    return @($clean -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-ShortScope([string]$Scope) {
    if ($Scope -match 'storageAccounts/([^/]+)/blobServices/default/containers/([^/]+)$') { return "$($Matches[1])/$($Matches[2])" }
    if ($Scope -match 'storageAccounts/([^/]+)$') { return $Matches[1] }
    if ($Scope -match 'resourceGroups/([^/]+)$') { return "resource group $($Matches[1])" }
    if ($Scope -match '^/subscriptions/[^/]+$') { return 'subscription' }
    if ($Scope -eq '/') { return 'root' }
    return ($Scope -split '/')[-1]
}

function Test-Credential($Label, $CredInfo, [ref]$Flags) {
    # Returns one line about the credential and adds expiry flags. Never reads a secret value.
    $start = [datetime]$CredInfo.startDateTime
    $end   = [datetime]$CredInfo.endDateTime
    $days  = [math]::Round(($end - $start).TotalDays)
    $name  = if ($CredInfo.displayName) { $CredInfo.displayName } else { $CredInfo.keyId }
    if (($end - $today).TotalDays -le 30) { $Flags.Value += 'SECRET_EXPIRES_SOON' }
    if ($days -gt 90) { $Flags.Value += 'SECRET_TOO_LONG' }
    return "$Label '$name' ends $($end.ToString('yyyy-MM-dd')) ($days days)"
}

$roleNameCache = @{}
function Get-AppRoleName([string]$ResourceId, [string]$RoleId) {
    if (-not $roleNameCache.ContainsKey($ResourceId)) {
        $sp = Get-Graph "https://graph.microsoft.com/v1.0/servicePrincipals/$ResourceId`?`$select=appRoles"
        $roleNameCache[$ResourceId] = $sp.appRoles
    }
    $role = $roleNameCache[$ResourceId] | Where-Object id -eq $RoleId
    if ($role) { return $role.value } else { return $RoleId }
}

function Get-DelegatedScopes([string]$ClientSpId) {
    # Returns each delegated scope name, from every grant the client has.
    $grants = Get-Graph "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$ClientSpId'"
    return @($grants | ForEach-Object { $_.scope -split ' ' } | Where-Object { $_ } | Sort-Object -Unique)
}

# ---------- Intake records ----------

$intake = @{}
$current = $null
foreach ($line in Get-Content $IntakePath) {
    if ($line -match '^## (AI-\d+)') { $current = @{ IntakeId = $Matches[1] }; continue }
    if ($current -and $line -match '^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|\s*$') {
        $current[$Matches[1]] = $Matches[2]
        if ($Matches[1] -eq 'Agent identity object ID') { $intake[$Matches[2].Trim()] = $current }
    }
}

# ---------- Azure roles, read once for the whole subscription ----------

$allRoles = az role assignment list --all -o json | ConvertFrom-Json

# ---------- Agent identities ----------

$agents = Get-Graph 'https://graph.microsoft.com/v1.0/servicePrincipals/microsoft.graph.agentIdentity'
$rows = @()
$sponsorCallsUsed = @()

foreach ($a in $agents) {
    $flags = @()
    $notes = @()
    $id = $a.id
    $record = $intake[$id]

    # Sponsors. Three ways to read them, in order. Never guess.
    $sponsors = $null
    $sponsorSource = ''
    $sponsorTries = [ordered]@{
        'v1.0 /sponsors'        = { Get-Graph "https://graph.microsoft.com/v1.0/servicePrincipals/$id/microsoft.graph.agentIdentity/sponsors" }
        'v1.0 $expand=sponsors' = { (Get-Graph "https://graph.microsoft.com/v1.0/servicePrincipals/$id/microsoft.graph.agentIdentity?`$expand=sponsors").sponsors }
        'beta $expand=sponsors' = { (Get-Graph "https://graph.microsoft.com/beta/servicePrincipals/$id/microsoft.graph.agentIdentity?`$expand=sponsors").sponsors }
    }
    foreach ($try in $sponsorTries.GetEnumerator()) {
        try { $sponsors = @(& $try.Value); $sponsorSource = $try.Key; break } catch { }
    }
    $sponsorText = @()
    if (-not $sponsorSource) {
        $flags += 'SPONSOR_UNREADABLE'
        $sponsorText = @('could not read')
    } elseif ($sponsors.Count -eq 0) {
        $flags += 'NO_SPONSOR'
    } else {
        $sponsorCallsUsed += $sponsorSource
        foreach ($s in $sponsors) {
            try {
                $u = Get-Graph "https://graph.microsoft.com/v1.0/users/$($s.id)?`$select=displayName,accountEnabled"
                $state = if ($u.accountEnabled) { 'enabled' } else { 'disabled' }
                if (-not $u.accountEnabled) { $flags += 'SPONSOR_DISABLED' }
                $sponsorText += "$($u.displayName) ($state)"
            } catch {
                # Not a user, for example a group. Keep its name.
                $sponsorText += "$($s.displayName) (not a user)"
            }
        }
    }

    # Owners
    $owners = @(Get-Graph "https://graph.microsoft.com/v1.0/servicePrincipals/$id/owners" | ForEach-Object { $_.displayName })

    # Graph access on the identity itself
    $appPerms = @(Get-Graph "https://graph.microsoft.com/v1.0/servicePrincipals/$id/appRoleAssignments" |
        ForEach-Object { "$($_.resourceDisplayName) $(Get-AppRoleName $_.resourceId $_.appRoleId)" })
    $delegated = Get-DelegatedScopes $id
    $approvedGraph = if ($record) { @(Split-List $record['Approved Graph permissions on the agent identity']) } else { @() }
    foreach ($p in @($appPerms) + @($delegated)) {
        $permName = ($p -split ' ')[-1]
        if ($approvedGraph -notcontains $permName) { $flags += 'ACCESS_NOT_IN_INTAKE' }
    }

    # Azure roles
    $azRoles = @($allRoles | Where-Object principalId -eq $id |
        ForEach-Object { "$($_.roleDefinitionName) on $(Get-ShortScope $_.scope)" })
    $approvedAz = if ($record) { @(Split-List $record['Approved Azure roles']) } else { @() }
    foreach ($r in $azRoles) { if ($approvedAz -notcontains $r) { $flags += 'ACCESS_NOT_IN_INTAKE' } }

    # Credentials. On the identity itself, and on its blueprint app.
    $creds = @()
    foreach ($c in @($a.passwordCredentials)) { if ($c) { $creds += Test-Credential 'identity secret' $c ([ref]$flags) } }
    foreach ($c in @($a.keyCredentials))      { if ($c) { $creds += Test-Credential 'identity certificate' $c ([ref]$flags) } }
    $blueprint = @(Get-Graph "https://graph.microsoft.com/v1.0/applications?`$filter=appId eq '$($a.agentIdentityBlueprintId)'")
    if ($blueprint.Count -eq 0) {
        $blueprint = @(Get-Graph "https://graph.microsoft.com/beta/applications?`$filter=appId eq '$($a.agentIdentityBlueprintId)'")
    }
    if ($blueprint.Count -eq 0) {
        $creds += 'blueprint app not found'
    } else {
        $bp = $blueprint[0]
        foreach ($c in @($bp.passwordCredentials)) { if ($c) { $creds += Test-Credential 'blueprint secret' $c ([ref]$flags) } }
        foreach ($c in @($bp.keyCredentials))      { if ($c) { $creds += Test-Credential 'blueprint certificate' $c ([ref]$flags) } }
        $fics = @(Get-Graph "https://graph.microsoft.com/v1.0/applications/$($bp.id)/federatedIdentityCredentials")
        foreach ($f in $fics) { if ($f) { $creds += "blueprint federated credential '$($f.name)'" } }
    }

    # Tool app named in the intake record
    $toolAppName = ''
    $toolGrants = @()
    if ($record) {
        $toolList = @(Split-List $record['Tool app'])
        if ($toolList.Count -gt 0) {
            $toolAppName = $toolList[0]
            $app = @(Get-Graph "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$toolAppName'")
            if ($app.Count -eq 0) {
                $notes += "tool app $toolAppName not found"
            } else {
                foreach ($c in @($app[0].passwordCredentials)) { if ($c) { $creds += Test-Credential 'tool app secret' $c ([ref]$flags) } }
                foreach ($c in @($app[0].keyCredentials))      { if ($c) { $creds += Test-Credential 'tool app certificate' $c ([ref]$flags) } }
                $toolSp = @(Get-Graph "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($app[0].appId)'")
                if ($toolSp.Count -gt 0) { $toolGrants = Get-DelegatedScopes $toolSp[0].id }
                $approvedTool = @(Split-List $record['Approved delegated permissions on the tool app'])
                foreach ($g in $toolGrants) { if ($approvedTool -notcontains $g) { $flags += 'ACCESS_NOT_IN_INTAKE' } }
            }
        }
    }

    # Intake join
    if (-not $record) {
        $flags += 'NO_INTAKE'
        if ($a.displayName -match '^lindhav-foundry-lindhav-agents-AgentIdentity$') {
            $notes += "Foundry project lindhav-agents' shared agent identity. Agents made before Microsoft's update used it. Ours have their own"
        } elseif ($a.displayName -match '^lindhav-foundry') {
            $notes += 'Made by the Foundry project lindhav-agents, not tied to an intake record'
        }
    } else {
        $review = $record['Next review']
        if ($review -match '(\d{4}-\d{2}-\d{2})' -and [datetime]$Matches[1] -lt $today) { $flags += 'REVIEW_OVERDUE' }
    }
    if (-not $a.accountEnabled) { $flags += 'DISABLED' }

    $rows += [pscustomobject]@{
        AgentName              = $a.displayName
        ObjectId               = $id
        Enabled                = $a.accountEnabled
        CreatedUtc             = ([datetime]$a.createdDateTime).ToUniversalTime().ToString('yyyy-MM-dd')
        BlueprintAppId         = $a.agentIdentityBlueprintId
        IntakeId               = if ($record) { $record.IntakeId } else { '' }
        Purpose                = if ($record) { $record['Purpose'] } else { '' }
        RiskTier               = if ($record) { ($record['Risk tier'] -split '\.')[0] } else { '' }
        NextReview             = if ($record -and $record['Next review'] -match '(\d{4}-\d{2}-\d{2})') { $Matches[1] } else { '' }
        IntakeStatus           = if ($record) { $record['Status'] } else { '' }
        Sponsors               = $sponsorText -join ', '
        SponsorReadWith        = $sponsorSource
        Owners                 = $owners -join ', '
        GraphAppPermissions    = $appPerms -join ', '
        GraphDelegatedGrants   = $delegated -join ', '
        AzureRoles             = $azRoles -join ', '
        ToolApp                = $toolAppName
        ToolAppDelegatedGrants = $toolGrants -join ', '
        Credentials            = $creds -join ' | '
        Flags                  = (@($flags | Select-Object -Unique) -join ' ')
        Note                   = $notes -join '. '
    }
}

# ---------- Save and summarize ----------

New-Item -ItemType Directory -Force (Split-Path $OutPath) | Out-Null
$rows | Export-Csv -Path $OutPath -Encoding utf8

$problemRows = @($rows | Where-Object { ($_.Flags -split ' ' | Where-Object { $_ -and $_ -ne 'DISABLED' }).Count -gt 0 })
Write-Host ''
Write-Host "Agent identities found  $($rows.Count)"
Write-Host "With a problem flag     $($problemRows.Count)"
$flagCounts = $rows.Flags -split ' ' | Where-Object { $_ } | Group-Object | Sort-Object Name
foreach ($f in $flagCounts) { Write-Host ("  {0,-22} {1}" -f $f.Name, $f.Count) }
Write-Host ''
foreach ($r in $rows) {
    $f = if ($r.Flags) { $r.Flags } else { 'no flags' }
    $tag = if ($r.IntakeId) { $r.IntakeId } else { 'no intake' }
    Write-Host ("  {0,-9} {1}  {2}" -f $tag, $r.AgentName, $f)
}
$used = ($sponsorCallsUsed | Select-Object -Unique) -join ', '
Write-Host ''
Write-Host "Sponsors read with      $(if ($used) { $used } else { 'none worked' })"
Write-Host "Saved                   $((Resolve-Path $OutPath).Path)"
