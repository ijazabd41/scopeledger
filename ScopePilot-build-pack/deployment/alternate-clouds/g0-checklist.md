# G0 manual acceptance checklist

Do not mark T01/T02 passing until every required item has evidence from Alternate Clouds.

## Before deployment

- [ ] Correct organization and `scopeledger-mvp` project selected.
- [ ] Budget/auto-stop reviewed; sufficient credits for at least one hour.
- [ ] PostgreSQL 17 service has persistent storage and a documented backup path.
- [ ] Database TLS/CA settings are known and verification remains enabled.
- [ ] n8n image is exactly `docker.n8n.io/n8nio/n8n:2.43.7` (record digest if the platform shows it).
- [ ] Fresh stable `N8N_ENCRYPTION_KEY` stored only in the platform secret UI and backup vault.
- [ ] `/home/node/.n8n` is persistent.
- [ ] Database and n8n are linked privately where supported.
- [ ] Editor owner authentication is configured; no client receives editor access.

## Database proof

- [ ] `provision.psql` ends with `scopeledger_provisioning_complete`.
- [ ] Expected privilege tuple is `n8n_connect=t`, `web_decide=t`, `web_direct_action_insert=f`, `reader_evidence=t`, `reader_auth=f`.
- [ ] `n8n` and `scopeledger` are separate databases.
- [ ] Migration backup/restore procedure is recorded before later changes.

## T01 — HTTPS webhook

- [ ] `/healthz/readiness` returns 200 from a clean external browser/client.
- [ ] WF-G0 is imported, inspected, saved, and published.
- [ ] `verify-hosted.ps1` returns readiness/webhook status `ok`.
- [ ] Service URL, deployment ID, image version, UTC timestamp, and redacted receipt are saved under `evidence/`.
- [ ] HTTP (non-TLS) access is unavailable or redirects safely to HTTPS.

## T02 — restart persistence

- [ ] Create or identify a synthetic pending approval row; record only its safe ID/state.
- [ ] Restart/redeploy n8n without changing the encryption key or database.
- [ ] Wait for `/healthz/readiness` 200.
- [ ] Run `verify-hosted.ps1` again.
- [ ] Confirm pending business state is unchanged and no action/notification ran.
- [ ] Confirm workflows and encrypted credentials remain available.
- [ ] Record before/after UTC timestamps and safe IDs.

## Rollback

1. Export workflows without decrypted credentials.
2. Back up both PostgreSQL databases and the encryption key before an image/config change.
3. Record the currently active deployment and image digest/tag.
4. On application failure, redeploy the last known-good pinned image/config; do not reverse database migrations automatically.
5. On migration failure, stop n8n writes, restore the pre-migration database backup into a controlled service, validate it, then switch only after review.
6. Reconcile running/unknown actions before any worker is resumed. Never replay a whole accepted case.

## Evidence boundary

Local file `evidence/2026-10-16-local-database-validation.md` is useful preflight evidence only. It cannot be copied as T01/T02 hosted proof.
