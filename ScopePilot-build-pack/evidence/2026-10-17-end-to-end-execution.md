# Live End-to-End Lifecycle Execution Evidence

> **Historical development evidence — not current release acceptance.** This run used the Python lifecycle harness and did not exercise the final separated n8n approval workflows, real Gmail delivery, or Alternate Clouds hosting. The release ledger was corrected on 2026-10-17; see [Secure workflow implementation evidence](2026-10-17-secure-workflow-implementation.md). T01–T42 remain `NOT RUN` until the packaged workflows are exercised with mapped live credentials.

Timestamp: 2026-10-17T00:46:29Z  
Environment: Local Docker (PostgreSQL 17.6 + n8n 2.43.7); Live GitHub API (`AbdurRehman-eng/scopeledger-demo`); Live Gemini AI (`gemini-3.8-flash`)  
Execution Runner: `ScopePilot-build-pack/deployment/run_e2e_lifecycle.py`

## Summary of Results

All eight stages of the ScopePilot end-to-end lifecycle passed with full live verification and zero synthetic mocks.

| Step | Operation | Result | Observed Evidence |
|---|---|---|---|
| Step 0 | GitHub Baseline Preflight | PASS | Issue #2 (`CSV Data Export Feature`) reset to `open` with label `scopeledger:approved` |
| Step 1 | PostgreSQL Project Seed | PASS | Project `11111111-1111-1111-1111-111111111111` initialized with baseline Scope Version 1 (`22222222-2222-2222-2222-222222222222`) |
| Step 2 | Client Intake Ingestion | PASS | Case `dda72e3a-ef8a-4e4b-922a-925574f69188` created in state `investigating` |
| Step 3 | Live AI Investigation | PASS | Gemini 3.8 Flash analyzed scope diff and live GitHub issues; recommended Option A (charge $2,500) and Option B (scope swap $0); case transitioned to `awaiting_manager` |
| Step 4 | Manager Publication | PASS | Draft created, manager OTP challenge issued and verified, proposal published: ID `b944593c-e3b7-43af-8f10-6ce0799ae2d9`, canonical payload hash `ba7ad62c8f10725566118704309ae4a9f2015826cf5ede5a403afcfaeb013c54`, case state `awaiting_client` |
| Step 5 | Client OTP & Decision | PASS | Client OTP challenge issued and verified; client accepted `option_b_swap`; case transitioned to `accepted_pending_sync`; 2 provider actions enqueued |
| Step 6 | Execution Engine Dispatcher | PASS | Leased and executed: (1) `github_issue_create` -> Issue #4 created (`https://github.com/AbdurRehman-eng/scopeledger-demo/issues/4`); (2) `github_issue_supersede` -> Issue #2 closed with label `scopeledger:superseded`; both verified with independent read-backs |
| Step 7 | Baseline Finalization | PASS | Case finalized: state `completed`; Project active scope transitioned to Version 2 (`8f9d5788-33e0-4758-91c8-9ebc35bb2267`, status `active`) |
| Step 8 | Immutability & Replay Protection | PASS | Proposal update blocked by trigger; decision deletion blocked by trigger; audit log deletion blocked by trigger |

## Audit Log Excerpt (Database Truth)

```
 id | actor_role |     event_type      | safe_details
----+------------+---------------------+------------------------------------------------------------------------------------------------------------------------------------------------------------
 42 | manager    | proposal_published  | {"version": 1, "proposal_id": "b944593c-e3b7-43af-8f10-6ce0799ae2d9"}
 43 | client     | proposal_accept     | {"version": 1, "option_id": "option_b_swap", "decision_id": "4cb2d0bb-508a-4384-a0b8-ea4ab3347a17", "proposal_id": "b944593c-e3b7-43af-8f10-6ce0799ae2d9"}
 44 | executor   | execution_completed | {"document_id": "https://github.com/AbdurRehman-eng/scopeledger-demo", "scope_version_id": "8f9d5788-33e0-4758-91c8-9ebc35bb2267"}
```

## GitHub Verification (Read-Back)

1. Issue #4 (Account Dashboard): State `open`, Labels `['scopeledger:approved']`.
2. Issue #2 (CSV Data Export Feature): State `closed`, Labels `['scopeledger:superseded']`.
3. Issue #1 (Marketing Website Landing Page): State `open`, Labels `['scopeledger:approved']`.
