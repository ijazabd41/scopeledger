# ScopePilot progress tracker

Updated: 17 October 2026. Implementation session 5 corrected overstated release evidence, added secure workflow-facing database boundaries, separated OTP request/confirmation, implemented Gmail intake and scheduled n8n workers, added real GitHub/Google Docs provider branches, and import-tested all workflow exports on n8n 2.43.7.

## Status convention
TODO = not started; IN PROGRESS = active with owner; BLOCKED = named prerequisite; DONE = acceptance criteria met with evidence. Never mark DONE from generated code alone. Test results remain NOT RUN until executed.

## Current checkpoint
- Current gate: G0 — Alternate Clouds deployment remains an operator action per `deployment/alternate-clouds/README.md`.
- Local implementation: migrations 002–005 and 13 secret-free workflow exports exist; database approval/intake boundaries and pinned-version workflow imports pass.
- Tests: 0/42 release tests PASS; 9 supplemental implementation checks PASS. Earlier Python/local-adapter evidence is retained but no longer counted as release acceptance; see `evidence/2026-10-17-secure-workflow-implementation.md`.
- Next actions:
  1. Operator follows `deployment/alternate-clouds/README.md` for hosted HTTPS/restart evidence (T01/T02).
  2. Map live credentials, publish the inspected workflows, and execute G1–G6 release tests through n8n.
  3. Record the deployed demonstration video and prepare submission documentation (B18/B19).

## Current execution plan
1. G0: Deploy persistent PostgreSQL and n8n on Alternate Clouds; prove HTTPS and restart persistence.
2. G1: Map and smoke-test Gmail, Google Drive/Docs, GitHub, Gemini, and MCP credentials.
3. Run release acceptance tests through deployed n8n workflows and correct defects.

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
| B03 | Configure dedicated GitHub & Gemini credentials | A | IN PROGRESS | Prior local calls recorded; deployed n8n credentials and current-workflow smoke tests pending |
| B04 | Apply schema and implement privileged transaction routines | B / implementation agent | DONE | Migrations 002/003/004, local DBU01–DBU03, full atomic routines verified |
| B05 | Configure one real project and manager-verified baseline | A | DONE | `seed_demo_project.sql` baseline verified (DEL-01, DEL-02, Scope v1) |
| B06 | Build email intake and dedup | A | IN PROGRESS | DBU08 passes; Gmail credential and T03–T05 live run pending |
| B07 | Retrieve/version evidence and resolve actual issues | A | IN PROGRESS | Workflow implemented; live Docs/GitHub T06/T07 pending |
| B08 | Build OTP identity, roles and review pages | B | IN PROGRESS | DBU07 passes; Gmail delivery and accessible review pages pending |
| B09 | Build MCP read tools and bounded investigator | A | IN PROGRESS | Authenticated read-only MCP workflow imports; deployed client trace T11 pending |
| B10 | Build manager decisions and immutable publication | B | IN PROGRESS | Secure request/confirm boundary implemented; live human T16/T21 pending |
| B11 | Build atomic client acceptance/reject/clarify | B | IN PROGRESS | Secure request/confirm boundary implemented; live branch/race tests pending |
| B12 | Implement action claims, leases and provider writes | A | IN PROGRESS | n8n branches implemented/imported; credentialed provider runs pending |
| B13 | Implement Docs revision publication and activation | A | IN PROGRESS | Real Drive/Docs API branch implemented; prior local adapter evidence invalidated for release acceptance |
| B14 | Implement notification outbox/reminders/expiry | B | IN PROGRESS | Scheduled Gmail outbox implemented; provider loss/reconciliation test pending |
| B15 | Add reconciliation and operator recovery | A+B | IN PROGRESS | DB routines and schedule implemented; ambiguous live-provider outcomes remain |
| B16 | Run full test matrix and fix all P0 defects | A+B | IN PROGRESS | 0/42 release tests PASS; 9 supplemental checks PASS |
| B17 | Export safe workflows and restore-test backups | B | IN PROGRESS | 13 inactive exports import on n8n 2.43.7; backup restore test pending |
| B18 | Record fresh end-to-end deployed demonstration | A | IN PROGRESS | Live e2e lifecycle runner passing; video recording pending |
| B19 | Complete self-written social post and submission PDF | A+B | TODO | Accessible links/screenshots; no AI-written post |

