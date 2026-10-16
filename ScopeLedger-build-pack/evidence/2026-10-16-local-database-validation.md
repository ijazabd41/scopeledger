# Local database and runtime validation

Timestamp: 2026-10-16T21:14:01Z through 2026-10-16T21:40:34Z  
Environment: local Docker Desktop; PostgreSQL 17.6; n8n 2.43.7  
Scope: implementation evidence only. This is not Alternate Clouds or live-provider evidence.

## Clean initialization

- Recreated the dedicated `scopeledger-local` test volume.
- PostgreSQL 17.6 initialized separate `n8n` and `scopeledger` databases. An earlier PostgreSQL 16.4 run passed the SQL checks but n8n reported that version as compatibility-only, so the package was upgraded and fully retested on 17.6.
- `schema.sql`, migration 002, and migration 003 committed without errors.
- n8n completed its own operational migrations in the `n8n` database.
- `GET http://127.0.0.1:5679/healthz/readiness` returned `200 {"status":"ok"}`.
- Runtime version reported by the container: `2.43.7`.

## DBU01 — authorization and execution flow

Command: `psql -v ON_ERROR_STOP=1 -U postgres -d scopeledger -f /tmp/authorization_flow.sql`

Observed terminal marker: `authorization_flow_ok`.

Assertions exercised:

- draft and published proposals enqueue no provider actions;
- manager OTP/token is role- and stage-bound;
- published proposal content is immutable;
- client acceptance uses the stored option and produces one pending revision plus the exact actions;
- identical replay returns the original receipt without duplicate decisions/actions;
- leased actions require independent verification;
- the new baseline activates only after all mandatory actions are verified.

## DBU02 — concurrent project acceptance

Two independent PostgreSQL sessions submitted acceptances for two cases bound to the same active baseline.

Observed terminal marker: `concurrent_project_acceptance_ok: exactly one decision, one pending scope, one action`.

The losing transaction returned a conflict; it did not create a decision, scope revision, or action.

## DBU03 — least privilege

Observed privilege tuple: `f|t|t|f` for:

1. web role may directly insert actions: false;
2. web role may execute the decision routine: true;
3. reader role may read evidence: true;
4. reader role may read authentication challenges: false.

## DBU04 — local restart persistence

The dedicated n8n container restarted, returned readiness 200 again, and the business database still contained one `awaiting_client` case. No provider write was triggered.

## DBU05 — imported production webhook

`workflows/WF-G0-health.json` imported successfully into n8n 2.43.7, was published with the pinned release's `publish:workflow` command, and registered one POST webhook. After a graceful container restart:

- `/healthz/readiness` returned `{"status":"ok"}`;
- `POST /webhook/scopeledger-health-v1` returned `{"status":"ok","service":"scopeledger","workflow_version":"g0-v1"}`;
- the pending business-state count remained `1`;
- the deprecated `WEBHOOK_URL` warning was eliminated by using `N8N_WEBHOOK_URL`.

## DBU06 — clean manual provisioning script

`deployment/alternate-clouds/provision.psql` ran against a fresh disposable PostgreSQL 17.6 container with synthetic local-only passwords. It created both databases and four login roles, applied all migrations, and ended with `scopeledger_provisioning_complete`. Observed privileges were `t|t|f|t|f` for n8n connect, web decision execute, web direct action insert, reader evidence select, and reader auth select respectively.

## Boundaries

- No Alternate Clouds service, public HTTPS webhook, real credential persistence, provider integration, or hosted restart was tested.
- Gmail, Drive/Docs, GitHub, model, and MCP tests remain NOT RUN.
- Test credentials and OTP values were local synthetic values and are not recorded here.
