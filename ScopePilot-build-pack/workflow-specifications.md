# ScopePilot n8n workflow specifications

This document specifies the actual node-level responsibilities, connections, and contracts implemented across the 13 exported workflow JSON files in `workflows/`. Every workflow is exported inactive with placeholder credential IDs.

## Shared envelope
Every internal call carries `case_id`, `project_id`, `correlation_id`, `expected_case_version` and `caller_role` derived from the authenticated workflow context. External requests are authenticated via header or bearer tokens before any database operation. Every workflow logs safe audit events in PostgreSQL.

---

## WF01 & WF01A — Email intake and autonomous AI investigation

### WF01A — Gmail Trigger Adapter
- **Trigger**: Gmail Trigger node polling dedicated inbox with query `label:ScopePilot/Intake`.
- **Logic**: Filters messages from client addresses, extracts `message_id`, `thread_id`, `from`, `subject`, and plain body.
- **Dispatch**: Forwards verified email payload to `WF-01` over internal HTTP webhook with shared header authentication (`scopeledger-internal-webhook`).

### WF01 — Intake, AI Agent, and MCP Investigation
1. **Authenticated Intake Webhook**: Receives email payload via `scopeledger-internal-intake` with header authentication.
2. **Route And Deduplicate Email**: Calls PostgreSQL `scopeledger.ingest_email_case()`. Deduplicates by `mailbox_id + message_id`. Unknown senders or duplicate messages are halted.
3. **Fetch Active Scope Metadata**: Queries project details, active scope baseline, repo owner/name, drive folder, and active deliverable IDs.
4. **Read Active Google Doc**: Fetches active scope document text via Google Docs API. If unreadable, flags `doc_missing: true` with error isolation (`continueRegularOutput`).
5. **Read GitHub Issues**: Fetches open repository issues via GitHub API (excluding PRs).
6. **Assemble Investigation Prompt & Evidence**: Formats case facts, active scope deliverables, and initial evidence snapshots into the agent prompt payload.
7. **AI Agent - Scope Investigator (`@n8n/n8n-nodes-langchain.agent`)**:
   - Loops through reasoning and tool calls up to **8 iterations**, with **2 model retry attempts** and a **90-second timeout budget**.
   - Connected sub-nodes:
     - `Gemini 3.8 Flash Chat Model` (`@n8n/n8n-nodes-langchain.lmChatGoogleGemini`): Reasoning model (`models/gemini-3.8-flash`, temperature 0.1).
     - `ScopePilot MCP Client Tool` (`@n8n/n8n-nodes-langchain.mcpClientTool`): Connects to `WF-09` MCP server to query `Project_Context` and `Case_Evidence`.
     - `Structured Output Parser` (`@n8n/n8n-nodes-langchain.outputParserStructured`): Enforces `agent-output.schema.json`.
8. **Validate Grounding & Evidence Citations**:
   - Enforces strict classifications: `covered`, `additional`, or `ambiguous`.
   - Validates referenced deliverable IDs against active baseline deliverables.
   - Validates GitHub issue references against actual open issues.
   - Enforces `doc_missing` rule: forces `ambiguous` with confidence `<= 0.5`.
   - Fallback escalation: if the agent times out or returns malformed output, generates a deterministic `ambiguous` escalation for human manager review.
9. **Persist Investigation And Evidence**: Calls `scopeledger.record_investigation_result()` to store the recommendation, snapshot evidence, and advance case to `awaiting_manager`.
10. **Return Investigation Receipt**: Returns HTTP 202 receipt with `case_id` and `evidence_version`.

---

## WF02 & WF02B — Manager proposal publication

### WF02 — Manager Request Challenge
- Authenticates manager review session.
- Fetches case investigation and evidence.
- Generates 6-digit cryptographic OTP bound to the exact case `row_version`.
- Dispatches OTP to configured manager email via outbox.

### WF02B — Manager Confirm Publish
- Receives manager decision payload, options, pricing, and entered OTP.
- Calls `scopeledger.confirm_manager_challenge()` and `scopeledger.publish_proposal()`.
- Validates OTP and verifies that the case `row_version` has not changed since review.
- Persists immutable proposal, enqueues client invitation notification, and advances case to `awaiting_client`.

---

## WF03 & WF03B — Client decision & verification

### WF03 — Client Request Challenge
- Client accesses public review form.
- Generates 6-digit OTP sent strictly to the configured project client email.

### WF03B — Client Confirm Decision
- Receives selected proposal option, rationale, and client OTP.
- Calls `scopeledger.confirm_client_challenge()` and `scopeledger.decide_proposal()`.
- Rejects stale proposals, expired proposals, or concurrent conflicting cases.
- Enqueues provider actions in `actions` table and advances case to `accepted_pending_sync`.

---

## WF04 — Execution engine

- Scheduled/webhook triggered worker.
- Acquires project execution lease.
- Claims pending actions atomically via `scopeledger.claim_next_action()`.
- Sequential provider branches:
  - **GitHub Issue Supersede**: Updates superseded deliverable issues with `scopeledger:superseded` label and comments.
  - **Google Docs Revision Create**: Creates, populates, and reads back the new scope document revision with cryptographic verification markers.
  - **GitHub Issue Create**: Creates new tasks with labels, deliverables mapping, and tracking markers.
- Records verification via `scopeledger.record_action_result()`.
- Once all actions verify, calls `scopeledger.finalize_case()` to activate Scope Version 2 and complete the case.
- If any action fails, isolates case in `partially_applied` without corrupting baseline.

---

## WF05 — Reminders and expiry

- Runs every 5 minutes on schedule.
- Queries unpublished proposals or pending client reviews.
- Generates idempotent reminder notifications.
- Automatically transitions proposals past the expiry threshold to `expired` status.

---

## WF06 — Notification outbox

- Runs on schedule.
- Atomically claims pending outbox notifications (`scopeledger.claim_notification()`).
- Dispatches emails via Gmail API with stable Message-ID threading.
- Records delivery status and provider message ID.

---

## WF07 — Stalled lease & crash reconciliation

- Runs every 5 minutes on schedule.
- Calls `scopeledger.reconcile_stalled_actions()`.
- Detects actions with expired worker leases and safely requeues them up to max attempts.
- Marks persistently failing actions as `blocked` and updates case to `partially_applied` or `blocked`.
- Releases abandoned project execution leases.

---

## WF08 — Authenticated MCP read API

- Internal authenticated webhooks protected by `scopeledger-internal-webhook`.
- Exposes two read endpoints:
  - `GET /webhook/scopeledger-mcp-project-context`: Returns active scope baseline, repo info, and drive folder.
  - `GET /webhook/scopeledger-mcp-case-evidence`: Returns case evidence snapshots filtered by project boundary.

---

## WF09 — Authenticated read-only MCP server

- Trigger: `@n8n/n8n-nodes-langchain.mcpTrigger` at `/mcp/scopeledger-mcp` with `httpBearerAuth`.
- Exposes two tools via `@n8n/n8n-nodes-langchain.toolHttpRequest`:
  - `Project_Context`: Binds to WF-08 project context endpoint.
  - `Case_Evidence`: Binds to WF-08 case evidence endpoint.
- Provides read-only evidence querying capabilities to the AI Agent in WF-01.

---

## WF-G0 — Health and verification

- Static health check webhook at `/webhook/scopeledger-health-v1`.
- Emits verification receipt proving n8n uptime and readiness on Alternate Clouds.
