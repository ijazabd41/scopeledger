-- ScopeLedger starter business schema, PostgreSQL 14+.
-- Not executed against PostgreSQL during documentation authoring.
-- Separate from n8n operational tables. Review migration in disposable database.
-- Transactional auth/publication/acceptance/claim routines are REQUIRED and not supplied here.
BEGIN;
CREATE SCHEMA IF NOT EXISTS scopeledger;
SET search_path TO scopeledger, public;
CREATE TABLE projects (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL,
 manager_email text NOT NULL, client_email text NOT NULL,
 repo_owner text NOT NULL, repo_name text NOT NULL, drive_folder_id text NOT NULL,
 currency char(3) NOT NULL DEFAULT 'USD', active_scope_id uuid,
 lock_version bigint NOT NULL DEFAULT 0,
 execution_lease_owner text, execution_lease_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE scope_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES projects(id),
 version integer NOT NULL CHECK (version>0), normalized_scope jsonb NOT NULL,
 content_hash text NOT NULL, document_id text, provider_revision text,
 status text NOT NULL CHECK (status IN ('draft','accepted_pending_sync','active','superseded')),
 created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(project_id,version)
);
ALTER TABLE projects ADD CONSTRAINT active_scope_fk FOREIGN KEY(active_scope_id) REFERENCES scope_versions(id);
CREATE UNIQUE INDEX one_active_scope ON scope_versions(project_id) WHERE status='active';
CREATE TABLE cases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES projects(id),
 mailbox_id text NOT NULL, message_id text NOT NULL, thread_id text,
 request_excerpt text NOT NULL, state text NOT NULL,
 evidence_version integer NOT NULL DEFAULT 1, row_version bigint NOT NULL DEFAULT 0,
 recommendation jsonb, last_error_code text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(mailbox_id,message_id),
 CHECK (state IN ('received','investigating','awaiting_manager','awaiting_client','accepted_pending_sync','applying','completed','clarification_required','rejected','expired','blocked','partially_applied'))
);
CREATE TABLE evidence (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid NOT NULL REFERENCES cases(id),
 evidence_version integer NOT NULL, provider text NOT NULL, resource_id text NOT NULL,
 provider_revision text, content_hash text NOT NULL, excerpt text NOT NULL,
 safe_url text, retrieved_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE proposals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid NOT NULL REFERENCES cases(id),
 version integer NOT NULL CHECK(version>0), baseline_scope_id uuid NOT NULL REFERENCES scope_versions(id),
 evidence_version integer NOT NULL, payload jsonb NOT NULL, payload_hash text NOT NULL,
 status text NOT NULL CHECK(status IN ('draft','published','accepted','rejected','expired','superseded')),
 published_at timestamptz, expires_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(case_id,version)
);
CREATE UNIQUE INDEX one_published_proposal ON proposals(case_id) WHERE status='published';
CREATE TABLE auth_challenges (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES projects(id),
 proposal_id uuid REFERENCES proposals(id), actor_email text NOT NULL,
 actor_role text NOT NULL CHECK(actor_role IN ('manager','client')),
 stage text NOT NULL, secret_hash text NOT NULL,
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 expires_at timestamptz NOT NULL, consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE review_tokens (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), challenge_id uuid NOT NULL REFERENCES auth_challenges(id),
 case_id uuid NOT NULL REFERENCES cases(id), proposal_id uuid REFERENCES proposals(id),
 actor_email text NOT NULL, actor_role text NOT NULL CHECK(actor_role IN ('manager','client')),
 stage text NOT NULL, token_hash text NOT NULL UNIQUE, expected_payload_hash text,
 expires_at timestamptz NOT NULL, consumed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid NOT NULL REFERENCES cases(id),
 proposal_id uuid REFERENCES proposals(id), review_token_id uuid NOT NULL UNIQUE REFERENCES review_tokens(id),
 actor_email text NOT NULL, actor_role text NOT NULL, stage text NOT NULL,
 decision text NOT NULL, option_id text, payload_hash text NOT NULL,
 comment text, decided_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_client_final_choice ON decisions(proposal_id)
 WHERE actor_role='client' AND decision IN ('accept','reject');
CREATE TABLE actions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid NOT NULL REFERENCES cases(id),
 proposal_id uuid REFERENCES proposals(id), decision_id uuid NOT NULL REFERENCES decisions(id),
 business_key text NOT NULL UNIQUE, action_kind text NOT NULL, provider text NOT NULL,
 resource_id text, expected_hash text, approved_payload jsonb NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','running','verified','retryable','unknown','blocked')),
 attempt_count integer NOT NULL DEFAULT 0, next_attempt_at timestamptz,
 lease_owner text, lease_until timestamptz, provider_receipt jsonb,
 verification jsonb, last_error_code text,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), case_id uuid NOT NULL REFERENCES cases(id),
 proposal_id uuid REFERENCES proposals(id), business_key text NOT NULL UNIQUE,
 recipient text NOT NULL, template_id text NOT NULL, approved_content jsonb NOT NULL,
 state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','running','sent','unknown','blocked')),
 provider_message_id text, mail_marker text NOT NULL UNIQUE, attempt_count integer NOT NULL DEFAULT 0,
 next_attempt_at timestamptz, lease_owner text, lease_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE audit_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, case_id uuid REFERENCES cases(id),
 correlation_id text NOT NULL, actor_role text NOT NULL, event_type text NOT NULL,
 safe_details jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX case_project_state_idx ON cases(project_id,state);
CREATE INDEX action_due_idx ON actions(state,next_attempt_at);
CREATE INDEX notification_due_idx ON notifications(state,next_attempt_at);
CREATE INDEX evidence_case_idx ON evidence(case_id,evidence_version);
COMMIT;
-- Next: implement routines that enforce project consistency, immutable published payloads,
-- authorization, rate limits, decision consumption, scope activation and worker leases.
-- Do not grant general table write privileges to public webhooks or the agent.
