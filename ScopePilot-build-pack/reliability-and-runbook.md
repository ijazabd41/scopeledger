# Reliability and operational runbook

## Action ledger
Persist intent before provider writes, then persist provider response and independent verification. Business idempotency key survives n8n restarts and reruns. Separate each issue create, existing-issue update, scope-document create/fill and notification into distinct actions. Never claim exactly-once behavior across Gmail, Docs and GitHub.

## Retry policy
Read requests: 30-second timeout, up to 3 attempts with exponential backoff and jitter; honor Retry-After. Model: bounded 90-second investigation budget and one repair attempt. Writes: retry only confirmed absent or provider-idempotent actions. 400/401/403/422 are configuration/validation failures, not automatic transient retries. 429 and selected 5xx may be retried after reconciliation. Tune based on actual provider behavior.

## Unknown effects
GitHub issue create timeout: inspect repository issues using unique action marker, including pagination and closed issues. One matching issue with correct fields → verify. Multiple/conflicting matches → block. No immediate match does not prove absence; retry reads before manual resolution.
Docs create timeout: inspect dedicated folder/Drive metadata and revision marker; empty or mismatched document is not complete. Populate an identified empty draft only after verifying provenance.
Email timeout: query Sent using the unique mail marker/Message-ID if supported. Absence may be eventual; if uncertain, leave notification unknown and let operator decide. Duplicate email risk cannot be eliminated by a database key alone.

## Partial application
Acceptance is a durable business fact. If issue A is verified but Docs fails, leave the accepted change pending, set partially_applied, block subsequent project changes and retry the unfinished document action after reconciliation. Do not automatically reopen/erase tasks or pretend acceptance vanished. Material changes to the recovery plan require manager reapproval and, if commitments change, new client acceptance.

## Concurrency and external edits
Preflight expected hashes, acquire project execution lease, perform actions and read back. Use provider conditional writes where supported. Without them, do not promise race-free writes; avoid overwriting task bodies and prefer provenance comments/labels. Unexpected edits require review. A stale worker must not continue after lease loss; check ownership before each next action.

## Recovery procedures
| Incident | Operator procedure |
|---|---|
| n8n restarted | Verify DB/credentials; scan running leases; reconcile unknown effects; resume only pending safe actions |
| OAuth revoked | Block action, reconnect credential, re-read evidence; reapprove if state changed |
| Model unavailable | Show analysis unavailable; route evidence to manager; preserve intake |
| Proposal expired | Publish a new version after rechecking baseline; never extend a token in place |
| Duplicate acceptance | Return existing receipt; investigate only if payload conflicts |
| Manual provider edit | Compare current state, preserve edit and request new plan |
| Database unavailable | Reject decision as unavailable; no external writes; retry client submission safely later |
| Mail delivery failed | Preserve agreement/execution status; retry or contact configured actor; do not reapply tasks |

## Observability
Log case/proposal/action IDs, workflow version, provider status, attempt count, latency, safe resource IDs and error codes. No OTP/token/full email body in logs. Alerts: accepted case stalled >10 min, unknown write, expired worker, repeated auth failures and low remaining credits. These thresholds are proposed defaults, not measured SLAs.

## Backup
Back up business database, n8n database, encryption key, pinned image version and workflow exports. Test restoration with real demo credentials in a controlled environment; a backup without its encryption key may not restore usable credentials. Protect and expire sensitive backups.
