# Alternate Clouds deployment plan

## Status
Not deployed to Alternate Clouds. The user requested a manual deployment package instead of agent login. The operator runbook is at `deployment/alternate-clouds/README.md`. A local validation harness pins n8n 2.43.7 with PostgreSQL 17.6; it passed database readiness, workflow import/publication, production webhook, provisioning, and restart checks, but local evidence does not satisfy G0.

The checked-in local harness keeps n8n operational tables in database `n8n` and ScopeLedger business state in database `scopeledger`. Production must preserve this credential/database separation.

## Gate G0 — deploy before building
1. Confirm event credits and supported Docker service type.
2. Deploy a pinned official n8n image (record exact version/digest); avoid floating latest.
3. Expose the configured n8n port via public HTTPS ingress. Protect the editor; publish only intended webhook/forms endpoints.
4. Provision PostgreSQL with persistent storage, backups and private connectivity where supported. Separate n8n and business databases/roles. Confirm database service engine/version rather than assuming its default.
5. Set a stable N8N_ENCRYPTION_KEY via secrets. Persist /home/node/.n8n as required by pinned deployment; also preserve any local binary data or configure a supported alternative. Prefer bounded text-only evidence for MVP.
6. Set production `N8N_WEBHOOK_URL` and editor base URL to actual HTTPS URLs; configure trusted proxy count from actual ingress topology, not a guessed value. `WEBHOOK_URL` is deprecated in the pinned n8n 2.43.7 runtime.
7. Configure database SSL according to provider CA requirements; never disable verification merely to make it work.
8. Create test workflow, call production webhook externally, restart service and confirm workflow, credential access and business row survive.
9. Test Google OAuth redirect, outbound Google/GitHub/model connectivity, inbound client POST and MCP authenticated transport. Mark G0 passing only with evidence.

## Configuration
See environment.example. DB_* settings in it configure n8n's own operational database. Business DB connection is a separately stored n8n credential; do not paste business SQL into n8n internal tables. Use explicit named connection settings from the selected n8n release.

## Operational setup
Publish workflows after credential setup. Production URLs differ from editor test URLs. Configure timezone intentionally; store UTC timestamps. Restrict large webhook payloads; confirm proxy timeout. Review execution-data retention and payload logging; use redacted metadata and prevent raw secrets from being saved. Restrict MCP access using a separate credential and allowlist tools.

## Acceptance on the hosted deployment
- External webhook and form accessible in a clean browser.
- Real Gmail intake and reply path succeed from deployed service.
- Real Drive read/create/read-back and GitHub read/write/read-back succeed.
- Service restart preserves unconsumed approvals and accepted-pending actions.
- Model and MCP tools work through actual ingress with credentials.
- No credential values in workflow exports, repository, video or screenshots.
- Judge demo account can access only demo project; clients cannot access editor.

## Rollback
Before deployment changes export workflows without secrets and back up databases/key. Deploy a recorded known-good image/config. Database migrations require backup and a reviewed migration path; rolling back an image does not reverse data migrations or external writes. Never replay accepted cases to test rollback.

## Cost controls
Record starting credits, n8n/DB allocation, actual model cost and 24-hour idle burn. Limit tool calls, disable unnecessary schedules and stop unused services after event obligations. The screenshot balance is not a verified budget for the final topology.

## Licensing boundary
Check n8n Sustainable Use License before commercial hosted rollout or exposing workflow-management features to customers. Hackathon architecture does not establish permission to run a multi-tenant white-label automation platform. Record the exact intended commercial use and confirm applicable terms; this does not block writing or testing the authorized prototype.
