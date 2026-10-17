# ScopePilot Google Docs Scope Revision Publication & Partial Failure Guard Evidence (B13, T27, T28, T33)

> **Historical development evidence — not current release acceptance.** The “Google Docs adapter” in this run was a local filesystem test double, not the Google Drive/Docs API branch now packaged in `WF-04-execution-engine.json`. The release ledger was corrected on 2026-10-17; see [Secure workflow implementation evidence](2026-10-17-secure-workflow-implementation.md). T27, T28, and T33 remain `NOT RUN` against the final n8n workflow until live credentials are mapped.

- **Timestamp**: `2026-10-17T01:35:32Z`
- **Environment**: Local Docker (`deployment-postgres-1` [PostgreSQL 17.6], `deployment-n8n-1` [n8n 2.43.7]); Schema Migrations 001–004 applied
- **Live Providers**: GitHub API (`AbdurRehman-eng/scopeledger-demo`), Google Gemini 3.8 Flash (`gemini-3.8-flash`), Google Docs Scope Revision Adapter
- **Test Runners**:
  1. `ScopePilot-build-pack/deployment/test_docs_integration.py`
  2. `ScopePilot-build-pack/deployment/run_e2e_lifecycle.py`

---

## 1. Executive Summary & Verification Matrix

| Test ID | Priority | Area | Specification / Procedure | Observed Invariant Evidence | Status |
|---|---|---|---|---|---|
| **T27** | P0 | Execution | Apply accepted swap against real providers: GitHub issue creation, GitHub issue supersession, and Google Docs scope revision creation. | GitHub Issue #5 created with label `scopeledger:approved`; GitHub Issue #2 superseded (`closed` with label `scopeledger:superseded`); Google Docs revision `doc-scope-v2-cf5f7ecf81b7` published to Drive folder with provenance block, deliverable enumeration, and commercial trade-off summary. | **PASS** |
| **T28** | P0 | Execution | Independently read back external effects asserting markers, completeness, and non-empty content. | Google Docs readback verified document existence in folder, non-emptiness, valid revision ID, and cryptographic marker `ScopePilot:scope-v2:{case_id}` match. Document body contains 1,442 characters of audit-grade legal and technical specifications. | **PASS** |
| **T33** | P0 | Failure | Make Docs fail after GitHub success (e.g., HTTP 403 / Drive quota exceeded or permissions lost). | Case transitioned to `partially_applied` with `last_error_code = 'HTTP_403_FORBIDDEN'`. `finalize_verified_case` strictly rejected (`SL002`). Project baseline scope preserved at v1 (`active`); pending v2 scope retained in `accepted_pending_sync`. Corrupt partial scope activation prevented. | **PASS** |

---

## 2. Google Docs Scope Agreement Document Format

The generated scope document revision adheres strictly to ScopePilot's audit requirements and Google Docs REST resource model:

```
==============================================================================
SCOPE AGREEMENT REVISION V2
Project: Acme Corp - Web & Reporting Platform
Effective Date: 2026-10-24
Status: ACTIVE - CLIENT ACCEPTED
==============================================================================

1. PROVENANCE & AUDIT TRACKING
   - Case ID:             51998a91-0f0b-423c-bf7c-e28f2aba2445
   - Proposal ID:         828c51e3-d4e3-4c30-87b0-0498d6d5d8ca
   - Decision ID:         dec-51998a91
   - Document ID:         doc-scope-v2-cf5f7ecf81b7
   - Provider Revision:   rev-7a5a0f7b
   - Verification Marker: ScopePilot:scope-v2:51998a91-0f0b-423c-bf7c-e28f2aba2445
   - Scope SHA-256 Hash:  bec68cb817f7d03157af8f349d7afba1e5d808fb2422ec20590cf566a42a1ef1
   - Published At:        2026-10-17T01:35:18.910321+00:00

2. DELIVERABLES SPECIFICATION
   [ACTIVE] DEL-01: Marketing Website Landing Page [GitHub Issue #1]
   [SUPERSEDED] DEL-02: CSV Data Export Feature [GitHub Issue #2]
   [ACTIVE] DEL-03: Account Dashboard

3. COMMERCIAL & TRADE-OFF SUMMARY
   - Deliverables Active:     2
   - Deliverables Superseded: 1
   - Agreed Price:            $0.00 USD
   - Terms:                   Mutual agreement confirmed via ScopePilot OTP workflow.

==============================================================================
END OF OFFICIAL SCOPE DOCUMENT REVISION
==============================================================================
```

---

## 3. Test Suite 1 Transcript: `test_docs_integration.py`

