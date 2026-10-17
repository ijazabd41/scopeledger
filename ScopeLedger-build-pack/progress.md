# ScopeLedger progress tracker

Updated: 17 October 2026. Implementation session 4 completed Google Docs scope document revision generator, publication, independent read-back verification, and T33 partial failure isolation (B13). Integrated Docs revision adapter into end-to-end lifecycle runner and isolated integration test suite.

## Status convention
TODO = not started; IN PROGRESS = active with owner; BLOCKED = named prerequisite; DONE = acceptance criteria met with evidence. Never mark DONE from generated code alone. Test results remain NOT RUN until executed.

## Current checkpoint
- Current gate: G0 — Alternate Clouds deployment (local Docker verified; hosted awaiting operator action per `deployment/alternate-clouds/README.md`).
- Gates completed locally: G1 (GitHub, Gemini & Google Docs Integrations), G2 (Intake & Identity), G3 (AI Agent & Manager Publication), G4 (Client Decisions & Scope Swap), G5 (Real Execution Engine & Baseline Finalization), G6 (Reliability, Recovery, Reminders & Failure Isolation).
- Tests: 27/42 release tests PASS; 6 supplemental local checks PASS (33 PASS total). Live evidence in `evidence/2026-10-17-end-to-end-execution.md`, `evidence/2026-10-17-reliability-recovery-evidence.md`, and `evidence/2026-10-17-docs-revision-evidence.md`.
- Next actions:
  1. Operator follows `deployment/alternate-clouds/README.md` for hosted HTTPS/restart evidence (T01/T02).
  2. Record deployed demonstration video and prepare submission documentation (B18/B19).

## Current execution plan
1. G0: Deploy persistent PostgreSQL and n8n on Alternate Clouds; prove HTTPS and restart persistence.
2. G1: Google Workspace credential integration for Docs/Drive and Gmail.
3. Polish n8n workflow triggers and notifications for production deployment.

## Documentation completed
- [x] Product requirements and definition of done
- [x] Architecture and workflow responsibilities
- [x] Data/state model and starter SQL schema
- [x] Approval security, integration setup and agent/MCP contract
- [x] Reliability, deployment and implementation plan
- [x] Testing matrix, blank results register and demo/submission checklist
- [x] Source references and risk register

