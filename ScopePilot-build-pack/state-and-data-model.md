# State, data and concurrency

## Canonical states
Cases: received → investigating → awaiting_manager → awaiting_client → accepted_pending_sync → applying → completed. Side paths: clarification_required, rejected, expired, blocked, partially_applied. Return to investigating after new evidence; never overwrite the original request.

Proposals: draft → published → accepted/rejected/expired/superseded. Published payloads are immutable. Manager edits create a higher version. Acceptance records survive execution failures.

Actions: pending → running → verified. Failure may become retryable, unknown or blocked. Running with an expired worker lease becomes unknown and requires reconciliation before reclaim.

Scope versions: draft, accepted_pending_sync, active, superseded. Only a fully verified execution activates the new baseline. Previous baseline stays active until then; project has an unresolved accepted change and is locked against further changes.

## Entities
See schema.sql for starter tables. Important invariants are enforced by transactional application routines, not only table constraints.

| Entity | Purpose |
|---|---|
| projects | Allowlisted client/manager, repo and Drive folder; active baseline and lock version |
| scope_versions | Normalized agreed deliverables and external document evidence |
| cases | Incoming message, investigation state and source evidence version |
| evidence | Resource snapshots/excerpts with provider revision and hash |
| proposals | Immutable options, evidence version and baseline binding |
| auth_challenges | Rate-limited, short-lived email OTP challenges |
| review_tokens | High-entropy one-time capability after verification; bound to actor and decision stage |
| decisions | Exact choice, actor and proposal hash; append-only |
| actions | Provider writes, idempotency keys, expected/current state and worker leases |
| notifications | Outbox plus sent/unknown status, provider message IDs |
| audit_events | Append-only operational history; not a tamper-proof ledger |

## Approval transaction (implementation contract)
Use one stored PostgreSQL routine or one transactional query on a single connection. Multiple n8n Postgres nodes issuing BEGIN/COMMIT do not guarantee the same connection.
1. Lock project row, then case, then proposal, then token in that order on every path.
2. Validate token hash, verified actor/role, expiry, case/project ownership and unconsumed state.
3. Require proposal published, submitted hash/version equal stored values, source evidence version unchanged, active baseline unchanged and no other accepted change for the project.
4. Validate selected option against immutable stored options; ignore submitted prices, recipient addresses and issue URLs.
5. Insert one decision; mark token consumed; transition proposal/case; create the accepted-pending revision and action outbox in the same transaction.
6. Increment project lock version. Commit before external calls.
7. A repeated identical submission returns the existing receipt; a conflicting decision returns 409. No additional actions are inserted.

A token issued to a client cannot authorize manager publication. Manager publication uses the same locking and version checks. Database foreign keys alone do not prove cross-project consistency; routines must join all records through the configured project.

## External preflight
Fetch actual task and scope state before execution. Approval binds expected fingerprints. If fields to be changed differ from reviewed values, block and re-review; preserve human edits. Serialize project mutations with a durable project execution lease. Do not hold a database transaction open across an API call. Some providers lack conditional writes, so a read/write race remains: minimize the window, read back, and document this limitation.

## Worker claim
Claim pending actions with a single UPDATE/SELECT FOR UPDATE SKIP LOCKED routine, lease owner and expiry. Key = project/case/proposal-version/action-kind/resource. Use UNIQUE on this business key, never n8n execution ID. Lease expiry is not proof the provider write failed.

## Sensitive data
Do not store credential values, raw OTPs or bearer tokens in business tables. Hash tokens; keep minimal excerpts rather than entire inboxes. All times are UTC in storage; display Asia/Karachi or the configured project zone. Proposed retention: 30 days raw evidence, 90 days failed execution metadata, agreement records according to agency policy; confirm before production.
