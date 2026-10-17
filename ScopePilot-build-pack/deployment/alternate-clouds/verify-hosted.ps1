param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^https://')]
  [string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
$root = $BaseUrl.TrimEnd('/')
$readiness = Invoke-RestMethod -Method Get -Uri "$root/healthz/readiness" -TimeoutSec 20
if ($readiness.status -ne 'ok') { throw 'n8n readiness response was not ok.' }

$receipt = Invoke-RestMethod -Method Post -Uri "$root/webhook/scopeledger-health-v1" `
  -ContentType 'application/json' -Body '{"probe":"g0-manual-verification"}' -TimeoutSec 20
if ($receipt.status -ne 'ok' -or $receipt.service -ne 'scopeledger') {
  throw 'ScopePilot health webhook returned an unexpected receipt.'
}

[pscustomobject]@{
  tested_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  base_url = $root
  readiness = $readiness.status
  webhook_status = $receipt.status
  service = $receipt.service
  workflow_version = $receipt.workflow_version
} | ConvertTo-Json