## Gate register
| Gate | Status | Evidence | Blocking issue |
|---|---|---|---|
| G0 Hosting | BLOCKED | [local-only runtime evidence](evidence/2026-10-16-local-database-validation.md) | User requested manual deployment; operator must complete [the deployment runbook](deployment/alternate-clouds/README.md) and T01/T02 |
| G1 Integrations | IN PROGRESS | [implementation evidence](evidence/2026-10-17-secure-workflow-implementation.md) | Live credential mapping, provider smoke tests, and MCP client trace pending |
| G2 Intake and identity | IN PROGRESS | [implementation evidence](evidence/2026-10-17-secure-workflow-implementation.md) | DB boundaries pass; Gmail delivery and UI acceptance pending |
| G3 Agent and manager publication | IN PROGRESS | [implementation evidence](evidence/2026-10-17-secure-workflow-implementation.md) | Workflow imported; live model/human flow pending |
| G4 Client decisions | IN PROGRESS | [implementation evidence](evidence/2026-10-17-secure-workflow-implementation.md) | Atomic DB flow passes; live client/race tests pending |
| G5 Real execution | IN PROGRESS | [implementation evidence](evidence/2026-10-17-secure-workflow-implementation.md) | Provider branches imported; real provider execution/read-back pending |
| G6 Reliability/security | IN PROGRESS | [local DB evidence](evidence/2026-10-17-reliability-recovery-evidence.md) | Database simulations pass; live failure, privacy, and restart tests pending |
| G7 Submission | TODO | — | Video, social post, and hosted URL |

## Blockers
| ID | Description | Owner | Next action | Opened | Resolved |
|---|---|---|---|---|---|
| BL01 | Hosted G0 requires operator manual Alternate Clouds deployment | B | Follow `deployment/alternate-clouds/README.md`; return safe URL/service IDs and T01/T02 evidence | 2026-10-17 | — |
| BL02 | Google Workspace credentials (Drive/Docs and Gmail) | A | Map dedicated OAuth credentials to the imported n8n workflows and run T03/T06/T27/T28/T37 | 2026-10-17 | — |

## Session log
| Date | Completed | Tests/evidence | Next |
|---|---|---|---|
| 2026-10-17 | Initial documentation pack authored | Artifact consistency checks only; application tests not run | B01–B03 |
| 2026-10-17 | Added atomic OTP/publication/acceptance/action/finalization routines, immutable/append-only guards, least-privilege roles, separated local DBs, and n8n 2.43.7 harness | [DBU01–DBU04 local evidence](evidence/2026-10-16-local-database-validation.md); release tests remain NOT RUN | Authenticate Alternate Clouds; deploy G0; configure G1 credentials |
| 2026-10-17 | Added manual Alternate Clouds runbook, secure interactive provisioning, service manifest, hosted verifier and importable G0 workflow; corrected PostgreSQL target to 17.6 and `N8N_WEBHOOK_URL` from observed runtime behavior | [DBU05–DBU06 local evidence](evidence/2026-10-16-local-database-validation.md) | User manually deploys G0; then run live T01/T02 and G1 provider checks |
| 2026-10-17 | Implemented and verified end-to-end lifecycle: sanitized credentials, parameterized n8n workflows (WF01-WF04), live Gemini 3.8 Flash investigation, atomic OTP publication/acceptance, live GitHub issue creation/supersession with verified readbacks, baseline v2 activation, and immutability assertions | [Live E2E Evidence](evidence/2026-10-17-end-to-end-execution.md); T03–T06, T08–T10, T12–T18, T21, T23, T27, T28, T42 PASS | Reliability, recovery, and reminder routines (B14/B15) |
| 2026-10-17 | Implemented and verified reliability routines: proposal expiry (T38), outbox idempotency (T37), worker crash recovery (T32), blocked failure guard (T29/T33), baseline supersession stale rejection (T20), concurrent case conflict guard (T22), and 429 Retry-After backoff honor (T30) | [Reliability recovery evidence](evidence/2026-10-17-reliability-recovery-evidence.md); 8 tests verified | Google Docs Scope Revision publication (B13) |
| 2026-10-17 | Implemented and verified Google Docs Scope Revision Generator, Publication & Read-Back Verification Adapter (`docs_adapter.py`), updated Migration 004 with `partially_applied` isolation, added integration test suite (`test_docs_integration.py`), and wired Docs revision into live E2E lifecycle (`run_e2e_lifecycle.py`) | [Docs revision evidence](evidence/2026-10-17-docs-revision-evidence.md); T27, T28, T33 PASS | Alternate Clouds hosted deployment (G0) and demo video (B18/B19) |
| 2026-10-17 | Corrected release evidence; added migration 005, secure OTP request/confirm workflows, Gmail intake, scheduled workers, real provider branches, authenticated read-only MCP workflows, and inactive credential placeholders | [Secure workflow implementation](evidence/2026-10-17-secure-workflow-implementation.md); DBU07–DBU09 PASS; all release rows reset to NOT RUN | Map live credentials, finish review-page UX, deploy manually, and execute the release matrix |

## Update procedure
At the start of a work session, read this file and select the next unmet gate. Assign an owner and change one or more task statuses. At the end, add exact work completed, test IDs/results, safe evidence links, blockers and next action. Update test-results.csv; retain failures and retests. Never store credentials here.
