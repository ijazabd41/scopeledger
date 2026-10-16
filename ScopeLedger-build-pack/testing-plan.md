# Testing plan

Status: planned, not executed. No passing application tests are claimed.

## Test environments
Use actual deployed n8n on Alternate Clouds, actual PostgreSQL and dedicated Gmail/Drive/GitHub resources. Synthetic contracts and labeled agent evaluation cases are permitted; live acceptance must not rely on stubbed provider responses. Unit-level isolated tests may use controlled fakes, but mark them UNIT-ONLY and never count them as proof of integration.

Fault injection should use a controlled proxy/adapter failure switch or temporary credential/network change against dedicated resources. Record whether the provider committed before the response was lost. A fixture that merely returns a fabricated success does not prove recovery.

## Preconditions
G0/G1 smoke tests, pinned n8n image, applied starter schema plus reviewed transactional routines, configured actors and baseline, supported model/tool access, clean demo resources and redacted evidence location. Never run destructive tests on production client data.

## Test matrix
| ID | Priority | Area | Procedure | Required result |
|---|---|---|---|---|
| T01 | P0 | Hosting | Call hosted production webhook | HTTPS response from Alternate Clouds; safe receipt |
| T02 | P0 | Hosting | Restart n8n with a pending approval | Business state and credentials persist; no writes auto-run |
| T03 | P0 | Integration | Send real client email | One correct project case with provider message ID |
| T04 | P0 | Integration | Deliver the same intake event twice | One case, no duplicate review mail |
| T05 | P0 | Routing | Use unknown or ambiguous sender/project | Blocked routing; no model-selected destination |
| T06 | P0 | Evidence | Fetch live scope and GitHub issues | Correct excerpts/revisions; PRs excluded |
| T07 | P1 | Evidence | Missing/deleted source document | Visible missing evidence; no definitive classification |
| T08 | P0 | Agent | Run covered/addition/ambiguous examples | Evidence-backed classification; uncertainty escalated |
| T09 | P0 | Agent | Inject send-secrets instruction in email/document | No external send/write or credential access |
| T10 | P0 | Agent | Return invalid schema or unknown evidence ID | One repair attempt then manager escalation |
| T11 | P0 | MCP | Invoke tools through deployed agent | Authenticated real MCP trace; configured case only |
| T12 | P0 | Auth | Request OTP for another email in form | Code goes only to configured actor; no data disclosure |
| T13 | P0 | Auth | Submit wrong OTP five times, request rapidly | Attempt limit and resend/global rate limits enforced |
| T14 | P0 | Auth | Use expired/consumed OTP or wrong-role token | Denied; no proposal/action transition |
| T15 | P0 | Approval | Open GET link with email scanner | No acceptance or external mutation |
| T16 | P0 | Approval | Manager publishes confirmed swap and fee alternatives | Immutable payload/recipient/date/currency validated |
| T17 | P0 | Approval | Client accepts exact swap | One decision and outbox; accepted pending sync receipt |
| T18 | P0 | Approval | Replay identical acceptance 10 times | Same receipt; one action set |
| T19 | P0 | Approval | Race two acceptance POSTs | Exactly one accepted outcome; loser gets receipt/conflict |
| T20 | P0 | Approval | Change baseline/proposal after token issuance | Stale acceptance rejected; re-review required |
| T21 | P0 | Approval | Tamper price, recipient or removed issue in POST | Stored immutable option used; tampering denied |
| T22 | P0 | Approval | Accept two cases against same baseline concurrently | Project lock allows one; other conflicts |
| T23 | P0 | Branch | Client rejects proposal | No scope/task writes; recorded rejection |
| T24 | P1 | Branch | Manager approves clarification; client replies | Approved email sent; reply is evidence, not acceptance |
| T25 | P1 | Branch | Manager declines request | Only approved response sent; baseline unchanged |
| T26 | P0 | Branch | Client accepts fee or goodwill option | Only selected confirmed scope changes apply; no fake payment |
| T27 | P0 | Execution | Apply accepted swap against real providers | New issue; authorized supersession; populated scope doc |
| T28 | P0 | Execution | Independently read back external effects | Expected fields/markers match; links accessible |
| T29 | P0 | Failure | Force 401/403 on a write | Blocked with reconnect instructions; no blind retries |
| T30 | P0 | Failure | Force 429 with Retry-After | Bounded retry; honor delay; action not duplicated |
| T31 | P0 | Failure | Provider write succeeds but response is dropped | Unknown action reconciled; no immediate repeat write |
| T32 | P0 | Failure | Kill worker after first verified write | Resume unfinished actions after read-back; no duplication |
| T33 | P0 | Failure | Make Docs fail after GitHub success | Partially applied visible; acceptance retained; project blocked |
| T34 | P0 | Failure | Edit target issue during review | Preserve edit; invalidate execution plan or re-review |
| T35 | P0 | Failure | Return two resources with same action marker | Block ambiguous reconciliation; no arbitrary choice |
| T36 | P0 | Failure | Database unavailable during acceptance | No authorized external writes; safe resubmission later |
| T37 | P1 | Notification | Mail accepted by provider but response lost | Reconcile sent or mark unknown; no blind resend |
| T38 | P0 | Expiry | Let proposal expire without response | Expired, never accepted; no task writes |
| T39 | P1 | UI | Keyboard navigation and malicious HTML excerpt | Usable controls; escaped text; no script execution |
| T40 | P0 | Privacy | Inspect workflow export/logs/video | No secrets/OTP/token; client cannot open editor |
| T41 | P1 | Recovery | Restore backup in controlled deployment | Workflow/business state usable; key restores credentials |
| T42 | P0 | End-to-end | Fresh request to completed live swap | Entire hosted flow verified with timestamped receipts |

## Release gate
All P0 cases must pass on the deployment candidate, with no unresolved authorization, data-loss, duplicate-write or false-completion defects. P1 cases must pass or have an explicit documented limitation and a deliberate feature cut; a limitation is not a pass. Repeat relevant tests after fixes. Record one full end-to-end run after deployment/config changes. Test all advertised commercial branches; if not implemented, disable them visibly.

Run at least 10 duplicate submissions and 5 concurrent-approval trials on dedicated cases. These are a small functional check, not a scalability or reliability guarantee. Run the 12-case actual-model evaluation specified in agent-and-mcp.md; record failures, do not curate them away.

## Measurement
Record intake-to-case latency, agent latency/tool count, decision-to-verification time, API call count and model spend. Human waiting time is reported separately. Proposed targets: intake within configured polling interval plus processing time, investigation under 90 seconds or explicit fallback, completion under 120 seconds when providers respond normally. These are targets to measure, not promised SLAs.

## Evidence record template
- Test ID and build/workflow version:
- Date/time UTC and tester:
- Preconditions/case/proposal IDs:
- Real providers involved:
- Steps performed and injected fault:
- Expected vs observed:
- Result: NOT RUN / PASS / FAIL / BLOCKED:
- Safe resource links/screenshots/log excerpt:
- Defect ID and retest result:

Never record tokens, OTPs or private credentials. Link each completed test from progress.md. See test-results.csv for a blank results register.
