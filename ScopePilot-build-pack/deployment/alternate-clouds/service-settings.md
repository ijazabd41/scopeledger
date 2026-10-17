# Alternate Clouds service settings

Replace angle-bracketed values in the platform secret/config UI. Do not create a populated copy in source control.

## PostgreSQL service

| Field | Value |
|---|---|
| Engine | PostgreSQL 17.x (17.6 in the checked local harness) |
| Service name | `scopeledger-postgres` |
| Persistence | Required; record mount/volume and backup behavior |
| Network | Private project link preferred |
| TLS | Verify provider CA; never set reject-unauthorized false as a shortcut |
| Databases | `n8n` operational; `scopeledger` business |
| Runtime roles | `n8n_runtime`, `scopeledger_reader_login`, `scopeledger_web_login`, `scopeledger_worker_login` |

## n8n service

| Field | Value |
|---|---|
| Service name | `scopeledger-n8n` |
| Docker image | `docker.n8n.io/n8nio/n8n:2.43.7` |
| Container port | `5678` |
| Persistent mount | `/home/node/.n8n` |
| Public URL | `https://<platform-assigned-host>` |
| Health/readiness | `/healthz/readiness` |

Environment variables:

```dotenv
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=<PRIVATE_POSTGRES_HOST>
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_SCHEMA=public
DB_POSTGRESDB_USER=n8n_runtime
DB_POSTGRESDB_PASSWORD=<SECRET>
DB_POSTGRESDB_POOL_SIZE=5
DB_POSTGRESDB_SSL_ENABLED=true
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=true
# Set only when the provider requires an explicit CA value:
# DB_POSTGRESDB_SSL_CA=<PROVIDER_CA_PEM>

N8N_ENCRYPTION_KEY=<FRESH_RANDOM_VALUE_AT_LEAST_32_BYTES>
N8N_HOST=<PLATFORM_ASSIGNED_HOST_WITHOUT_SCHEME>
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_WEBHOOK_URL=https://<PLATFORM_ASSIGNED_HOST>/
N8N_EDITOR_BASE_URL=https://<PLATFORM_ASSIGNED_HOST>/
PUBLIC_REVIEW_URL=https://<PLATFORM_ASSIGNED_HOST>/form/<CLIENT_REVIEW_FORM>
SCOPELEDGER_MAILBOX_ID=<STABLE_GMAIL_MAILBOX_ID>
SCOPELEDGER_PROJECT_ID=<CONFIGURED_PROJECT_UUID>
GEMINI_MODEL=gemini-2.5-flash
N8N_PROXY_HOPS=<VERIFIED_INGRESS_PROXY_COUNT>
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
GENERIC_TIMEZONE=Asia/Karachi
TZ=UTC

EXECUTIONS_MODE=regular
EXECUTIONS_TIMEOUT=180
EXECUTIONS_TIMEOUT_MAX=900
EXECUTIONS_DATA_SAVE_ON_SUCCESS=none
EXECUTIONS_DATA_SAVE_ON_ERROR=none
EXECUTIONS_DATA_SAVE_ON_PROGRESS=false
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=false
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168
EXECUTIONS_DATA_PRUNE_MAX_COUNT=5000
N8N_PAYLOAD_SIZE_MAX=4
N8N_METRICS=false
N8N_UNVERIFIED_PACKAGES_ENABLED=false
N8N_RUNNERS_TASK_TIMEOUT=90
N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES=268435456
N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES=1000

NODES_EXCLUDE=["n8n-nodes-base.executeCommand","n8n-nodes-base.readWriteFile"]
```

If the database service uses private, provider-terminated TLS without an explicit CA, follow its documented verified configuration. Do not guess the TLS fields or disable verification.

## Business credentials inside n8n

All three point to database `scopeledger` but use different users:

| n8n credential | Login | Use |
|---|---|---|
| `scopeledger-reader-db` | `scopeledger_reader_login` | evidence and investigator reads |
| `scopeledger-web-db` | `scopeledger_web_login` | OTP, manager publication, client decisions |
| `scopeledger-worker-db` | `scopeledger_worker_login` | action claims, results, expiry, finalization |

Additional credentials referenced by the sanitized workflow exports:

| n8n credential | Type / required configuration |
|---|---|
| `scopeledger-gmail` | Gmail OAuth2; dedicated demo mailbox with read/send access |
| `scopeledger-github` | GitHub API; repository-scoped token for the configured demo repository |
| `scopeledger-google-oauth` | Generic OAuth2 bearer credential with Drive file and Docs scopes |
| `scopeledger-gemini-api-key` | Header Auth using header `x-goog-api-key` and the model API key |
| `scopeledger-internal-webhook` | Header Auth with a fresh random internal-only header/value pair |
| `scopeledger-mcp-bearer` | Bearer Auth with a fresh random token used only by approved MCP clients |

Every workflow export is intentionally inactive and contains placeholder credential IDs. After
import, map each reference to the credential with the exact name above, inspect the nodes, and
only then publish the workflow. Error and success execution payload persistence are disabled
because OTPs and private client text pass through the approval and intake workflows; PostgreSQL
remains the durable audit ledger.

Do not grant these logins membership in each other’s group roles.

The pinned release warns that internal task-runner mode is deprecated. This MVP keeps the built-in JavaScript runner to preserve the one-service architecture and does not install Python. Before a longer-lived production rollout, add n8n's supported external task-runner companion and its shared authentication secret, then retest every Code-node workflow.
