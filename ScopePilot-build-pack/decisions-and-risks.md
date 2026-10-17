# Decisions, risks and open questions

## Architecture decisions
| ID | Decision | Why / cost |
|---|---|---|
| ADR01 | n8n application layer | Faster real integration; custom portal UX and security still require work |
| ADR02 | PostgreSQL business ledger | Atomic acceptance and concurrency; requires routines and migrations |
| ADR03 | Database states rather than one long Wait execution | Recoverable cross-day work; more small workflows |
| ADR04 | Immutable proposals and new scope documents | Preserves history; requires document reconciliation |
| ADR05 | One agency and bound project resources | Feasible security surface; not public SaaS |
| ADR06 | Agent read-only, executor deterministic | Keeps model outside authorization; limited autonomous action |
| ADR07 | Real integrations, synthetic business scenario allowed | Externally verifiable demonstration without production client exposure |
| ADR08 | Client form, not free-text email acceptance | Exact versioned choice; additional user step |
| ADR09 | Actual MCP evidence read path | Coherent reusable tools; extra deployment/auth smoke check |
| ADR10 | Pin local/initial hosted candidate to n8n 2.43.7 with PostgreSQL 17.x and separate operational/business databases | n8n 2.43.7 emitted a compatibility-only warning on PostgreSQL 16; PostgreSQL 17 removes that known mismatch while preserving the authorization boundary |
| ADR11 | Python files are retained only as historical development/test harnesses; deployable business execution lives in n8n workflows | Restores the fixed one-service architecture; Python/local adapter output is not release evidence |
| ADR12 | Split OTP request/delivery from confirmation and authorized mutation | Prevents a workflow from issuing and immediately consuming its own OTP; challenge binds the exact proposal and manager case version |
| ADR13 | Import all workflow exports inactive with placeholder credential IDs | Prevents accidental execution after import and keeps credentials out of source; operator must map and inspect each credential before publishing |
| ADR14 | Rename the product to ScopePilot while retaining the lowercase `scopeledger` technical namespace | Gives the project a clearer product identity without invalidating migrations, database roles, credential mappings, webhook integrations, or audit markers |

## Risks and mitigations
1. Direct competitor overlap: ScopeGuard products advertise detection/change orders. Differentiate with explicit scope swaps and verified execution synchronization; validate with agencies, do not claim unique market.
2. Scope ambiguity: cite evidence, manager verifies baseline and commercial terms, ambiguous cases ask questions.
3. Partial provider writes: journal, reconcile and preserve acceptance; never blindly replay.
4. Approval impersonation/staleness: configured actors, OTP, bounded token, atomic version checks and project serialization.
5. Platform limitations: deploy first, verify persistence/ingress/credits, use support before expanding scope.
6. OAuth/setup friction: dedicated accounts and early live checks; restrict to one project.
7. n8n-only UI friction: prioritize readable evidence/decisions; add external UI only if core loop complete.
8. Concurrency outside app: providers may lack CAS; preserve human edits, minimize write surface, detect divergence, disclose race limitation.
9. Commercial hosting license: verify intended model against current terms before public paid rollout.

## Open questions (do not block independent implementation)
- Actual corrected deadline and freeze time? Confirm with organizer.
- Alternate Clouds supported n8n/PG versions, storage, private networking and model endpoint? Dev B verifies at G0.
- Which team accounts can supply dedicated Gmail, Drive and GitHub resources? Dev A verifies at G1.
- Who are the two developers and daily available hours? Assign in progress.
- One-step OTP+decision or short-lived verified session? Prototype on pinned n8n release and choose ADR10 before G2.
- Which agency can assess a redacted realistic scope-change scenario? Obtain feedback by Day 3.
- Should closed issue behavior mean 'superseded' or remain open with label? Manager explicitly chooses per action; default no closure.

## Go/no-go
Continue if G0/G1 pass and at least one agency user recognizes the workflow. Narrow scope if identity/partial recovery is unfinished by Day 5. Do not broaden integrations to compensate for an incomplete end-to-end loop. Revisit business thesis if users already solve it adequately or refuse the required connections.
