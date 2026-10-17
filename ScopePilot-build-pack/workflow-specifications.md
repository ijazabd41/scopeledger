# n8n workflow specifications

Names below are logical workflow/node names; verify available node names and parameters against the pinned n8n release. Build and export real workflow JSON only after configuration. No fictional exported workflow is included.

## Shared envelope
Every internal call carries case_id, project_id, correlation_id, expected_case_version and caller_role derived from the authenticated workflow context. Never trust these fields from an external request without lookup. Every workflow writes a safe audit event and error code.

## WF00 — Project onboarding
Manager-authenticated Form/Webhook → validate allowlisted repo/folder and client address → credential smoke reads → fetch original scope → extract normalized deliverables → manager verifies mapping → create initial scope version → activate project. Block intake until baseline and GitHub links are confirmed. Input includes display name, configured resource IDs and decision-maker email, not credentials.

## WF01 — Email intake
Gmail Trigger (label designated messages, poll supported interval) → fetch full selected message → normalize plain text/MIME and size limits → deduplicate via mailbox+message ID → deterministic project resolution → insert case → call WF02. Unknown sender, forwarded identity ambiguity or multiple matching projects → blocked routing queue. Do not ingest the whole inbox. Sender address is routing evidence, not approval authentication.

## WF02 — Investigate
Load configured project and active baseline → retrieve current source revisions and GitHub issue fields → persist evidence snapshot/version → AI Agent → structured parser/JSON Schema validation → deterministic reference checks → persist recommendation → create manager review notification. Agent can retrieve more evidence via WF09; at most 8 tool calls and 2 model attempts, 90-second investigation budget. Budget exceeded → manager review with partial evidence, not guessed output. No provider writes.

## WF03 — Manager decision
GET review page displays sanitized evidence and options after verification. POST decision uses token + current version. Branches:
- clarify: manager approves exact question and recipient; enqueue mail, set clarification_required.
- decline: record reason, enqueue approved response, set rejected.
- covered: manager confirms no baseline change; optionally authorizes one defined task action using same action ledger.
- publish options: require confirmed effort, prices, currency, dates and issue mapping; persist new immutable proposal, record publication decision, enqueue client invitation, set awaiting_client.
Changes to options invalidate existing client tokens. Manager cannot silently accept on behalf of client.

## WF04 — Client verification and decision
Use GET for view, POST /auth/request-code, POST /auth/verify-code, POST /decision. Paths are logical route contracts under n8n production webhooks, not claims of an implemented service. Send OTP only to configured client address; never to request-supplied address. After verification, issue short-lived review token. POST decision runs approval transaction. Return 202 with receipt for acceptance pending sync; reject/clarify transitions do not execute changes. Email replies are evidence only.

## WF05 — Execution dispatcher
Scheduled trigger or internal authenticated dispatch → atomically claim accepted case → preflight evidence fingerprints → acquire project lease → prepare accepted scope draft → execute allowlisted GitHub actions sequentially → publish/fill new scope document → verify all mandatory effects → activate new scope revision transactionally → enqueue completion notice → completed. If a verified effect exists and another fails: partially_applied; baseline not activated. Do not send success mail until complete.

A new GitHub issue includes a unique ScopePilot action marker. For swaps, existing issue is preserved; add a superseded label/comment and close only when the approved plan specifically authorizes closure. Never delete issues. Reconcile uncertain create requests before retry.

## WF06 — Reminders and expiry
Schedule every 5 minutes → query due unpublished/sent reviews → stable reminder key per stage/interval → enqueue reminder. Suggested reminders 24h and 48h, proposal expiry 72h (configurable). Timeout expires the decision and alerts manager. Never convert expiry to acceptance. Changes accepted before expiry may continue syncing; the original decision remains valid unless preflight fails.

## WF07 — Notification outbox
Claim pending notification → render approved template → send via Gmail → store provider ID → verified sent. Unknown send outcome → reconcile Sent by unique Message-ID where supported; otherwise manual review, not blind resend. Delivery/sent is not proof recipient read the message. Failed delivery is shown separately from accepted agreement state.

## WF08 — Error and reconciliation
Error Trigger catches unhandled workflow failures → identify correlated case/action → log redacted error → notify operator. Scheduled scan also finds stalled/unknown actions in case Error Trigger itself failed. Read provider state and classify effect as verified, absent-and-safe-to-retry, or unresolved. Resume only safe action keys. Never rerun the whole case automatically.

## WF09 — MCP evidence tools
MCP Server Trigger (authenticated) → tool subworkflows for baseline, evidence and issue reads. Main AI Agent connects through MCP Client Tool to this endpoint so MCP is actually exercised. Per-case credentials bind tool access to the server-side investigation context. If the chosen n8n version cannot propagate a trustworthy context, bind the MVP tools to the one configured demo project; do not claim arbitrary multi-project isolation. No write or approval tool is exposed.

## WF10 — Operator view
Manager-authenticated form/webhook → case list/detail, source links, proposal version, safe action receipts, error status and next permitted recovery action. Recovery POST requires fresh manager authorization for changed plans. Never expose n8n editor or credential pages to client accounts.
