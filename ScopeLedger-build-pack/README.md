# ScopeLedger — implementation pack

Version 1.0 · 17 October 2026 · Documentation ready; application not built.

ScopeLedger helps a software agency resolve a client's change request before changing delivery commitments. An agent investigates the request; the manager chooses the commercial response; the client accepts an exact proposal; controlled automation updates the scope and GitHub tasks.

## Fixed decisions
- Two developers, seven working days. Use the user-confirmed timeline; the handbook deadline was reported incorrect. Confirm actual submission time with organizers.
- Deploy application services on Alternate Clouds. Docker/GitHub/database options were visible in the supplied dashboard; resource limits, persistent volumes and networking remain to be tested.
- n8n owns application logic, forms, webhooks, agents, MCP and scheduled jobs. No separate Python, LangGraph or React service in the MVP.
- PostgreSQL holds business state and atomic decisions. Do not use n8n execution history or Data Tables as the authoritative approval ledger.
- Integrate actual Gmail, Google Drive/Docs and GitHub accounts. Sample business content is permitted; fake integration success is not.
- Single agency installation, one configured client per project, one currency and one GitHub repository per project. Not a public multi-tenant SaaS.
- Scope swaps are the demonstration centerpiece. Estimates, pricing and delivery dates require manager confirmation.
- This pack is a build specification, not a verified implementation or importable n8n workflow export. SQL is a starter schema; transactions and provider adapters still need implementation and live tests.

## Read in this order
| File | Purpose |
|---|---|
| [product-requirements.md](product-requirements.md) | Product boundaries, stories and acceptance criteria |
| [architecture.md](architecture.md) | Components, trust boundaries and integration strategy |
| [state-and-data-model.md](state-and-data-model.md) | Cases, proposals, scope versions and concurrency |
| [workflow-specifications.md](workflow-specifications.md) | Node-level responsibilities and payload contracts |
| [security-and-approvals.md](security-and-approvals.md) | Manager/client identity, OTP, expiry and atomic consumption |
| [integration-setup.md](integration-setup.md) | Credential setup and live smoke checks |
| [agent-and-mcp.md](agent-and-mcp.md) | Agent prompt, tools and bounded authority |
| [ui-and-content.md](ui-and-content.md) | n8n forms, decision pages and transactional templates |
| [reliability-and-runbook.md](reliability-and-runbook.md) | Action journal, partial effects, reconciliation and support |
| [deployment.md](deployment.md) | Alternate Clouds setup and restart verification |
| [implementation-plan.md](implementation-plan.md) | Two-developer schedule and build gates |
| [testing-plan.md](testing-plan.md) | Functional, integration, security and recovery coverage |
| [progress.md](progress.md) | Honest implementation and evidence tracker |
| [demo-and-submission.md](demo-and-submission.md) | Demo script, rubric proof and submission checklist |
| [decisions-and-risks.md](decisions-and-risks.md) | Architecture decisions, unknowns and scope cuts |
| [sources.md](sources.md) | Official implementation references |
| [schema.sql](schema.sql) | Starter business database schema |
| [agent-output.schema.json](agent-output.schema.json) | Agent structured-output contract |
| [environment.example](environment.example) | Deployment configuration checklist; no secrets |

## Definition of done
A new real email creates a case, source evidence is retrieved, a verified manager publishes options, the verified client accepts an immutable proposal, actual document and issue changes are applied, and independent API reads prove them. Stale acceptance, duplicate callbacks, provider errors and process restart do not silently produce unauthorized or repeated changes. Every required test has a dated evidence entry. No test currently has a passing result.

## First action
Read progress.md; perform G0 deployment and G1 integration smoke tests before implementing agent sophistication. Add evidence as work completes. Commit this directory with the project repository when implementation starts. Never store real credentials in these documents.

## Current implementation handoff

The locally verified G0/database foundation is implemented under `db/`, `deployment/`, and `workflows/`. Start manual hosting with [deployment/alternate-clouds/README.md](deployment/alternate-clouds/README.md). This package does not yet contain the G1–G7 business workflows or live provider credentials; see `progress.md` for the exact boundary.
