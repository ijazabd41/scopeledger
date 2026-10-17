# Sources and provenance

Checked 17 October 2026. Live documentation changes; pin the installed n8n release and retest exact node behavior. These references support capabilities, not proof this implementation works. Some previously published URLs redirect to updated documentation paths.

## Official implementation references
- n8n Wait: https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.wait/ — database-backed waiting and webhook/form continuation. Business approval authority remains separate.
- n8n Forms: https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.formtrigger/ — generated form interface; not a complete authenticated portal.
- n8n MCP Server Trigger: https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.mcptrigger/ — expose tool workflows to MCP clients.
- n8n Postgres: https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.postgres/ — database operations; validate parameterized query/transaction behavior in installed node.
- n8n reverse proxy webhook configuration: https://docs.n8n.io/hosting/configuration/configuration-examples/webhook-url/
- n8n official Docker instructions: https://github.com/n8n-io/n8n-docs/blob/main/docs/deploy/host-n8n/install-options/install-with-docker.md
- n8n Docker Compose and PostgreSQL configuration: https://docs.n8n.io/deploy/host-n8n/install-options/install-with-docker/ and https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/use-environment-variables/database/
- n8n health/readiness endpoints: https://docs.n8n.io/deploy/host-n8n/keep-n8n-running/monitor-n8n/
- n8n releases (2.43.7 stable checked 17 October 2026): https://github.com/n8n-io/n8n/releases
- n8n license: https://docs.n8n.io/sustainable-use-license/
- Gmail sending: https://developers.google.com/workspace/gmail/api/guides/sending — real message/draft sending and MIME behavior.
- GitHub Issues REST: https://docs.github.com/en/rest/issues/issues — real task operations.
- Google Drive sharing: https://developers.google.com/workspace/drive/api/guides/manage-sharing
- Google Docs API reference (verify create/read/write revision operations before implementation): https://developers.google.com/workspace/docs/api/reference/rest
- Alternate Clouds deployment tutorial: https://docs.alternatefutures.ai/guides/deploy-an-agent — built-in agent tutorial, not proof of custom n8n topology.
- Alternate Clouds dashboard/deployment model: https://docs.alternatefutures.ai/guides/dashboard and https://docs.alternatefutures.ai/guides/how-deployments-work

## Product research
- ScopeGuard private beta: https://www.scopeguard.ai/ — advertises SOW monitoring, pricing and approved change orders. Feature overlap is real; traction not established here.
- ScopeGuard Pro: https://scopeguard.pro/ — advertises scope tracking/client approval; full functionality not independently tested.

## User-provided evidence
Agentika Participant Handbook.pdf: deployment on Alternate Clouds, submission proof, theme/rubric and self-written LinkedIn rule. User explicitly corrected the timeline; actual deadline must be confirmed.
Platform screenshot: GitHub Repo, Template, Database, Docker Image, Function, Bucket, Server options. Does not prove configured services are operational.
Rubric screenshot: execution 25, impact 20, theme 15, creativity 15, depth 15, UX 10.

## Verification boundaries
No accounts connected, credentials inspected, workflows imported, SQL executed against PostgreSQL, services deployed, tests passed or money recovered during documentation authoring. Live build evidence must be recorded separately.
