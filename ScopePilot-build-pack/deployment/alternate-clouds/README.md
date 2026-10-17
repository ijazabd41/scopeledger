# Manual Alternate Clouds deployment

This directory is the operator handoff for G0. It does not contain credentials and does not claim the deployment has been performed.

Pinned candidate versions:

- n8n: `docker.n8n.io/n8nio/n8n:2.43.7`
- PostgreSQL: 17.x (the clean local verification harness uses 17.6)

The Alternate Clouds dashboard and current `acc` CLI both support project services, versioned public Docker images, environment variables, logs, shell access, resource/storage selection, and spend controls. Composite templates are dashboard-only. Confirm each field shown by the live platform instead of substituting an old `af` CLI command.

## Package contents

- `service-settings.md`: exact service topology and environment-variable mapping.
- `invoke-provision.ps1` and `provision.psql`: secure-prompt first-install database/login bootstrap; passwords are passed through temporary process environment variables and never written to disk or command history.
- `verify-hosted.ps1`: checks n8n readiness and the published G0 webhook.
- `g0-checklist.md`: deployment, restart, evidence, and rollback checklist.
- `../../workflows/WF-G0-health.json`: secret-free bootstrap workflow for the production webhook test.
- `../../workflows/WF-01*.json` through `WF-07*.json`: inactive, secret-free business workflow exports.
- `../../schema.sql` plus `../../db/migrations/*.sql`: business schema and privileged routines.

## 1. Create the project and services

1. Sign in at `https://clouds.alternatefutures.ai` yourself.
2. Select the intended organization and create one project named `scopepilot-mvp`.
3. Set a budget or auto-stop appropriate for the event account before deploying.
4. In that project, deploy a PostgreSQL 17 database/template with persistent storage and backups. Do not expose it publicly unless temporarily required for the bootstrap; prefer a private project link. n8n 2.43.7 reports PostgreSQL 16 as compatibility-only, so do not choose 16 for the deployment.
5. Record the internal host, port, admin database, admin user, CA/TLS requirements, and service ID in a private operator record.
6. Do not deploy n8n yet. Provision its database first.

The platform’s current dashboard asks for region, resources, storage, environment variables, port, and spend control. Start with modest CPU/memory and increase only after observing actual use. Storage must be persistent; an ephemeral database does not pass G0.

## 2. Provision PostgreSQL

Use a trusted workstation with `psql` 14+ and the database service’s TLS connection settings. From the repository root:

```powershell
./deployment/alternate-clouds/invoke-provision.ps1 -AdminDatabaseUrl '<ADMIN_DATABASE_URL_WITH_TLS_VERIFICATION>'
```

The launcher prompts, without echo, for four fresh passwords:

- n8n operational database login;
- read-only investigator/MCP login;
- public review-webhook login;
- execution-worker login.

It creates separate `n8n` and `scopeledger` databases, applies the checked-in migrations, and maps each login to a `NOLOGIN` group role. The launcher clears all four temporary environment variables in a `finally` block. Run it once on a fresh service. Later schema changes require a numbered forward migration and a backup/restore plan; do not rerun the starter schema over live data. If the service has no temporary external endpoint, use its dashboard shell or `acc ssh`, transfer this pack using the platform-supported file-transfer flow shown by `acc cp --help`, and use the platform's secret injection mechanism to set the four `SCOPELEDGER_*_DB_PASSWORD` environment variables before invoking `provision.psql`. Do not paste secrets into shell history or source files.

Expected final marker: `scopeledger_provisioning_complete`.

## 3. Deploy n8n

Deploy a Docker-image service in the same project:

- image: `docker.n8n.io/n8nio/n8n:2.43.7`
- container port: `5678`
- public HTTPS URL: platform-assigned service URL
- persistent storage mounted at `/home/node/.n8n`
- database link: the PostgreSQL service from step 1

Enter the values from `service-settings.md` in the dashboard’s secret/environment UI. Generate a fresh `N8N_ENCRYPTION_KEY`; do not reuse the local test value. Set `N8N_WEBHOOK_URL`, `N8N_EDITOR_BASE_URL`, and `PUBLIC_REVIEW_URL` only after the platform assigns the public URL. Redeploy after changing them.

Before proceeding, verify:

```text
GET https://<service-host>/healthz/readiness
200 {"status":"ok"}
```

Protect the editor with n8n owner authentication and, where the platform supports it, network/access restrictions. Clients receive only explicit form/webhook URLs.

## 4. Configure n8n credentials

Create these credentials manually in n8n; values stay encrypted under the stable encryption key:

1. `scopeledger-reader-db`: PostgreSQL database `scopeledger`, reader login.
2. `scopeledger-web-db`: PostgreSQL database `scopeledger`, web login.
3. `scopeledger-worker-db`: PostgreSQL database `scopeledger`, worker login.
4. `scopeledger-gmail`: dedicated Gmail OAuth credential.
5. `scopeledger-google-oauth`: generic OAuth2 credential with Drive file and Docs scopes.
6. `scopeledger-github`: repository-scoped GitHub credential.
7. `scopeledger-gemini-api-key`: Header Auth credential using `x-goog-api-key`.
8. `scopeledger-internal-webhook`: Header Auth credential with a fresh random header/value pair.
9. Separate authenticated MCP credential after the MCP workflow is implemented.

Use the exact OAuth redirect URI displayed by the deployed n8n instance. Never copy values into workflow JSON or this repository.

## 5. Import and publish the G0 workflow

Import `workflows/WF-G0-health.json` through n8n. Inspect the two nodes, save, and publish it. The production route is:

```text
POST https://<service-host>/webhook/scopeledger-health-v1
```

It returns only a static safe receipt; it performs no business write. Run:

```powershell
./deployment/alternate-clouds/verify-hosted.ps1 -BaseUrl 'https://<service-host>'
```

Then restart/redeploy n8n from Alternate Clouds, wait for readiness, and run the verifier again. Confirm a pending business row remains unchanged. Record timestamps, service/deployment IDs, the pinned image, and redacted output in a new evidence file.

## 6. Import the business workflows

Import every JSON file under `workflows/`. The exports are intentionally inactive and their
credential IDs are placeholders. For each workflow:

1. Open every credentialed node and map it to the exact credential name from step 4.
2. Confirm Code and HTTP Request nodes match the checked-in export.
3. Keep success and error execution payload persistence disabled because OTPs and private client
   text pass through these workflows.
4. Publish in this order: WF01, WF01A, WF02, WF02B, WF03, WF03B, WF04, WF05, WF06, WF07, WF08, WF09.
5. Do not publish WF01A until the configured Gmail mailbox and sender/project mapping are ready.

The current exports include real Gmail intake, Drive/Docs reads and writes, GitHub reads and writes,
Gemini investigation, separated OTP confirmation, scheduled provider execution, reminders, outbox,
lease reconciliation, and a bearer-authenticated read-only MCP server. They still require credentialed
smoke tests, a real MCP client trace, and polished review forms.

## 7. Continue to G1

Follow `integration-setup.md` using dedicated demo resources. A provider test passes only after a real write and independent read-back. Do not mark T01/T02 or any provider test passing from the local evidence bundled here.

## Stop conditions

Stop and correct the deployment if any of these occur:

- PostgreSQL has no persistent storage or verified backup path.
- TLS verification must be disabled to connect.
- n8n cannot preserve its encryption key or `/home/node/.n8n` data.
- the editor is publicly usable without owner authentication.
- the public URL is HTTP-only.
- the database roles have direct privileges outside their documented boundary.
- any workflow export or log contains a secret, OTP, review token, or raw private message.
