[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$AdminDatabaseUrl
)

$ErrorActionPreference = 'Stop'

function Read-TemporarySecret {
  param([Parameter(Mandatory = $true)][string]$Prompt)

  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
  }
  finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
  }
}

try {
  $env:SCOPELEDGER_N8N_DB_PASSWORD = Read-TemporarySecret 'n8n_runtime password'
  $env:SCOPELEDGER_READER_DB_PASSWORD = Read-TemporarySecret 'scopeledger_reader_login password'
  $env:SCOPELEDGER_WEB_DB_PASSWORD = Read-TemporarySecret 'scopeledger_web_login password'
  $env:SCOPELEDGER_WORKER_DB_PASSWORD = Read-TemporarySecret 'scopeledger_worker_login password'

  $scriptPath = Join-Path $PSScriptRoot 'provision.psql'
  & psql $AdminDatabaseUrl -v ON_ERROR_STOP=1 -f $scriptPath
  if ($LASTEXITCODE -ne 0) {
    throw "psql provisioning failed with exit code $LASTEXITCODE"
  }
}
finally {
  Remove-Item Env:SCOPELEDGER_N8N_DB_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SCOPELEDGER_READER_DB_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SCOPELEDGER_WEB_DB_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SCOPELEDGER_WORKER_DB_PASSWORD -ErrorAction SilentlyContinue
}
