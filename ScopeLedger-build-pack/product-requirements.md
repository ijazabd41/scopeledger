# Product requirements

## Buyer and problem
Initial buyer: owner/account manager at a small software or automation agency. Client requests arrive in email while commitments live in documents and tasks. The agency needs to distinguish covered work, clarification and commercial change, and agree on trade-offs before developers proceed.

Business hypothesis: explicit changes reduce unagreed work and coordination time. A proposed USD 49–149 monthly price is unvalidated. Track time and agreements; do not claim recovered revenue from merely detected requests.

## Roles
- Manager: named project owner; confirms estimates, selects options, approves outgoing commercial content.
- Client decision maker: one configured email address; approves an exact option or rejects/asks for clarification.
- Operator: manages credentials, failed actions and deployment. Cannot fabricate client acceptance.
- Agent: reads bounded evidence and recommends; cannot approve, publish commitments or execute writes.

## MVP use case
The baseline includes a marketing website and CSV export. Client asks for an account dashboard. Manager offers (A) additional fee with a confirmed revised date or (B) exchange CSV export for the dashboard. Client chooses B. The dashboard issue is created, export is marked superseded with provenance, and a new scope document is published. Prior scope remains preserved.

## Functional requirements
| ID | Requirement | Acceptance |
|---|---|---|
| FR01 | Deduplicate email intake | Same mailbox/message ID creates one case |
| FR02 | Resolve project from configured routing | Ambiguous sender/project is held; model cannot choose credentials |
| FR03 | Retrieve scope and amendments | Evidence retains resource ID, revision/hash and quoted excerpt |
| FR04 | Inspect current tasks | Only allowlisted repository is queried; PR objects excluded from issue listings |
| FR05 | Classify request | covered/change/ambiguous with evidence; classification is advisory |
| FR06 | Ask for missing details | Manager reviews exact outgoing clarification; reply creates a new evidence version |
| FR07 | Publish manager-confirmed options | Fee, currency, date and affected deliverables validated before publication |
| FR08 | Accept exact proposal | Identity, option, version, expiry, baseline and consumed status checked atomically |
| FR09 | Handle all decisions | Charge, swap, goodwill, clarification and decline have explicit branches |
| FR10 | Update actual systems | Verified GitHub and Docs results; no success from model text |
| FR11 | Preserve agreement history | Immutable proposal and scope revision references remain accessible |
| FR12 | Recover partial effects | Only unfinished/reconciled actions resume; no blind replay |
| FR13 | Remind and expire | Silence never means consent; expiry blocks execution |
| FR14 | Provide audit view | Case status, decisions, actions and safe evidence links available to manager |

## Rules
- A covered request still requires manager confirmation before task writes in MVP.
- Charge/swap/goodwill changes all require client acceptance of the proposed revision; goodwill means zero additional fee, not no agreement.
- A decline sends only manager-approved content; no baseline/task changes.
- Client questions are not acceptance. Only the verified decision form can accept in MVP; email replies become evidence.
- Manager may edit generated options; edits create a new version and require republishing.
- A swap must enumerate removed and added deliverable IDs. No full-project replacement inferred by the model.
- Money stored as integer minor units. One configured currency with two decimal places; restrict supported currencies until unit rules exist.
- Dates are explicit ISO dates/timezones confirmed by manager; the agent does not predict availability.
- The accepted revision can be pending synchronization. Block subsequent project changes until all required external effects are verified.

## Exclusions
Payment collection, automatic invoicing, electronic-signature/legal-enforceability claims, Slack intake, audio calls, scanned document OCR, autonomous effort estimation, automatic code changes, project-wide scheduling, multilingual contracts, multi-party acceptance and public SaaS onboarding.

## Success metrics
Measure median manager handling time, client turnaround, proposals accepted/rejected, agreed additional fees (not collected revenue), verified task synchronization and recovery count. Compare measured manual and automated runs on the same scenario, including human time. Three prospective agencies should assess the complete workflow before claiming product-market validation.
