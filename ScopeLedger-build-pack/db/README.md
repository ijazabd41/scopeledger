# ScopeLedger database

Apply `../schema.sql`, then the files in `migrations/` in numeric order with a migration owner. The schema and privileged routines require PostgreSQL 14+ and `pgcrypto`.

The migrations create three `NOLOGIN` group roles:

- `scopeledger_reader`: bounded read access for evidence tools.
- `scopeledger_web`: OTP, publication, and exact client-decision routines only.
- `scopeledger_worker`: proposal preparation, claims, result recording, completion, and expiry.

Create platform login roles outside source control and grant membership in only the required group. Do not give the n8n webhook credential ownership of the schema or direct table mutation rights.

## Local validation

From the repository pack directory, set temporary local-only environment values and run:

```powershell
$env:POSTGRES_ADMIN_PASSWORD = '<random-local-value>'
$env:N8N_ENCRYPTION_KEY = '<random-local-value-at-least-32-bytes>'
docker compose -f deployment/docker-compose.local.yml --project-name scopeledger-local up -d postgres
docker cp db/tests/authorization_flow.sql scopeledger-local-postgres-1:/tmp/authorization_flow.sql
docker exec scopeledger-local-postgres-1 psql -v ON_ERROR_STOP=1 -U postgres -d scopeledger -f /tmp/authorization_flow.sql
./db/tests/run_concurrency_test.ps1
```

The harness is local verification only. It is not evidence of Alternate Clouds hosting or live Gmail, Drive, GitHub, model, or MCP connectivity.
