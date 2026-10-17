# Integration setup and live checks

Use dedicated real demo accounts and resources. Real provider actions on sample content satisfy integration; fabricated API responses do not. Do not connect production client material during development.

## Google account and OAuth
1. Create a Google Cloud project under a team-controlled account. Enable Gmail, Drive and Docs APIs as required.
2. Configure consent screen and test users. A test-mode OAuth app can have token/refresh limitations; verify the actual consent configuration and reauthorization behavior.
3. Create the OAuth client required by the pinned n8n credential type. Copy the exact redirect URI displayed by deployed n8n; never guess it.
4. Register that URI and connect the dedicated agency mailbox and scope folder.
5. Use least required scopes supported by the selected nodes: reading selected mail, sending mail, reading selected scope files, creating revision documents. Drive scope and file visibility must be tested; drive.file may not cover preexisting arbitrary files.
6. Store credentials only in n8n credential storage. Never embed access tokens in workflow JSON, screenshots or environment.example.

## Gmail intake and sends
Label selected messages ScopePilot/Intake; route using explicit project mapping or a stable project code in subject. Record mailbox ID, provider message ID, thread ID and Internet Message-ID. Fetch selected thread messages when investigation needs them, not the whole mailbox. Use Gmail node for threading if supported; raw API sends need MIME, base64URL, In-Reply-To and References as appropriate. Use a unique notification Message-ID/marker and verify sent status without claiming exactly-once delivery.

Live check GMAIL-01: send a new email from the configured client to the actual inbox; trigger receives it. GMAIL-02: send a safe notification to that configured address and verify receipt. GMAIL-03: replay the provider event; one case exists.

## Drive and Docs
Create a dedicated folder, original scope document and baseline mapping. Persist source file ID, retrieved revision/hash and normalized deliverable IDs. New accepted scope version becomes a newly created document in that folder, with case/proposal/revision marker. Use Docs API operations supported by actual node or HTTP Request; verify create, populate and read-back behavior. A created empty document is not successful publication. Do not assume Docs has arbitrary application-defined metadata; marker may live in document text or Drive appProperties through supported APIs.

Live check DRIVE-01: read actual original text. DOCS-01: create/fill/read a revision document and verify its content. DOCS-02: simulate lost response; find/reconcile marker or leave unknown, rather than generate duplicates. Client must have intended viewing access; test in their account.

## GitHub
Create a dedicated repository with Issues enabled. Use a fine-grained PAT or GitHub App scoped to that repository; metadata read and Issues read/write as required. Keep repository owner/name configured, not model-selected. Preserve issue number, node/resource ID, updated_at and fingerprint of fields to change. Issue listing endpoints can include PRs: exclude objects containing pull_request.

Live check GH-01: list real issues. GH-02: create one marked task and independently fetch it. GH-03: add the approved supersession comment/label to a sample issue. GH-04: revoke the token and confirm execution blocks visibly.

## Credential checklist
| Credential | Owner | Required proof |
|---|---|---|
| Alternate Clouds account/credits | Dev B | Running application + restart test |
| Business PostgreSQL role | Dev B | Migration + transactional claim test |
| Gmail OAuth | Dev A | Real intake and received outgoing mail |
| Drive/Docs OAuth | Dev A | Read original; create/read revision |
| GitHub credential | Dev A | Read/create/update sample issue |
| Model credential/gateway | Dev B | Tool call and structured output |
| MCP credential | Dev B | Authenticated agent invocation trace |

All proofs are currently pending. Capture timestamps and safe IDs in progress.md. Credential identifiers are fine; credential values are not.
