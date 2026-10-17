# Artifact verification

17 October 2026

- 19 relative Markdown links resolved.
- Agent JSON parsed; required/properties alignment, extra-field rejection declaration and manager-confirmation constant inspected.
- 42 release-test entries remain NOT RUN; six supplemental local database/runtime/package checks are recorded separately.
- PostgreSQL 17.6 executed the schema and migrations 002/003 successfully in a clean local database.
- The manual provisioning script passed on a fresh disposable PostgreSQL 17.6 container without storing its prompted synthetic passwords.
- The secret-free G0 workflow imported and published in n8n 2.43.7; its production webhook returned the expected safe receipt after a graceful restart.
- Full JSON Schema validator unavailable in authoring runtime; validate with a standards-compliant validator during implementation.
- The starter schema is now supplemented by tested authorization, publication, acceptance, claim, completion, expiry and least-privilege migrations. Hosted migration/rollback and live provider behavior remain unverified.
- Source URLs were checked selectively during research; external links are not a deployment guarantee.
