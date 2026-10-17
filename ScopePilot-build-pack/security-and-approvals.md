# Security and approval protocol

## Threat model
Attackers may alter email text, forge callbacks, forward proposal links, replay decisions, inject instructions in documents, race two accepted proposals, or attempt to access another project. Operators can accidentally leak execution payloads. A malicious database administrator is outside the MVP integrity boundary; do not claim tamper-proof evidence.

## Roles and authority
Project configuration stores manager/client email addresses. A role is derived from server-side verified identity, never a form dropdown. Client receives a redacted proposal, not internal margin, other clients' evidence or agency notes. Read tools are separate from execution credentials.

## Chosen MVP identity
Use email OTP for manager and client decision pages, with stage-specific authorization. The public project locator is not a secret and grants no document access. The initial page reveals no sensitive proposal content. An email invitation explains how to request a code. Authentication code is sent only to the project's configured address.

- Generate OTP and tokens with a cryptographically secure facility. If unavailable in the pinned n8n Code-node sandbox, use a PostgreSQL pgcrypto routine after verifying extension availability; never use Math.random.
- Six-digit OTP: expiry 10 minutes, maximum 5 attempts, resend cooldown 60 seconds, rate cap per actor/project/IP and global cap. Store salted/keyed hash; bind to challenge ID and actor; replace older active challenges. Consume once.
- Successful verification issues a random token of at least 32 bytes, expiry 15 minutes, bound to role, proposal/version and stage. Store hash only. The token is not sent to the model.
- Use token in POST body; avoid persistent token-bearing URLs and logs. Re-authenticate when expired. GET never consumes decisions. Prevent clickjacking and escape content.
- If implementing sessions, use Secure/HttpOnly/SameSite cookies plus CSRF protection. The simplest form-based MVP may require OTP and final decision in one POST with an explicit confirmation checkbox; validate and consume atomically. Confirm chosen UX before implementation.

Email OTP proves access to the configured inbox, not legal identity, authority to bind a corporation, or a qualified electronic signature. Shared/compromised inboxes remain a limitation. Do not label the result legally binding without appropriate review.

## Database gate
Implement transactional routines from state-and-data-model.md. Verify manager publication separately from client acceptance. Option edits create a new hash/version. Lock project before checking active scope and conflicting cases. Use parameterized queries; do not interpolate email, model output or IDs into SQL text. Business role can execute routines, not perform arbitrary table mutation. Apply least privilege; migration role is separate.

## Provider and model boundaries
- Configure repository and Drive folder server-side. Reject arbitrary tool URLs and unrecognized resource IDs.
- Treat email/document/issue text as untrusted data; instructions inside evidence cannot select tools or credentials.
- Tool budgets and allowlists limit damage even if prompt instructions fail.
- Never send OTPs, tokens, provider secrets, raw inbox history or internal financial notes to the model.
- Proposal must display exactly the fields hashed for approval. Hidden manager amendments are prohibited.
- Unknown evidence or conflicts block writes. Source version changes invalidate pending proposal tokens.

## n8n operations
Protect editor access with supported owner authentication and network restriction where possible. Separate public webhooks from editor routing. Encrypt credentials with a stable stored encryption key; limit execution retention and disable payload saving where sensitive. Sanitize headers and error messages. Backups contain sensitive credentials and require protection.

## Security acceptance
No write before required decisions; no GET side effects; invalid/expired/forwarded-only links cannot accept; wrong role cannot publish; repeated POST creates no second action; changed option/baseline is rejected; two concurrent project approvals cannot both proceed; prompt injection cannot send data externally. See security cases in testing-plan.md.