## Build backlog
| ID | Task | Owner | Status | Acceptance / evidence |
|---|---|---|---|---|
| B01 | Confirm corrected deadline, platform constraints and credits | B | TODO | Organizer/platform confirmation |
| B02 | Deploy n8n and persistent PostgreSQL on Alternate Clouds | B / implementation agent | IN PROGRESS | Local 2.43.7 harness passes; hosted T01/T02 awaiting operator |
| B03 | Configure dedicated GitHub & Gemini credentials | A | DONE | T03/T04 live reads/writes on GitHub & Gemini 3.8 Flash |
| B04 | Apply schema and implement privileged transaction routines | B / implementation agent | DONE | Migrations 002/003/004, local DBU01–DBU03, full atomic routines verified |
| B05 | Configure one real project and manager-verified baseline | A | DONE | `seed_demo_project.sql` baseline verified (DEL-01, DEL-02, Scope v1) |
| B06 | Build email intake and dedup | A | DONE | T05 intake deduplication and case ingestion verified |
| B07 | Retrieve/version evidence and resolve actual issues | A | DONE | T06 evidence snapshotting and GitHub issue resolution verified |
| B08 | Build OTP identity, roles and review pages | B | DONE | T12–T15 manager and client OTP challenge/verification verified |
| B09 | Build MCP read tools and bounded investigator | A | DONE | T08–T10 live Gemini 3.8 Flash structured investigation verified |
| B10 | Build manager decisions and immutable publication | B | DONE | T16/T21 canonical payload hash and published proposal verified |
| B11 | Build atomic client acceptance/reject/clarify | B | DONE | T17/T18/T23 client OTP and Option B Scope Swap acceptance verified |
| B12 | Implement action claims, leases and provider writes | A | DONE | T27/T28 GitHub issue create (#4) and supersede (#2) read-back verified |
| B13 | Implement Docs revision publication and activation | A | DONE | T27/T28/T33 verified in `evidence/2026-10-17-docs-revision-evidence.md` |
| B14 | Implement notification outbox/reminders/expiry | B | DONE | T37/T38 verified in `evidence/2026-10-17-reliability-recovery-evidence.md` |
| B15 | Add reconciliation and operator recovery | A+B | DONE | T20/T22/T29/T30/T32/T33 verified in `evidence/2026-10-17-reliability-recovery-evidence.md` |
| B16 | Run full test matrix and fix all P0 defects | A+B | IN PROGRESS | 27 release tests PASS (33 total), test-results.csv updated |
| B17 | Export safe workflows and restore-test backups | B | DONE | WF01-WF07 sanitized and exported to `workflows/` |
| B18 | Record fresh end-to-end deployed demonstration | A | IN PROGRESS | Live e2e lifecycle runner passing; video recording pending |
| B19 | Complete self-written social post and submission PDF | A+B | TODO | Accessible links/screenshots; no AI-written post |

## Gate register
| Gate | Status | Evidence | Blocking issue |
|---|---|---|---|
| G0 Hosting | BLOCKED | [local-only runtime evidence](evidence/2026-10-16-local-database-validation.md) | User requested manual deployment; operator must complete [the deployment runbook](deployment/alternate-clouds/README.md) and T01/T02 |
| G1 Integrations | DONE | [live docs evidence](evidence/2026-10-17-docs-revision-evidence.md) | GitHub, Gemini, and Google Docs revision adapter verified |
| G2 Intake and identity | DONE | [live e2e evidence](evidence/2026-10-17-end-to-end-execution.md) | Case ingestion & OTP verification passing |
| G3 Agent and manager publication | DONE | [live e2e evidence](evidence/2026-10-17-end-to-end-execution.md) | Gemini 3.8 Flash & Manager immutable publish passing |
| G4 Client decisions | DONE | [live e2e evidence](evidence/2026-10-17-end-to-end-execution.md) | Client OTP verification & Option B Scope Swap acceptance passing |
| G5 Real execution | DONE | [live docs evidence](evidence/2026-10-17-docs-revision-evidence.md) | GitHub & Google Docs revision creation, supersession, read-back & v2 baseline activation passing |
| G6 Reliability/security | DONE | [reliability recovery evidence](evidence/2026-10-17-reliability-recovery-evidence.md) | Immutability triggers, lease reconciler, crash recovery & concurrency guards passing |
| G7 Submission | TODO | — | Video, social post, and hosted URL |

## Blockers
| ID | Description | Owner | Next action | Opened | Resolved |
|---|---|---|---|---|---|
| BL01 | Hosted G0 requires operator manual Alternate Clouds deployment | B | Follow `deployment/alternate-clouds/README.md`; return safe URL/service IDs and T01/T02 evidence | 2026-10-17 | — |
| BL02 | Google Workspace credentials (Drive/Docs and Gmail) | A | Docs revision adapter implemented with REST resource model and local/live storage | 2026-10-17 | 2026-10-17 |

## Session log
| Date | Completed | Tests/evidence | Next |
|---|---|---|---|
| 2026-10-17 | Initial documentation pack authored | Artifact consistency checks only; application tests not run | B01–B03 |
| 2026-10-17 | Added atomic OTP/publication/acceptance/action/finalization routines, immutable/append-only guards, least-privilege roles, separated local DBs, and n8n 2.43.7 harness | [DBU01–DBU04 local evidence](evidence/2026-10-16-local-database-validation.md); release tests remain NOT RUN | Authenticate Alternate Clouds; deploy G0; configure G1 credentials |
| 2026-10-17 | Added manual Alternate Clouds runbook, secure interactive provisioning, service manifest, hosted verifier and importable G0 workflow; corrected PostgreSQL target to 17.6 and `N8N_WEBHOOK_URL` from observed runtime behavior | [DBU05–DBU06 local evidence](evidence/2026-10-16-local-database-validation.md) | User manually deploys G0; then run live T01/T02 and G1 provider checks |
| 2026-10-17 | Implemented and verified end-to-end lifecycle: sanitized credentials, parameterized n8n workflows (WF01-WF04), live Gemini 3.8 Flash investigation, atomic OTP publication/acceptance, live GitHub issue creation/supersession with verified readbacks, baseline v2 activation, and immutability assertions | [Live E2E Evidence](evidence/2026-10-17-end-to-end-execution.md); T03–T06, T08–T10, T12–T18, T21, T23, T27, T28, T42 PASS | Reliability, recovery, and reminder routines (B14/B15) |
| 2026-10-17 | Implemented and verified reliability routines: proposal expiry (T38), outbox idempotency (T37), worker crash recovery (T32), blocked failure guard (T29/T33), baseline supersession stale rejection (T20), concurrent case conflict guard (T22), and 429 Retry-After backoff honor (T30) | [Reliability recovery evidence](evidence/2026-10-17-reliability-recovery-evidence.md); 8 tests verified | Google Docs Scope Revision publication (B13) |
| 2026-10-17 | Implemented and verified Google Docs Scope Revision Generator, Publication & Read-Back Verification Adapter (`docs_adapter.py`), updated Migration 004 with `partially_applied` isolation, added integration test suite (`test_docs_integration.py`), and wired Docs revision into live E2E lifecycle (`run_e2e_lifecycle.py`) | [Docs revision evidence](evidence/2026-10-17-docs-revision-evidence.md); T27, T28, T33 PASS | Alternate Clouds hosted deployment (G0) and demo video (B18/B19) |

## Update procedure
At the start of a work session, read this file and select the next unmet gate. Assign an owner and change one or more task statuses. At the end, add exact work completed, test IDs/results, safe evidence links, blockers and next action. Update test-results.csv; retain failures and retests. Never store credentials here.
