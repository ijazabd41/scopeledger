-- ScopeLedger privileged routines and invariants.
-- Apply after ../../schema.sql with a migration role on PostgreSQL 14+.
-- Application callers should receive EXECUTE only on the routines they need.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
SET search_path TO scopeledger, public;

ALTER TABLE auth_challenges
  ADD COLUMN IF NOT EXISTS request_ip_hash text;

ALTER TABLE actions
  ADD COLUMN IF NOT EXISTS reconciled_at timestamptz;

ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS auth_challenge_actor_recent_idx
  ON auth_challenges(project_id, actor_email, created_at DESC);
CREATE INDEX IF NOT EXISTS auth_challenge_ip_recent_idx
  ON auth_challenges(request_ip_hash, created_at DESC)
  WHERE request_ip_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS review_token_case_idx
  ON review_tokens(case_id, stage, created_at DESC);

CREATE OR REPLACE FUNCTION canonical_jsonb_hash(p_value jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
  SELECT encode(digest(convert_to(p_value::text, 'UTF8'), 'sha256'), 'hex')
$$;

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS cases_touch_updated_at ON cases;
CREATE TRIGGER cases_touch_updated_at
BEFORE UPDATE ON cases
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS actions_touch_updated_at ON actions;
CREATE TRIGGER actions_touch_updated_at
BEFORE UPDATE ON actions
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

DROP TRIGGER IF EXISTS notifications_touch_updated_at ON notifications;
CREATE TRIGGER notifications_touch_updated_at
BEFORE UPDATE ON notifications
FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE OR REPLACE FUNCTION protect_published_proposal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status <> 'draft' AND (
    NEW.case_id IS DISTINCT FROM OLD.case_id OR
    NEW.version IS DISTINCT FROM OLD.version OR
    NEW.baseline_scope_id IS DISTINCT FROM OLD.baseline_scope_id OR
    NEW.evidence_version IS DISTINCT FROM OLD.evidence_version OR
    NEW.payload IS DISTINCT FROM OLD.payload OR
    NEW.payload_hash IS DISTINCT FROM OLD.payload_hash OR
    NEW.published_at IS DISTINCT FROM OLD.published_at OR
    NEW.expires_at IS DISTINCT FROM OLD.expires_at
  ) THEN
    RAISE EXCEPTION USING
      ERRCODE = 'SL003',
      MESSAGE = 'published proposal content is immutable';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS proposals_immutable_after_publish ON proposals;
CREATE TRIGGER proposals_immutable_after_publish
BEFORE UPDATE ON proposals
FOR EACH ROW EXECUTE FUNCTION protect_published_proposal();

CREATE OR REPLACE FUNCTION protect_decision()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = 'SL003', MESSAGE = 'decisions are append-only';
END;
$$;

DROP TRIGGER IF EXISTS decisions_append_only_update ON decisions;
CREATE TRIGGER decisions_append_only_update
BEFORE UPDATE ON decisions
FOR EACH ROW EXECUTE FUNCTION protect_decision();
DROP TRIGGER IF EXISTS decisions_append_only_delete ON decisions;
CREATE TRIGGER decisions_append_only_delete
BEFORE DELETE ON decisions
FOR EACH ROW EXECUTE FUNCTION protect_decision();

CREATE OR REPLACE FUNCTION protect_audit_event()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION USING ERRCODE = 'SL003', MESSAGE = 'audit events are append-only';
END;
$$;

DROP TRIGGER IF EXISTS audit_events_append_only_update ON audit_events;
CREATE TRIGGER audit_events_append_only_update
BEFORE UPDATE ON audit_events
FOR EACH ROW EXECUTE FUNCTION protect_audit_event();
DROP TRIGGER IF EXISTS audit_events_append_only_delete ON audit_events;
CREATE TRIGGER audit_events_append_only_delete
BEFORE DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION protect_audit_event();

CREATE OR REPLACE FUNCTION validate_proposal_payload(p_payload jsonb, p_currency char(3))
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_option jsonb;
  v_action jsonb;
  v_option_ids text[] := ARRAY[]::text[];
BEGIN
  IF jsonb_typeof(p_payload) <> 'object'
     OR jsonb_typeof(p_payload->'options') <> 'array'
     OR jsonb_array_length(p_payload->'options') < 1
     OR jsonb_array_length(p_payload->'options') > 5 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal must contain 1 to 5 options';
  END IF;

  IF upper(coalesce(p_payload->>'currency', '')) <> p_currency THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal currency does not match project currency';
  END IF;

  FOR v_option IN SELECT value FROM jsonb_array_elements(p_payload->'options') LOOP
    IF coalesce(v_option->>'id', '') !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'
       OR v_option->>'kind' NOT IN ('charge','swap','goodwill','clarify','decline')
       OR length(coalesce(v_option->>'description', '')) NOT BETWEEN 1 AND 1200 THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal option has invalid id, kind, or description';
    END IF;
    IF v_option->>'id' = ANY(v_option_ids) THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal option ids must be unique';
    END IF;
    v_option_ids := array_append(v_option_ids, v_option->>'id');

    IF jsonb_typeof(v_option->'normalized_scope') <> 'object'
       OR jsonb_typeof(v_option->'actions') <> 'array' THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'each option requires normalized_scope and actions';
    END IF;
    IF (v_option->>'price_minor') IS NULL
       OR (v_option->>'price_minor') !~ '^[0-9]+$' THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'price_minor must be a non-negative integer';
    END IF;
    IF v_option->>'kind' IN ('swap','goodwill') AND (v_option->>'price_minor')::bigint <> 0 THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'swap and goodwill options must have zero additional fee';
    END IF;

    FOR v_action IN SELECT value FROM jsonb_array_elements(v_option->'actions') LOOP
      IF v_action->>'provider' NOT IN ('github','google_docs')
         OR v_action->>'action_kind' NOT IN (
           'github_issue_create','github_issue_supersede',
           'scope_document_create','scope_document_fill','scope_document_verify'
         )
         OR coalesce(v_action->>'business_suffix', '') !~ '^[A-Za-z0-9][A-Za-z0-9:_-]{0,127}$'
         OR jsonb_typeof(v_action->'approved_payload') <> 'object' THEN
        RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal contains an unsupported or malformed action';
      END IF;
    END LOOP;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION create_proposal_draft(
  p_case_id uuid,
  p_payload jsonb,
  p_expires_at timestamptz
)
RETURNS TABLE(proposal_id uuid, proposal_version integer, payload_hash text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_case cases%ROWTYPE;
  v_project projects%ROWTYPE;
  v_version integer;
  v_id uuid;
  v_hash text;
BEGIN
  SELECT * INTO v_case FROM cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'case not found';
  END IF;
  SELECT * INTO v_project FROM projects WHERE id = v_case.project_id FOR UPDATE;
  IF v_project.active_scope_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'project has no active scope';
  END IF;
  IF v_case.state NOT IN ('awaiting_manager','investigating') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'case is not ready for a proposal draft';
  END IF;
  IF p_expires_at <= now() OR p_expires_at > now() + interval '14 days' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal expiry is outside the permitted window';
  END IF;
  PERFORM validate_proposal_payload(p_payload, v_project.currency);

  UPDATE proposals SET status = 'superseded'
   WHERE case_id = p_case_id AND status = 'draft';
  SELECT coalesce(max(version), 0) + 1 INTO v_version FROM proposals WHERE case_id = p_case_id;
  v_hash := canonical_jsonb_hash(p_payload);
  INSERT INTO proposals(case_id, version, baseline_scope_id, evidence_version,
                        payload, payload_hash, status, expires_at)
  VALUES (p_case_id, v_version, v_project.active_scope_id, v_case.evidence_version,
          p_payload, v_hash, 'draft', p_expires_at)
  RETURNING id INTO v_id;

  RETURN QUERY SELECT v_id, v_version, v_hash;
END;
$$;

CREATE OR REPLACE FUNCTION issue_auth_challenge(
  p_project_id uuid,
  p_proposal_id uuid,
  p_actor_role text,
  p_stage text,
  p_request_ip_hash text DEFAULT NULL
)
RETURNS TABLE(challenge_id uuid, delivery_email text, one_time_code text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_project projects%ROWTYPE;
  v_proposal proposals%ROWTYPE;
  v_email text;
  v_code text;
  v_salt text;
  v_id uuid;
  v_expires timestamptz := now() + interval '10 minutes';
BEGIN
  SELECT * INTO v_project FROM projects WHERE id = p_project_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'project not found';
  END IF;
  IF p_actor_role = 'manager' THEN
    v_email := lower(v_project.manager_email);
    IF p_stage NOT IN ('manager_publish','manager_review','operator_recovery') THEN
      RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'invalid manager authorization stage';
    END IF;
  ELSIF p_actor_role = 'client' THEN
    v_email := lower(v_project.client_email);
    IF p_stage <> 'client_decision' THEN
      RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'invalid client authorization stage';
    END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'invalid actor role';
  END IF;

  IF p_proposal_id IS NOT NULL THEN
    SELECT p.* INTO v_proposal
      FROM proposals p JOIN cases c ON c.id = p.case_id
     WHERE p.id = p_proposal_id AND c.project_id = p_project_id;
    IF NOT FOUND OR (p_actor_role = 'client' AND v_proposal.status <> 'published') THEN
      RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'proposal is not available for this actor';
    END IF;
  ELSIF p_stage IN ('manager_publish','client_decision') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal is required for this stage';
  END IF;

  IF EXISTS (
    SELECT 1 FROM auth_challenges
     WHERE project_id = p_project_id AND actor_email = v_email
       AND created_at > now() - interval '60 seconds'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'SL006', MESSAGE = 'authorization code resend cooldown active';
  END IF;
  IF (SELECT count(*) FROM auth_challenges
       WHERE project_id = p_project_id AND actor_email = v_email
         AND created_at > now() - interval '1 hour') >= 10 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL006', MESSAGE = 'actor authorization rate limit exceeded';
  END IF;
  IF p_request_ip_hash IS NOT NULL AND
     (SELECT count(*) FROM auth_challenges
       WHERE request_ip_hash = p_request_ip_hash
         AND created_at > now() - interval '1 hour') >= 30 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL006', MESSAGE = 'network authorization rate limit exceeded';
  END IF;
  IF (SELECT count(*) FROM auth_challenges WHERE created_at > now() - interval '1 minute') >= 100 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL006', MESSAGE = 'global authorization rate limit exceeded';
  END IF;

  UPDATE auth_challenges SET consumed_at = now()
   WHERE project_id = p_project_id AND actor_email = v_email
     AND actor_role = p_actor_role AND stage = p_stage AND consumed_at IS NULL;

  v_code := lpad((('x' || substr(encode(gen_random_bytes(4), 'hex'), 1, 8))::bit(32)::bigint % 1000000)::text, 6, '0');
  v_salt := encode(gen_random_bytes(16), 'hex');
  INSERT INTO auth_challenges(project_id, proposal_id, actor_email, actor_role, stage,
                              secret_hash, expires_at, request_ip_hash)
  VALUES (p_project_id, p_proposal_id, v_email, p_actor_role, p_stage,
          v_salt || ':' || encode(digest(convert_to(v_salt || ':' || v_code, 'UTF8'), 'sha256'), 'hex'),
          v_expires, p_request_ip_hash)
  RETURNING id INTO v_id;

  RETURN QUERY SELECT v_id, v_email, v_code, v_expires;
END;
$$;

CREATE OR REPLACE FUNCTION verify_auth_challenge(
  p_challenge_id uuid,
  p_code text
)
RETURNS TABLE(review_token text, token_expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_challenge auth_challenges%ROWTYPE;
  v_case_id uuid;
  v_payload_hash text;
  v_salt text;
  v_calculated text;
  v_raw_token text;
  v_expiry timestamptz := now() + interval '15 minutes';
BEGIN
  SELECT * INTO v_challenge FROM auth_challenges WHERE id = p_challenge_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'authorization challenge not found';
  END IF;
  IF v_challenge.consumed_at IS NOT NULL OR v_challenge.expires_at <= now() OR v_challenge.attempts >= 5 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'authorization challenge is expired or consumed';
  END IF;
  UPDATE auth_challenges SET attempts = attempts + 1 WHERE id = p_challenge_id;
  IF p_code !~ '^[0-9]{6}$' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'authorization code is invalid';
  END IF;
  v_salt := split_part(v_challenge.secret_hash, ':', 1);
  v_calculated := v_salt || ':' || encode(digest(convert_to(v_salt || ':' || p_code, 'UTF8'), 'sha256'), 'hex');
  IF v_calculated <> v_challenge.secret_hash THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'authorization code is invalid';
  END IF;

  IF v_challenge.proposal_id IS NOT NULL THEN
    SELECT p.case_id, p.payload_hash INTO v_case_id, v_payload_hash
      FROM proposals p JOIN cases c ON c.id = p.case_id
     WHERE p.id = v_challenge.proposal_id AND c.project_id = v_challenge.project_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'proposal no longer belongs to the project';
    END IF;
  ELSE
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'proposal-bound token required';
  END IF;

  UPDATE auth_challenges SET consumed_at = now() WHERE id = p_challenge_id;
  v_raw_token := encode(gen_random_bytes(32), 'hex');
  INSERT INTO review_tokens(challenge_id, case_id, proposal_id, actor_email, actor_role,
                            stage, token_hash, expected_payload_hash, expires_at)
  VALUES (p_challenge_id, v_case_id, v_challenge.proposal_id, v_challenge.actor_email,
          v_challenge.actor_role, v_challenge.stage,
          encode(digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex'),
          v_payload_hash, v_expiry);
  RETURN QUERY SELECT v_raw_token, v_expiry;
END;
$$;

CREATE OR REPLACE FUNCTION publish_proposal(
  p_review_token text,
  p_proposal_id uuid,
  p_expected_case_version bigint,
  p_correlation_id text
)
RETURNS TABLE(proposal_id uuid, proposal_version integer, payload_hash text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_token_hash text := encode(digest(convert_to(p_review_token, 'UTF8'), 'sha256'), 'hex');
  v_token_hint review_tokens%ROWTYPE;
  v_project projects%ROWTYPE;
  v_case cases%ROWTYPE;
  v_proposal proposals%ROWTYPE;
  v_token review_tokens%ROWTYPE;
BEGIN
  SELECT * INTO v_token_hint FROM review_tokens WHERE token_hash = v_token_hash;
  IF NOT FOUND OR v_token_hint.proposal_id <> p_proposal_id THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'review token is invalid';
  END IF;
  SELECT pr.* INTO v_project FROM projects pr
    JOIN cases c ON c.project_id = pr.id WHERE c.id = v_token_hint.case_id FOR UPDATE OF pr;
  SELECT * INTO v_case FROM cases WHERE id = v_token_hint.case_id FOR UPDATE;
  SELECT * INTO v_proposal FROM proposals WHERE id = p_proposal_id FOR UPDATE;
  SELECT * INTO v_token FROM review_tokens WHERE id = v_token_hint.id FOR UPDATE;

  IF v_token.actor_role <> 'manager' OR v_token.stage <> 'manager_publish'
     OR lower(v_token.actor_email) <> lower(v_project.manager_email)
     OR v_token.consumed_at IS NOT NULL OR v_token.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'manager authorization is invalid or expired';
  END IF;
  IF v_case.row_version <> p_expected_case_version OR v_case.state <> 'awaiting_manager'
     OR v_proposal.status <> 'draft' OR v_proposal.case_id <> v_case.id
     OR v_proposal.baseline_scope_id <> v_project.active_scope_id
     OR v_proposal.evidence_version <> v_case.evidence_version
     OR v_token.expected_payload_hash <> v_proposal.payload_hash
     OR v_proposal.payload_hash <> canonical_jsonb_hash(v_proposal.payload)
     OR v_proposal.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'proposal, evidence, case, or baseline is stale';
  END IF;
  PERFORM validate_proposal_payload(v_proposal.payload, v_project.currency);

  UPDATE proposals SET status = 'superseded'
   WHERE case_id = v_case.id AND status = 'published' AND id <> v_proposal.id;
  UPDATE proposals SET status = 'published', published_at = now() WHERE id = v_proposal.id;
  UPDATE review_tokens SET consumed_at = now() WHERE id = v_token.id;
  UPDATE cases SET state = 'awaiting_client', row_version = row_version + 1 WHERE id = v_case.id;
  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  VALUES (v_case.id, p_correlation_id, 'manager', 'proposal_published',
          jsonb_build_object('proposal_id', v_proposal.id, 'version', v_proposal.version));

  RETURN QUERY SELECT v_proposal.id, v_proposal.version, v_proposal.payload_hash, v_proposal.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION decide_proposal(
  p_review_token text,
  p_proposal_id uuid,
  p_proposal_version integer,
  p_payload_hash text,
  p_decision text,
  p_option_id text,
  p_comment text,
  p_correlation_id text
)
RETURNS TABLE(decision_id uuid, case_id uuid, case_state text, receipt_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_token_hash text := encode(digest(convert_to(p_review_token, 'UTF8'), 'sha256'), 'hex');
  v_hint review_tokens%ROWTYPE;
  v_project projects%ROWTYPE;
  v_case cases%ROWTYPE;
  v_proposal proposals%ROWTYPE;
  v_token review_tokens%ROWTYPE;
  v_existing decisions%ROWTYPE;
  v_option jsonb;
  v_action jsonb;
  v_decision_id uuid;
  v_scope_id uuid;
  v_scope_version integer;
  v_state text;
BEGIN
  IF p_decision NOT IN ('accept','reject','clarify') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'unsupported client decision';
  END IF;
  SELECT * INTO v_hint FROM review_tokens WHERE token_hash = v_token_hash;
  IF NOT FOUND OR v_hint.proposal_id <> p_proposal_id THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'review token is invalid';
  END IF;

  SELECT pr.* INTO v_project FROM projects pr
    JOIN cases c ON c.project_id = pr.id WHERE c.id = v_hint.case_id FOR UPDATE OF pr;
  SELECT * INTO v_case FROM cases WHERE id = v_hint.case_id FOR UPDATE;
  SELECT * INTO v_proposal FROM proposals WHERE id = p_proposal_id FOR UPDATE;
  SELECT * INTO v_token FROM review_tokens WHERE id = v_hint.id FOR UPDATE;

  SELECT * INTO v_existing FROM decisions WHERE review_token_id = v_token.id;
  IF FOUND THEN
    IF v_existing.decision = p_decision
       AND coalesce(v_existing.option_id, '') = coalesce(p_option_id, '')
       AND v_existing.payload_hash = p_payload_hash THEN
      RETURN QUERY SELECT v_existing.id, v_existing.case_id, v_case.state, 'duplicate_receipt'::text;
      RETURN;
    END IF;
    RAISE EXCEPTION USING ERRCODE = 'SL007', MESSAGE = 'a conflicting decision already exists';
  END IF;

  IF v_token.actor_role <> 'client' OR v_token.stage <> 'client_decision'
     OR lower(v_token.actor_email) <> lower(v_project.client_email)
     OR v_token.consumed_at IS NOT NULL OR v_token.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'client authorization is invalid or expired';
  END IF;
  IF v_proposal.case_id <> v_case.id OR v_proposal.status <> 'published'
     OR v_case.state <> 'awaiting_client'
     OR v_proposal.version <> p_proposal_version
     OR v_proposal.payload_hash <> p_payload_hash
     OR v_token.expected_payload_hash <> v_proposal.payload_hash
     OR v_proposal.payload_hash <> canonical_jsonb_hash(v_proposal.payload)
     OR v_proposal.expires_at <= now()
     OR v_proposal.baseline_scope_id <> v_project.active_scope_id
     OR v_proposal.evidence_version <> v_case.evidence_version THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'proposal, evidence, or baseline is stale';
  END IF;
  IF EXISTS (
    SELECT 1 FROM cases c
     WHERE c.project_id = v_project.id AND c.id <> v_case.id
       AND c.state IN ('accepted_pending_sync','applying','partially_applied')
  ) THEN
    RAISE EXCEPTION USING ERRCODE = 'SL007', MESSAGE = 'another accepted project change is unresolved';
  END IF;

  IF p_decision = 'accept' THEN
    SELECT value INTO v_option FROM jsonb_array_elements(v_proposal.payload->'options')
     WHERE value->>'id' = p_option_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'selected option is not in the published proposal';
    END IF;
  ELSIF p_option_id IS NOT NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'option_id is only valid for acceptance';
  END IF;

  INSERT INTO decisions(case_id, proposal_id, review_token_id, actor_email, actor_role,
                        stage, decision, option_id, payload_hash, comment)
  VALUES (v_case.id, v_proposal.id, v_token.id, v_token.actor_email, 'client',
          'client_decision', p_decision, p_option_id, v_proposal.payload_hash,
          nullif(left(coalesce(p_comment, ''), 2000), ''))
  RETURNING id INTO v_decision_id;
  UPDATE review_tokens SET consumed_at = now() WHERE id = v_token.id;

  IF p_decision = 'accept' THEN
    SELECT coalesce(max(version), 0) + 1 INTO v_scope_version
      FROM scope_versions WHERE project_id = v_project.id;
    INSERT INTO scope_versions(project_id, version, normalized_scope, content_hash, status)
    VALUES (v_project.id, v_scope_version, v_option->'normalized_scope',
            canonical_jsonb_hash(v_option->'normalized_scope'), 'accepted_pending_sync')
    RETURNING id INTO v_scope_id;

    FOR v_action IN SELECT value FROM jsonb_array_elements(v_option->'actions') LOOP
      INSERT INTO actions(case_id, proposal_id, decision_id, business_key, action_kind,
                          provider, resource_id, expected_hash, approved_payload)
      VALUES (v_case.id, v_proposal.id, v_decision_id,
              format('%s:%s:%s:%s', v_project.id, v_case.id, v_proposal.version,
                     v_action->>'business_suffix'),
              v_action->>'action_kind', v_action->>'provider',
              nullif(v_action->>'resource_id', ''), nullif(v_action->>'expected_hash', ''),
              v_action->'approved_payload');
    END LOOP;
    UPDATE proposals SET status = 'accepted' WHERE id = v_proposal.id;
    UPDATE cases SET state = 'accepted_pending_sync', row_version = row_version + 1 WHERE id = v_case.id;
    v_state := 'accepted_pending_sync';
  ELSIF p_decision = 'reject' THEN
    UPDATE proposals SET status = 'rejected' WHERE id = v_proposal.id;
    UPDATE cases SET state = 'rejected', row_version = row_version + 1 WHERE id = v_case.id;
    v_state := 'rejected';
  ELSE
    UPDATE proposals SET status = 'superseded' WHERE id = v_proposal.id;
    UPDATE cases SET state = 'clarification_required', row_version = row_version + 1 WHERE id = v_case.id;
    v_state := 'clarification_required';
  END IF;
  UPDATE projects SET lock_version = lock_version + 1 WHERE id = v_project.id;
  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  VALUES (v_case.id, p_correlation_id, 'client', 'proposal_' || p_decision,
          jsonb_build_object('proposal_id', v_proposal.id, 'version', v_proposal.version,
                             'option_id', p_option_id, 'decision_id', v_decision_id));
  RETURN QUERY SELECT v_decision_id, v_case.id, v_state, 'recorded'::text;
END;
$$;

CREATE OR REPLACE FUNCTION claim_next_action(
  p_worker_id text,
  p_lease_seconds integer DEFAULT 120
)
RETURNS SETOF actions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_action actions%ROWTYPE;
  v_project_id uuid;
BEGIN
  IF length(coalesce(p_worker_id, '')) NOT BETWEEN 1 AND 200
     OR p_lease_seconds NOT BETWEEN 30 AND 900 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'invalid worker lease request';
  END IF;
  SELECT a.* INTO v_action
    FROM actions a JOIN cases c ON c.id = a.case_id
   WHERE a.state IN ('pending','retryable')
     AND coalesce(a.next_attempt_at, '-infinity'::timestamptz) <= now()
     AND NOT EXISTS (
       SELECT 1 FROM actions prior
        WHERE prior.case_id = a.case_id AND prior.id <> a.id
          AND prior.created_at < a.created_at AND prior.state <> 'verified'
     )
   ORDER BY a.created_at, a.id
   FOR UPDATE OF a SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;

  SELECT c.project_id INTO v_project_id FROM cases c WHERE c.id = v_action.case_id;
  UPDATE projects SET execution_lease_owner = p_worker_id,
                      execution_lease_until = now() + make_interval(secs => p_lease_seconds)
   WHERE id = v_project_id
     AND (execution_lease_until IS NULL OR execution_lease_until <= now()
          OR execution_lease_owner = p_worker_id);
  IF NOT FOUND THEN RETURN; END IF;

  UPDATE actions SET state = 'running', lease_owner = p_worker_id,
                     lease_until = now() + make_interval(secs => p_lease_seconds),
                     attempt_count = attempt_count + 1
   WHERE id = v_action.id RETURNING * INTO v_action;
  UPDATE cases SET state = 'applying' WHERE id = v_action.case_id
    AND state = 'accepted_pending_sync';
  RETURN NEXT v_action;
END;
$$;

CREATE OR REPLACE FUNCTION record_action_result(
  p_action_id uuid,
  p_worker_id text,
  p_outcome text,
  p_provider_receipt jsonb DEFAULT NULL,
  p_verification jsonb DEFAULT NULL,
  p_error_code text DEFAULT NULL,
  p_retry_after timestamptz DEFAULT NULL
)
RETURNS actions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_action actions%ROWTYPE;
BEGIN
  SELECT * INTO v_action FROM actions WHERE id = p_action_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'action not found'; END IF;
  IF v_action.state <> 'running' OR v_action.lease_owner <> p_worker_id OR v_action.lease_until <= now() THEN
    RAISE EXCEPTION USING ERRCODE = 'SL008', MESSAGE = 'worker does not hold the active action lease';
  END IF;
  IF p_outcome NOT IN ('verified','retryable','unknown','blocked') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'invalid action outcome';
  END IF;
  IF p_outcome = 'verified' AND (p_verification IS NULL OR jsonb_typeof(p_verification) <> 'object') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'verified action requires independent verification';
  END IF;
  UPDATE actions SET state = p_outcome, provider_receipt = coalesce(p_provider_receipt, provider_receipt),
                     verification = CASE WHEN p_outcome = 'verified' THEN p_verification ELSE verification END,
                     last_error_code = p_error_code, next_attempt_at = p_retry_after,
                     lease_owner = NULL, lease_until = NULL,
                     reconciled_at = CASE WHEN p_outcome IN ('verified','retryable') THEN now() ELSE reconciled_at END
   WHERE id = p_action_id RETURNING * INTO v_action;
  RETURN v_action;
END;
$$;

CREATE OR REPLACE FUNCTION finalize_verified_case(
  p_case_id uuid,
  p_document_id text,
  p_provider_revision text,
  p_correlation_id text
)
RETURNS TABLE(scope_version_id uuid, completed_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_case cases%ROWTYPE;
  v_project projects%ROWTYPE;
  v_scope scope_versions%ROWTYPE;
  v_now timestamptz := now();
BEGIN
  SELECT * INTO v_case FROM cases WHERE id = p_case_id;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'case not found'; END IF;
  SELECT * INTO v_project FROM projects WHERE id = v_case.project_id FOR UPDATE;
  SELECT * INTO v_case FROM cases WHERE id = p_case_id FOR UPDATE;
  IF v_case.state NOT IN ('applying','partially_applied') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'case is not applying';
  END IF;
  IF EXISTS (SELECT 1 FROM actions WHERE case_id = p_case_id AND state <> 'verified')
     OR NOT EXISTS (SELECT 1 FROM actions WHERE case_id = p_case_id) THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'not all mandatory actions are verified';
  END IF;
  SELECT sv.* INTO v_scope FROM scope_versions sv
    JOIN decisions d ON d.case_id = p_case_id AND d.decision = 'accept'
   WHERE sv.project_id = v_project.id AND sv.status = 'accepted_pending_sync'
   ORDER BY sv.version DESC LIMIT 1 FOR UPDATE OF sv;
  IF NOT FOUND OR length(coalesce(p_document_id, '')) < 1 OR length(coalesce(p_provider_revision, '')) < 1 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'pending scope and verified document identity are required';
  END IF;
  UPDATE scope_versions SET status = 'superseded'
   WHERE project_id = v_project.id AND status = 'active';
  UPDATE scope_versions SET status = 'active', document_id = p_document_id,
                            provider_revision = p_provider_revision
   WHERE id = v_scope.id;
  UPDATE projects SET active_scope_id = v_scope.id, lock_version = lock_version + 1,
                      execution_lease_owner = NULL, execution_lease_until = NULL
   WHERE id = v_project.id;
  UPDATE cases SET state = 'completed', row_version = row_version + 1 WHERE id = p_case_id;
  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  VALUES (p_case_id, p_correlation_id, 'executor', 'execution_completed',
          jsonb_build_object('scope_version_id', v_scope.id, 'document_id', p_document_id));
  RETURN QUERY SELECT v_scope.id, v_now;
END;
$$;

CREATE OR REPLACE FUNCTION claim_next_notification(
  p_worker_id text,
  p_lease_seconds integer DEFAULT 120
)
RETURNS SETOF notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_notification notifications%ROWTYPE;
BEGIN
  IF length(coalesce(p_worker_id, '')) NOT BETWEEN 1 AND 200
     OR p_lease_seconds NOT BETWEEN 30 AND 900 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'invalid worker lease request';
  END IF;
  SELECT * INTO v_notification FROM notifications
   WHERE state = 'pending' AND coalesce(next_attempt_at, '-infinity'::timestamptz) <= now()
   ORDER BY created_at, id FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE notifications SET state = 'running', lease_owner = p_worker_id,
                           lease_until = now() + make_interval(secs => p_lease_seconds),
                           attempt_count = attempt_count + 1
   WHERE id = v_notification.id RETURNING * INTO v_notification;
  RETURN NEXT v_notification;
END;
$$;

CREATE OR REPLACE FUNCTION expire_due_proposals(p_correlation_id text DEFAULT 'scheduled-expiry')
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_count integer;
BEGIN
  WITH due AS (
    SELECT p.id, p.case_id FROM proposals p JOIN cases c ON c.id = p.case_id
     WHERE p.status = 'published' AND p.expires_at <= now() AND c.state = 'awaiting_client'
     FOR UPDATE OF p, c SKIP LOCKED
  ), updated_proposals AS (
    UPDATE proposals p SET status = 'expired' FROM due d WHERE p.id = d.id RETURNING p.case_id
  ), updated_cases AS (
    UPDATE cases c SET state = 'expired', row_version = row_version + 1
     FROM updated_proposals u WHERE c.id = u.case_id RETURNING c.id
  )
  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  SELECT id, p_correlation_id, 'scheduler', 'proposal_expired', '{}'::jsonb FROM updated_cases;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION create_proposal_draft(uuid,jsonb,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION issue_auth_challenge(uuid,uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION verify_auth_challenge(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION publish_proposal(text,uuid,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION decide_proposal(text,uuid,integer,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION claim_next_action(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_action_result(uuid,text,text,jsonb,jsonb,text,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION finalize_verified_case(uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION claim_next_notification(text,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION expire_due_proposals(text) FROM PUBLIC;

COMMIT;
