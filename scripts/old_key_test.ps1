<#
Old key test for Lindhav Bank (Phase 5 step 3).

What it does
  Proves an old key gets turned away after key access is off on the Foundry
  resource lindhav-foundry. It turns key access back on for a short time, reads
  KEY 1 into memory only and retries a model call with it until it gets a 200.
  Then it turns key access off again and retries the same old key every 2 minutes
  until it gets a 403. Microsoft's docs say 401, but Azure really sends
  403 AuthenticationTypeDisabled. Key access is turned off again in a finally block, so it
  never stays on if the script fails. The key is never printed, logged or saved.

Limits
  Waits up to 15 minutes for the 200. If none comes, it turns keys off anyway.
  Waits up to 2 hours for the 403. If the old key still works, it stops and says so.

Inputs
  Azure CLI                     signed in to the Lindhav Bank tenant, subscription havlund-lab
  lindhav-foundry               the Foundry resource in rg-lindhav-ai and its gpt-5.4-mini deployment

Outputs
  old_key_test.log              next to the script. Times, HTTP codes and the disableLocalAuth setting only
  The same lines in the terminal

How to run
  Run it in its own PowerShell window, not from Claude Code.
  pwsh -File scripts/old_key_test.ps1
#>

$env:PATH += ";C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin"
$log = Join-Path $PSScriptRoot "old_key_test.log"
function Write-Log($m) { $line = "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))  $m"; $line | Tee-Object -FilePath $log -Append }

$id  = az cognitiveservices account show -n lindhav-foundry -g rg-lindhav-ai --query id -o tsv
$uri = "https://lindhav-foundry.cognitiveservices.azure.com/openai/deployments/gpt-5.4-mini/chat/completions?api-version=2024-10-21"
$body = '{"messages":[{"role":"user","content":"Reply with the word OK."}],"max_completion_tokens":200}'

function Set-LocalAuthOff([bool]$off) {
  $v = if ($off) { "true" } else { "false" }
  $r = az resource update --ids $id --set "properties.disableLocalAuth=$v" --query "properties.disableLocalAuth" -o tsv
  Write-Log "disableLocalAuth set to $r"
}
function Invoke-KeyCall($k) {
  try { $r = Invoke-WebRequest -Uri $uri -Method Post -Headers @{ "api-key" = $k } -Body $body -ContentType "application/json"; return @{ code = [int]$r.StatusCode; msg = "" } }
  catch { return @{ code = [int]$_.Exception.Response.StatusCode.value__; msg = $_.ErrorDetails.Message } }
}

$key = $null
try {
  Write-Log "Start. Turning key access back on for the test"
  Set-LocalAuthOff $false

  $got200 = $false
  $deadline = (Get-Date).AddMinutes(15)
  while ((Get-Date) -lt $deadline) {
    if (-not $key) { $key = az cognitiveservices account keys list -n lindhav-foundry -g rg-lindhav-ai --query key1 -o tsv 2>$null }
    if ($key) {
      $res = Invoke-KeyCall $key
      Write-Log "Key call with keys on -> HTTP $($res.code)"
      if ($res.code -eq 200) { $got200 = $true; break }
    } else { Write-Log "Keys not listable yet" }
    Start-Sleep -Seconds 60
  }
  if (-not $got200) { Write-Log "No 200 within 15 minutes. Turning keys off anyway" }
}
finally {
  Write-Log "Turning key access off again"
  Set-LocalAuthOff $true
}

if ($got200) {
  $deadline = (Get-Date).AddHours(2)
  $got403 = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 120
    $res = Invoke-KeyCall $key
    Write-Log "Old key call with keys off -> HTTP $($res.code) $($res.msg)"
    if ($res.code -eq 403) { $got403 = $true; break }
  }
  if (-not $got403) { Write-Log "Old key still worked after 2 hours. Stopping" }
}
$key = $null
Remove-Variable key
Write-Log "Done. Final setting: $(az cognitiveservices account show -n lindhav-foundry -g rg-lindhav-ai --query properties.disableLocalAuth -o tsv)"