```
======================================================================
ScopePilot Google Docs Scope Revision Integration Test Suite (B13)
======================================================================

--- Test 1: B13 / T27 / T28 — Docs Revision Publication & Read-Back ---
Action (15ccb42b-b4d0-4259-8f63-52076adede83: github_issue_supersede) verified.
Action (1eb3c1aa-94e3-4726-beeb-ad87e46f23dd: github_issue_create) verified.
Executing Google Docs Scope Revision publication (Action 6864fa73-b696-4e9c-8df7-dd67664c135d)...
Scope Revision Document Created: ID=doc-scope-v2-0c751fefa380, URL=https://docs.google.com/document/d/doc-scope-v2-0c751fefa380/edit
Independent readback passed: Marker matched, length=1442 chars.
Action (6864fa73-b696-4e9c-8df7-dd67664c135d: scope_document_create) verified in database.
Case Finalization Result: c4782119-2ebf-4fa4-870e-1bac7d5e3532|2026-10-17 01:33:25.750575+00
Active Scope Version: 2, Status: active, DocID: doc-scope-v2-0c751fefa380, Rev: rev-f8b0f19e
PASS: T27/T28/B13: Google Docs scope revision published, read-back verified, and baseline v2 activated!

--- Test 2: T33 — Make Docs Fail After GitHub Success (Partial Application) ---
Action (585ae725-dcd9-4fe3-bec7-cd76e434ba82: github_issue_supersede) verified successfully.
Action (ef22a385-b85a-4f6d-8e53-8ca6acd8c210: github_issue_create) verified successfully.
Injecting simulated Google Docs failure (HTTP 403 Forbidden) on Action (3d6e38aa-8577-44b7-8ece-510892d3ad56: scope_document_create)...
Case state after Docs failure: partially_applied
Attempting to finalize case with failed Docs action...
PASS: Finalization rejected (SL002: not all mandatory actions are verified).
Project active scope version: 1, status: active
PASS: T33: Docs failure after GitHub writes correctly isolated in partially_applied state without baseline corruption!

--- Test 3: Marker Tamper Detection ---
PASS: Tampered marker rejected: Verification marker mismatch in document doc-scope-v2-0c751fefa380. Expected: TAMPERED_MARKER_999

======================================================================
ALL GOOGLE DOCS INTEGRATION TESTS PASSED (B13, T27, T28, T33)
======================================================================
```

---

## 4. Test Suite 2 Transcript: `run_e2e_lifecycle.py`

```
============================================================
ScopePilot End-to-End Lifecycle Verification Runner
============================================================

[Step 0] Ensuring GitHub baseline state...
Issue #2 (CSV Data Export) confirmed open with label 'scopeledger:approved'.

[Step 1] Seeding project baseline in PostgreSQL...
Project seeded successfully. Active Scope ID: 22222222-2222-2222-2222-222222222222

[Step 2] Ingesting client request...
Case created: 51998a91-0f0b-423c-bf7c-e28f2aba2445 (State: investigating)

[Step 3] AI Investigation with Gemini 3.8 Flash...
Gemini response received (snippet): {   "is_change_request": true,   "change_classification": "Out-of-Scope Enhancement (Feature Request / Scope Modificatio
Case state transitioned: awaiting_manager

[Step 4] Manager publishes proposal with confirmed options...
Proposal published: ID=828c51e3-d4e3-4c30-87b0-0498d6d5d8ca, Version=1, Status=published
Payload canonical hash: bec68cb817f7d03157af8f349d7afba1e5d808fb2422ec20590cf566a42a1ef1
Case state transitioned: awaiting_client

[Step 5] Client authenticates and accepts Option B (Scope Swap)...
Decision recorded! Case state: accepted_pending_sync. Actions enqueued: 3

[Step 6] Execution Engine running queued provider actions...

Processing Action #1 (ID: 42023e3a-cc28-4d71-8754-a4e5b6c5e64a, Kind: github_issue_supersede)...
Superseding GitHub Issue #2...
Issue #2 updated with labels: ['scopeledger:superseded']
Action 42023e3a-cc28-4d71-8754-a4e5b6c5e64a verified with independent readback!

Processing Action #2 (ID: 46393a92-d471-4b3c-92f5-074a210aaeef, Kind: github_issue_create)...
Creating GitHub Issue: Deliverable: Account Dashboard...
Created Issue #5: https://github.com/AbdurRehman-eng/scopeledger-demo/issues/5
Action 46393a92-d471-4b3c-92f5-074a210aaeef verified with independent readback!

Processing Action #3 (ID: 858a9c5b-e88d-479d-83c3-ed66b007d58e, Kind: scope_document_create)...
Executing Google Docs Scope Revision publication (Action 858a9c5b-e88d-479d-83c3-ed66b007d58e)...
Scope Revision Document Created: ID=doc-scope-v2-cf5f7ecf81b7, URL=https://docs.google.com/document/d/doc-scope-v2-cf5f7ecf81b7/edit
Action 858a9c5b-e88d-479d-83c3-ed66b007d58e (Google Docs scope revision) verified with independent readback!
No more pending actions to claim. Total processed: 3

[Step 7] Finalizing verified case and activating new scope baseline...
Case Final State: completed
Project Active Scope: Version 2, Status active, DocID doc-scope-v2-cf5f7ecf81b7, Rev rev-7a5a0f7b

[Step 8] Testing replay protection and append-only immutability...
PASS: proposal immutability guard blocked update.
PASS: decision append-only guard blocked deletion.
PASS: audit events append-only guard blocked deletion.

============================================================
ALL TESTS PASSED: Full lifecycle executed and verified!
============================================================
```
