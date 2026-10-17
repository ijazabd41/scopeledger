# Forms, screens and transactional content

## MVP surfaces
Use n8n Form nodes for simple collection and authenticated Webhook/Respond to Webhook HTML for dynamic review where needed. n8n generates forms, but does not automatically provide a complete secure client portal. Prototype rendering and identity before committing to specific node features. Escape all evidence and display only approved fields.

## Manager case page
Show request, project, current baseline, exact source excerpts/links, current task state, agent classification with caveats and evidence gaps. Controls: classify covered/change/ambiguous; request clarification; decline; publish options. Each option has action type, added/removed IDs, manager-confirmed effort, minor-unit price, currency, explicit date and explanation. Show old/new commitments side by side.

Display publication summary before confirmation: recipient, selected options, outgoing text, exact affected issues and proposal expiry. Require 'I reviewed the scope, estimates and delivery consequences.' Model estimates must be blank/unconfirmed, not silently prefilled as final.

## Client page
Before verification, show only project locator and code-request control. After verification, show proposal version, original commitments, change requested, alternatives and deadlines. Exclude internal margin/notes. Accept by selecting an option plus explicit confirmation and POST. Also offer reject and ask a question. On acceptance: 'Your choice is recorded. Project updates are being applied.' Do not show completed until verified.

## Status/receipt
States include awaiting manager, awaiting client, accepted pending sync, applying, partially applied, completed, blocked and expired. Show provider links for verified actions and next owner for blockers. A partial result must say which steps succeeded and which did not; never show a green all-done badge.

## Email templates (application messages, not LinkedIn posts)
Manager review: 'A request for {project} needs review. Current baseline: {revision}. Open the review page to inspect evidence and choose the next step. No project changes have been applied.'
Client invitation: 'We have prepared options for your requested change to {project}. Review proposal {version}, confirm your email and select an option by {expiry}. Your existing agreement remains unchanged until a change is accepted.'
Clarification: manager-edited question with request reference; replies become evidence, not acceptance.
Acceptance receipt: 'We recorded option {label} from proposal {version} at {time}. Synchronization status: {status}. Reference: {receipt_id}.'
Completion: 'The accepted change has been applied. Scope revision: {link}. Affected tasks: {links}. Reference: {receipt_id}.'
Blocked: 'Your choice remains recorded, but {step} needs attention. We have not marked the update complete. Owner: {role}.'

## Accessibility
Use clear labels, keyboard-operable controls, textual state labels and readable contrast. Dates include timezone. Errors identify how to recover. No color-only distinctions. Form tokens and OTP fields must not appear in screenshots or receipts.
