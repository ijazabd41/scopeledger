-- ScopePilot Migration 005: secure workflow-facing approval boundaries
-- Separates OTP issuance/delivery from OTP verification and the authorized write.

\set ON_ERROR_STOP on
BEGIN;
SET search_path TO scopeledger, public;

ALTER TABLE auth_challenges
  ADD COLUMN IF NOT EXISTS expected_case_version bigint;

CREATE OR REPLACE FUNCTION ingest_email_case(
  p_mailbox_id text,
  p_message_id text,
  p_thread_id text,
  p_sender_email text,
  p_subject text,
  p_body text
)
RETURNS TABLE(
  case_id uuid,
  project_id uuid,
  case_state text,
  deduplicated boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_project_ids uuid[];
  v_case_id uuid;
  v_state text;
  v_existing boolean;
BEGIN
  IF nullif(trim(p_mailbox_id), '') IS NULL OR nullif(trim(p_message_id), '') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'mailbox and provider message id are required';
  END IF;
  IF nullif(trim(p_sender_email), '') IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'sender email is required';
  END IF;

  SELECT array_agg(id ORDER BY id::text)
    INTO v_project_ids
    FROM projects
   WHERE lower(client_email) = lower(trim(p_sender_email));

  IF coalesce(array_length(v_project_ids, 1), 0) <> 1 THEN
    RETURN QUERY SELECT NULL::uuid, NULL::uuid, 'blocked'::text, false;
    RETURN;
  END IF;

  SELECT c.id, c.state
    INTO v_case_id, v_state
    FROM cases c
   WHERE c.mailbox_id = p_mailbox_id AND c.message_id = p_message_id;
  v_existing := FOUND;

  IF NOT v_existing THEN
    INSERT INTO cases(project_id, mailbox_id, message_id, thread_id, request_excerpt, state)
    VALUES (
      v_project_ids[1], p_mailbox_id, p_message_id, nullif(p_thread_id, ''),
      left(coalesce(nullif(trim(p_subject), '') || E'\n', '') || coalesce(p_body, ''), 4000),
      'investigating'
    )
    RETURNING id, state INTO v_case_id, v_state;
  END IF;

  RETURN QUERY SELECT v_case_id, v_project_ids[1], v_state, v_existing;
END;
$$;

CREATE OR REPLACE FUNCTION record_investigation_result(
  p_case_id uuid,
  p_recommendation jsonb,
  p_evidence jsonb,
  p_correlation_id text
)
RETURNS TABLE(case_id uuid, case_state text, evidence_version integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_case cases%ROWTYPE;
  v_item jsonb;
BEGIN
  IF jsonb_typeof(p_recommendation) <> 'object'
     OR nullif(p_recommendation->>'classification', '') IS NULL
     OR jsonb_typeof(coalesce(p_recommendation->'recommended_options', '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'investigation recommendation is invalid';
  END IF;
  IF jsonb_typeof(p_evidence) <> 'array' OR jsonb_array_length(p_evidence) < 2 THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'scope and task evidence are required';
  END IF;

  SELECT * INTO v_case FROM cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'case not found';
  END IF;
  IF v_case.state NOT IN ('investigating', 'clarification_required') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'case is not open for investigation';
  END IF;

  DELETE FROM evidence e
   WHERE e.case_id = p_case_id AND e.evidence_version = v_case.evidence_version;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_evidence)
  LOOP
    IF nullif(v_item->>'provider', '') IS NULL OR nullif(v_item->>'resource_id', '') IS NULL THEN
      RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'evidence provider and resource id are required';
    END IF;
    INSERT INTO evidence(case_id, evidence_version, provider, resource_id, provider_revision,
                         content_hash, excerpt, safe_url)
    VALUES (
      p_case_id,
      v_case.evidence_version,
      v_item->>'provider',
      v_item->>'resource_id',
      nullif(v_item->>'provider_revision', ''),
      encode(digest(convert_to(coalesce(v_item->>'excerpt', ''), 'UTF8'), 'sha256'), 'hex'),
      left(coalesce(v_item->>'excerpt', ''), 4000),
      nullif(v_item->>'safe_url', '')
    );
  END LOOP;

  UPDATE cases
     SET recommendation = p_recommendation,
         state = 'awaiting_manager',
         row_version = row_version + 1,
         updated_at = now(),
         last_error_code = NULL
   WHERE id = p_case_id
   RETURNING * INTO v_case;

  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  VALUES (p_case_id, p_correlation_id, 'investigator', 'investigation_completed',
          jsonb_build_object('evidence_version', v_case.evidence_version,
                             'evidence_count', jsonb_array_length(p_evidence),
                             'classification', p_recommendation->>'classification'));

  RETURN QUERY SELECT v_case.id, v_case.state, v_case.evidence_version;
END;
$$;

CREATE OR REPLACE FUNCTION request_manager_publication(
  p_case_id uuid,
  p_payload jsonb,
  p_expires_at timestamptz,
  p_request_ip text DEFAULT NULL
)
RETURNS TABLE(
  challenge_id uuid,
  delivery_email text,
  one_time_code text,
  challenge_expires_at timestamptz,
  proposal_id uuid,
  proposal_version integer,
  payload_hash text,
  proposal_payload jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_case cases%ROWTYPE;
  v_proposal_id uuid;
  v_proposal_version integer;
  v_payload_hash text;
  v_challenge_id uuid;
  v_delivery_email text;
  v_code text;
  v_challenge_expires timestamptz;
  v_ip_hash text;
BEGIN
  SELECT * INTO v_case FROM cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'case not found';
  END IF;
  IF v_case.state <> 'awaiting_manager' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'case is not awaiting manager review';
  END IF;

  SELECT d.proposal_id, d.proposal_version, d.payload_hash
    INTO v_proposal_id, v_proposal_version, v_payload_hash
    FROM create_proposal_draft(p_case_id, p_payload, p_expires_at) d;

  v_ip_hash := CASE WHEN nullif(p_request_ip, '') IS NULL THEN NULL
                    ELSE encode(digest(convert_to(p_request_ip, 'UTF8'), 'sha256'), 'hex') END;

  SELECT c.challenge_id, c.delivery_email, c.one_time_code, c.expires_at
    INTO v_challenge_id, v_delivery_email, v_code, v_challenge_expires
    FROM issue_auth_challenge(
      v_case.project_id,
      v_proposal_id,
      'manager',
      'manager_publish',
      v_ip_hash
    ) c;

  UPDATE auth_challenges
     SET expected_case_version = v_case.row_version
   WHERE id = v_challenge_id;

  RETURN QUERY
  SELECT v_challenge_id, v_delivery_email, v_code, v_challenge_expires,
         v_proposal_id, v_proposal_version, v_payload_hash, p_payload;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_manager_publication(
  p_challenge_id uuid,
  p_code text,
  p_correlation_id text
)
RETURNS TABLE(
  proposal_id uuid,
  proposal_version integer,
  payload_hash text,
  expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_challenge auth_challenges%ROWTYPE;
  v_review_token text;
  v_token_expires timestamptz;
BEGIN
  SELECT * INTO v_challenge
    FROM auth_challenges
   WHERE id = p_challenge_id
   FOR UPDATE;

  IF NOT FOUND OR v_challenge.actor_role <> 'manager'
     OR v_challenge.stage <> 'manager_publish'
     OR v_challenge.proposal_id IS NULL
     OR v_challenge.expected_case_version IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'manager authorization challenge is invalid';
  END IF;

  SELECT v.review_token, v.token_expires_at
    INTO v_review_token, v_token_expires
    FROM verify_auth_challenge(p_challenge_id, p_code) v;

  RETURN QUERY
  SELECT p.proposal_id, p.proposal_version, p.payload_hash, p.expires_at
    FROM publish_proposal(
      v_review_token,
      v_challenge.proposal_id,
      v_challenge.expected_case_version,
      p_correlation_id
    ) p;
END;
$$;

CREATE OR REPLACE FUNCTION request_client_decision_challenge(
  p_proposal_id uuid,
  p_request_ip text DEFAULT NULL
)
RETURNS TABLE(
  challenge_id uuid,
  delivery_email text,
  one_time_code text,
  challenge_expires_at timestamptz,
  proposal_id uuid,
  proposal_version integer,
  payload_hash text,
  proposal_payload jsonb,
  proposal_expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_proposal proposals%ROWTYPE;
  v_case cases%ROWTYPE;
  v_challenge_id uuid;
  v_delivery_email text;
  v_code text;
  v_challenge_expires timestamptz;
  v_ip_hash text;
BEGIN
  SELECT * INTO v_proposal FROM proposals WHERE id = p_proposal_id;
  IF NOT FOUND OR v_proposal.status <> 'published' OR v_proposal.expires_at <= now() THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'proposal is not available for a decision';
  END IF;
  SELECT * INTO v_case FROM cases WHERE id = v_proposal.case_id;
  IF v_case.state <> 'awaiting_client' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'case is not awaiting a client decision';
  END IF;

  v_ip_hash := CASE WHEN nullif(p_request_ip, '') IS NULL THEN NULL
                    ELSE encode(digest(convert_to(p_request_ip, 'UTF8'), 'sha256'), 'hex') END;

  SELECT c.challenge_id, c.delivery_email, c.one_time_code, c.expires_at
    INTO v_challenge_id, v_delivery_email, v_code, v_challenge_expires
    FROM issue_auth_challenge(
      v_case.project_id,
      v_proposal.id,
      'client',
      'client_decision',
      v_ip_hash
    ) c;

  RETURN QUERY
  SELECT v_challenge_id, v_delivery_email, v_code, v_challenge_expires,
         v_proposal.id, v_proposal.version, v_proposal.payload_hash,
         v_proposal.payload, v_proposal.expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION confirm_client_decision(
  p_challenge_id uuid,
  p_code text,
  p_decision text,
  p_option_id text,
  p_comment text,
  p_correlation_id text
)
RETURNS TABLE(
  decision_id uuid,
  case_id uuid,
  case_state text,
  receipt_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_challenge auth_challenges%ROWTYPE;
  v_proposal proposals%ROWTYPE;
  v_review_token text;
  v_token_expires timestamptz;
BEGIN
  SELECT * INTO v_challenge
    FROM auth_challenges
   WHERE id = p_challenge_id
   FOR UPDATE;

  IF NOT FOUND OR v_challenge.actor_role <> 'client'
     OR v_challenge.stage <> 'client_decision'
     OR v_challenge.proposal_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = 'SL005', MESSAGE = 'client authorization challenge is invalid';
  END IF;

  SELECT * INTO v_proposal FROM proposals WHERE id = v_challenge.proposal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'proposal not found';
  END IF;

  SELECT v.review_token, v.token_expires_at
    INTO v_review_token, v_token_expires
    FROM verify_auth_challenge(p_challenge_id, p_code) v;

  RETURN QUERY
  SELECT d.decision_id, d.case_id, d.case_state, d.receipt_status
    FROM decide_proposal(
      v_review_token,
      v_proposal.id,
      v_proposal.version,
      v_proposal.payload_hash,
      p_decision,
      nullif(p_option_id, ''),
      nullif(p_comment, ''),
      p_correlation_id
    ) d;
END;
$$;

CREATE OR REPLACE FUNCTION complete_case_if_ready(
  p_case_id uuid,
  p_correlation_id text
)
RETURNS TABLE(
  finalized boolean,
  case_state text,
  scope_version_id uuid,
  completed_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_case cases%ROWTYPE;
  v_document_id text;
  v_provider_revision text;
  v_scope_id uuid;
  v_completed_at timestamptz;
BEGIN
  SELECT * INTO v_case FROM cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'case not found';
  END IF;

  IF v_case.state = 'completed' THEN
    SELECT sv.id, sv.created_at
      INTO v_scope_id, v_completed_at
      FROM projects p
      JOIN scope_versions sv ON sv.id = p.active_scope_id
     WHERE p.id = v_case.project_id;
    RETURN QUERY SELECT true, v_case.state, v_scope_id, v_completed_at;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM actions WHERE case_id = p_case_id AND state <> 'verified') THEN
    RETURN QUERY SELECT false, v_case.state, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT coalesce(a.provider_receipt->>'document_id', a.resource_id),
         a.provider_receipt->>'provider_revision'
    INTO v_document_id, v_provider_revision
    FROM actions a
   WHERE a.case_id = p_case_id
     AND a.action_kind IN ('scope_document_create', 'scope_document_fill', 'scope_document_verify')
     AND a.state = 'verified'
   ORDER BY a.updated_at DESC
   LIMIT 1;

  IF v_document_id IS NULL THEN
    SELECT sv.document_id, sv.provider_revision
      INTO v_document_id, v_provider_revision
      FROM projects p
      JOIN scope_versions sv ON sv.id = p.active_scope_id
     WHERE p.id = v_case.project_id;
  END IF;

  SELECT f.scope_version_id, f.completed_at
    INTO v_scope_id, v_completed_at
    FROM finalize_verified_case(
      p_case_id,
      coalesce(v_document_id, 'scopeledger-no-document'),
      coalesce(v_provider_revision, 'scopeledger-unversioned'),
      p_correlation_id
    ) f;

  RETURN QUERY SELECT true, 'completed'::text, v_scope_id, v_completed_at;
END;
$$;

REVOKE ALL ON FUNCTION request_manager_publication(uuid,jsonb,timestamptz,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION confirm_manager_publication(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION request_client_decision_challenge(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION confirm_client_decision(uuid,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION complete_case_if_ready(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION ingest_email_case(text,text,text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_investigation_result(uuid,jsonb,jsonb,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION request_manager_publication(uuid,jsonb,timestamptz,text) TO scopeledger_web;
GRANT EXECUTE ON FUNCTION confirm_manager_publication(uuid,text,text) TO scopeledger_web;
GRANT EXECUTE ON FUNCTION request_client_decision_challenge(uuid,text) TO scopeledger_web;
GRANT EXECUTE ON FUNCTION confirm_client_decision(uuid,text,text,text,text,text) TO scopeledger_web;
GRANT EXECUTE ON FUNCTION complete_case_if_ready(uuid,text) TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION ingest_email_case(text,text,text,text,text,text) TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION record_investigation_result(uuid,jsonb,jsonb,text) TO scopeledger_worker;

COMMIT;
