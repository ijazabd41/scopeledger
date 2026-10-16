param([string]$Container = 'scopeledger-local-postgres-1')
$ErrorActionPreference = 'Stop'

docker cp db/tests/concurrency_seed.sql "${Container}:/tmp/concurrency_seed.sql"
docker cp db/tests/accept_a.sql "${Container}:/tmp/accept_a.sql"
docker cp db/tests/accept_b.sql "${Container}:/tmp/accept_b.sql"
docker exec $Container psql -v ON_ERROR_STOP=1 -U postgres -d scopeledger -f /tmp/concurrency_seed.sql
if ($LASTEXITCODE -ne 0) { throw 'Concurrency fixture setup failed.' }

$jobA = Start-Job -ScriptBlock {
  param($Target)
  docker exec $Target psql -v ON_ERROR_STOP=1 -U postgres -d scopeledger -f /tmp/accept_a.sql 2>&1
  [pscustomobject]@{ Name = 'A'; ExitCode = $LASTEXITCODE }
} -ArgumentList $Container
$jobB = Start-Job -ScriptBlock {
  param($Target)
  docker exec $Target psql -v ON_ERROR_STOP=1 -U postgres -d scopeledger -f /tmp/accept_b.sql 2>&1
  [pscustomobject]@{ Name = 'B'; ExitCode = $LASTEXITCODE }
} -ArgumentList $Container

$results = @($jobA, $jobB) | Wait-Job | Receive-Job
@($jobA, $jobB) | Remove-Job -Force
$exitCodes = @($results | Where-Object { $_.PSObject.Properties.Name -contains 'ExitCode' } | Select-Object -ExpandProperty ExitCode)
if (($exitCodes | Where-Object { $_ -eq 0 }).Count -ne 1 -or
    ($exitCodes | Where-Object { $_ -ne 0 }).Count -ne 1) {
  $results | Out-String | Write-Host
  throw 'Expected exactly one concurrent acceptance to succeed and one to conflict.'
}

$verification = docker exec $Container psql -At -U postgres -d scopeledger -c @"
SET search_path TO scopeledger, public;
SELECT (SELECT count(*) FROM decisions WHERE case_id IN
 ('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000302'))
 || '|' ||
 (SELECT count(*) FROM scope_versions WHERE project_id='00000000-0000-0000-0000-000000000101'
  AND status='accepted_pending_sync')
 || '|' ||
 (SELECT count(*) FROM actions WHERE case_id IN
 ('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000302'));
"@
if ($LASTEXITCODE -ne 0 -or ($verification | Select-Object -Last 1) -ne '1|1|1') {
  throw "Concurrency invariant failed. Observed: $verification"
}
Write-Output 'concurrent_project_acceptance_ok: exactly one decision, one pending scope, one action'
