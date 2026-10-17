# Secure workflow implementation evidence

Timestamp: 2026-10-17T04:37:34Z  
Environment: dedicated local Docker harness; PostgreSQL 17.6; n8n 2.43.7  
Scope: implementation and compatibility evidence only. This is not hosted or live-provider acceptance evidence.

## What changed

- Added migration 005 with database-owned email intake, evidence persistence, separate manager/client OTP request and confirmation boundaries, and conditional case finalization.
- Bound manager OTP challenges to the exact case row version reviewed.
- Replaced the workflows that issued and consumed their own OTPs with separate request and confirm workflows.
- Replaced fake notification success with a Gmail send followed by provider message-ID recording.
- Replaced public reminder/reconciliation webhooks with schedule triggers.
- Replaced the action dispatcher stub with provider branches for GitHub create/supersede and Google Drive/Docs create, populate, read-back, result recording, and finalization.
- Added a real Gmail trigger adapter and an internal-header-authenticated intake workflow.
- Added migration 004 and 005 to both hosted and local provisioning paths.
- Made every workflow export inactive with placeholder credential IDs for safe import.

## Database integration tests

`db/tests/secure_workflow_boundaries.sql` completed with marker:

```text
secure_workflow_boundaries_ok
```

This test verified separate manager/client challenge confirmation, case-version binding, publication, acceptance, and exact action enqueueing.

`db/tests/intake_evidence_flow.sql` initially exposed an ambiguous `case_id` reference in `record_investigation_result`. Migration 005 was corrected and the test then completed with marker:

```text
intake_evidence_flow_ok
```

This test verified unknown-sender blocking, provider-message deduplication, configured-client routing, investigation persistence, and two-source evidence versioning.

Effective privilege tuple:

```text
web_request_manager=t | web_confirm_client=t | worker_ingest=t | worker_finalize=t | web_direct_action_insert=f
```

## n8n compatibility

All 13 sanitized workflow JSON files parsed with strict JSON parsing and imported together using the pinned n8n CLI:

```text
Importing 13 workflows...
Successfully imported 13 workflows.
```

The import proves workflow schema compatibility, not provider credentials or successful live execution.

## Deployment-package verification

- Rehearsed `provision.psql` against a disposable PostgreSQL 17.6 instance from a clean database. Schema plus migrations 002–005 completed and emitted `scopeledger_provisioning_complete`.
- Confirmed the provisioned login-role privilege tuple: n8n database connect allowed; web decision execution allowed; direct web action inserts denied; reader evidence access allowed; reader challenge access denied.
- Validated `docker-compose.local.yml` with the included example environment file.
- Parsed the three PowerShell operator/test scripts with the PowerShell language parser without errors.
- Re-ran both transactional database integration suites after the final changes; both completion markers were returned.
- Re-imported all 13 final workflow exports into n8n 2.43.7 after the client-response privacy adjustment.
- Scanned the package for common API-key, database-URL, and private-key patterns; no embedded secrets were found.
- Resolved all relative Markdown links and ran the repository whitespace/error check successfully.

## Test-ledger correction

The earlier Python lifecycle and Docs adapter artifacts remain useful development evidence, but they do not satisfy release tests requiring real Gmail, real Google Docs, human OTP entry, deployed n8n execution, or Alternate Clouds hosting. All T01–T42 release rows are therefore reset to `NOT RUN`. The original evidence files are retained; no history was deleted.

New supplemental checks DBU07–DBU09 record the validated database boundaries, intake/evidence flow, and pinned n8n import compatibility.

## Remaining verification

- Map real n8n credentials and execute Gmail, Google Docs, GitHub, and Gemini smoke tests.
- Publish the authenticated MCP server and verify a real client tool trace.
- Exercise provider failure/ambiguous-outcome paths through n8n.
- Deploy manually on Alternate Clouds and run restart, privacy, backup/restore, UI, and full end-to-end acceptance tests.
