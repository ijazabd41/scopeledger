# Seven-day build plan

Team labels are placeholders: Dev A owns business integrations/workflows; Dev B owns deployment/database/security. Assign actual names in progress.md. Both review authorization and recovery logic. AI-assisted coding is permitted by the user's plan; review generated code before execution.

| Day | Dev A | Dev B | Exit gate |
|---|---|---|---|
| 1 | Gmail/Docs/GitHub credential smoke checks; live sample resources | Alternate Clouds n8n+DB, schema trial, webhook and restart tests | G0 hosting and G1 integrations |
| 2 | Onboarding, email dedup, evidence retrieval | Atomic routines, project locks, review forms and OTP prototype | G2 intake + identity |
| 3 | AI investigator, MCP evidence tools, output validation | Manager publication, immutable proposal versions | G3 manager can publish evidence-based options |
| 4 | Client decision UX, actual mail notices | Atomic acceptance, token expiry, action outbox | G4 exactly one accepted choice under concurrent requests |
| 5 | GitHub action adapters and Docs revision publication | Worker leases, verification, partial-effect recovery | G5 real accepted change applied and verified |
| 6 | Agent evaluation and integration test evidence | Security, crash/restart and failure injection; fix blockers | G6 all critical tests passing |
| 7 | Demo recording and documentation | Deployment freeze, safe exports, access checks | G7 reviewable submission |

## Gates and stop conditions
G0: hosted n8n + persistent DB + restart success. If not, ask platform support immediately; do not move application off Alternate Clouds as an undisclosed fallback.
G1: live Gmail receive/send, Docs read/create/read, GitHub read/create/update and model request. Missing credentials are explicit blockers, not mock implementations.
G2: one new email → one routed case → evidence; OTP verifies configured actor.
G3: valid structured investigation and actual MCP tool trace; manager signs off exact alternatives.
G4: stale/duplicate/wrong-actor decisions fail; acceptance transaction passes race test.
G5: client-selected swap causes actual external changes; read-back shows exact result.
G6: critical tests including restart and uncertain write pass with stored evidence.
G7: reviewer opens deployed project, video, source export and receipts without personal credentials.

## Cut order
Cut custom dashboard styling, auto PDF extraction, Slack, payments, multiple projects, OCR and generalized search. Preserve actual provider calls, approval identity/version binding, client choice, action ledger and independent verification. If needed support only scope-swap proposals first; clearly label other commercial branches as unavailable rather than fake success.

## Daily routine
Read progress.md, select next unmet gate, assign task IDs, implement smallest end-to-end increment, run relevant tests, record evidence and blockers, export workflows. Use one shared workflow naming convention and do not edit the same workflow concurrently. Secrets are configured manually in the deployed n8n credential store.
