# ScopeLedger progress tracker

Updated: 17 October 2026. Implementation session 1 completed a locally verified database/runtime slice; hosted deployment and live integrations remain blocked.

## Status convention
TODO = not started; IN PROGRESS = active with owner; BLOCKED = named prerequisite; DONE = acceptance criteria met with evidence. Never mark DONE from generated code alone. Test results remain NOT RUN until executed.

## Current checkpoint
- Current gate: G0 — Alternate Clouds deployment and persistence (awaiting manual operator deployment by user request).
- Next action: operator follows `deployment/alternate-clouds/README.md`, then records hosted HTTPS/restart evidence for T01/T02.
- Developer A: unassigned.
- Developer B: unassigned.
- Confirmed event deadline/freeze: unconfirmed; use user-confirmed one-week build window until organizer clarification.
- Application release/version: database migrations 002/003; local runtime candidate n8n 2.43.7.
- Live deployment URL: not created.
- Source repository URL: not created.
- Tests: 0/42 release tests executed; 6 supplemental local checks passing; no hosted/provider reliability claim.

## Current execution plan
1. G0: deploy the pinned runtime and separated PostgreSQL databases on Alternate Clouds; prove HTTPS and restart persistence.
2. G1: configure dedicated Gmail, Drive/Docs, GitHub and model credentials and run one real read/write/read-back per provider.
3. Continue the smallest vertical slice: one email → evidence → immutable proposal → exact acceptance → verified scope swap.

## Documentation completed
- [x] Product requirements and definition of done
- [x] Architecture and workflow responsibilities
- [x] Data/state model and starter SQL schema
- [x] Approval security, integration setup and agent/MCP contract
- [x] Reliability, deployment and implementation plan
- [x] Testing matrix, blank results register and demo/submission checklist
- [x] Source references and risk register

These checkboxes mean the documents exist, not that described features work. Artifact packaging checks are separate from application tests.

## Build backlog
| ID | Task | Owner | Status | Acceptance / evidence |
|---|---|---|---|---|
| B01 | Confirm corrected deadline, platform constraints and credits | B | TODO | Organizer/platform confirmation |
| B02 | Deploy n8n and persistent PostgreSQL on Alternate Clouds | B / implementation agent | IN PROGRESS | Local 2.43.7 harness passes; hosted T01/T02 still blocked |
| B03 | Configure dedicated Google/GitHub/model credentials | A | TODO | G1 live read/write proofs |
| B04 | Apply schema and implement privileged transaction routines | B / implementation agent | IN PROGRESS | Migrations 002/003 and local authorization/concurrency evidence; hosted apply and rollback trial remain |
| B05 | Configure one real project and manager-verified baseline | A | TODO | WF00 scope/task mapping |
| B06 | Build email intake and dedup | A | TODO | T03–T05 |
| B07 | Retrieve/version evidence and resolve actual issues | A | TODO | T06/T07 |
| B08 | Build OTP identity, roles and review pages | B | TODO | T12–T15/T39 |
| B09 | Build MCP read tools and bounded investigator | A | TODO | T08–T11 + actual-model evaluation |
| B10 | Build manager decisions and immutable publication | B | TODO | T16/T21 |
| B11 | Build atomic client acceptance/reject/clarify | B | TODO | T17–T24 |
| B12 | Implement action claims, leases and provider writes | A | TODO | T27/T28 |
| B13 | Implement Docs revision publication and activation | A | TODO | Populated doc verified; T33 |
| B14 | Implement notification outbox/reminders/expiry | B | TODO | T25/T37/T38 |
| B15 | Add reconciliation and operator recovery | A+B | TODO | T29–T36 |
| B16 | Run full test matrix and fix all P0 defects | A+B | TODO | testing-plan.md + test-results.csv |
| B17 | Export safe workflows and restore-test backups | B | TODO | T40/T41 |
| B18 | Record fresh end-to-end deployed demonstration | A | TODO | T42 + video link |
| B19 | Complete self-written social post and submission PDF | A+B | TODO | Accessible links/screenshots; no AI-written post |

## Gate register
| Gate | Status | Evidence | Blocking issue |
|---|---|---|---|
| G0 Hosting | BLOCKED | [local-only runtime evidence](evidence/2026-10-16-local-database-validation.md) | User requested manual deployment; operator must complete [the deployment runbook](deployment/alternate-clouds/README.md) and T01/T02 |
| G1 Integrations | BLOCKED | — | Dedicated provider credentials not configured |
| G2 Intake and identity | TODO | — | G0/G1 |
| G3 Agent and manager publication | TODO | — | G2 |
| G4 Client decisions | TODO | — | Atomic routines and identity |
| G5 Real execution | TODO | — | G4 + adapters |
| G6 Reliability/security | TODO | — | Working execution |
| G7 Submission | TODO | — | G6 + actual event timing |

## Blockers
| ID | Description | Owner | Next action | Opened | Resolved |
|---|---|---|---|---|---|
| BL01 | Hosted G0 requires the user's manual Alternate Clouds deployment | B | Follow `deployment/alternate-clouds/README.md`; return safe URL/service IDs and T01/T02 evidence | 2026-10-17 | — |
| BL02 | Gmail/Drive/GitHub credentials not configured | A | Complete integration-setup.md | 2026-10-17 | — |

## Session log
| Date | Completed | Tests/evidence | Next |
|---|---|---|---|
| 2026-10-17 | Initial documentation pack authored | Artifact consistency checks only; application tests not run | B01–B03 |
| 2026-10-17 | Added atomic OTP/publication/acceptance/action/finalization routines, immutable/append-only guards, least-privilege roles, separated local DBs, and n8n 2.43.7 harness | [DBU01–DBU04 local evidence](evidence/2026-10-16-local-database-validation.md); release tests remain NOT RUN | Authenticate Alternate Clouds; deploy G0; configure G1 credentials |
| 2026-10-17 | Added manual Alternate Clouds runbook, secure interactive provisioning, service manifest, hosted verifier and importable G0 workflow; corrected PostgreSQL target to 17.6 and `N8N_WEBHOOK_URL` from observed runtime behavior | [DBU05–DBU06 local evidence](evidence/2026-10-16-local-database-validation.md) | User manually deploys G0; then run live T01/T02 and G1 provider checks |

## Update procedure
At the start of a work session, read this file and select the next unmet gate. Assign an owner and change one or more task statuses. At the end, add exact work completed, test IDs/results, safe evidence links, blockers and next action. Update test-results.csv; retain failures and retests. Never store credentials here.
