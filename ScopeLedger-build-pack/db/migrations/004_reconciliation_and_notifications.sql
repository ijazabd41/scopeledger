-- ScopeLedger Migration 004: Action Reconciliation, Reminders, and Notification Outbox
-- Idempotent and crash-recovery procedures for failure recovery and proposal expiry

\set ON_ERROR_STOP on
SET search_path TO scopeledger, public;

-- 1. Function to record notification delivery or failure
CREATE OR REPLACE FUNCTION record_notification_result(
  p_notification_id uuid,
  p_worker_id text,
  p_status text,
  p_provider_message_id text DEFAULT NULL,
  p_error_code text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_notif notifications%ROWTYPE;
BEGIN
  IF p_status NOT IN ('sent', 'unknown', 'blocked') THEN
    RAISE EXCEPTION USING ERRCODE = 'SL004', MESSAGE = 'invalid notification status';
  END IF;

  SELECT * INTO v_notif FROM notifications
   WHERE id = p_notification_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'notification not found';
  END IF;

  IF v_notif.state = 'sent' THEN
    -- Already verified sent, idempotent return
    RETURN;
  END IF;

  UPDATE notifications
     SET state = p_status,
         provider_message_id = coalesce(p_provider_message_id, v_notif.provider_message_id),
         lease_owner = NULL,
         lease_until = NULL,
         updated_at = now()
   WHERE id = p_notification_id;

  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  VALUES (
    v_notif.case_id,
    'notif-dispatch',
    'outbox',
    CASE WHEN p_status = 'sent' THEN 'notification_sent' ELSE 'notification_failed' END,
    jsonb_build_object(
      'notification_id', p_notification_id,
      'template_id', v_notif.template_id,
      'recipient', v_notif.recipient,
      'status', p_status,
      'error_code', p_error_code
    )
  );
END;
$$;

-- 2. Function to enqueue a proposal reminder idempotently
CREATE OR REPLACE FUNCTION enqueue_proposal_reminder(
  p_proposal_id uuid,
  p_template_id text DEFAULT 'reminder_client_review'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
DECLARE
  v_proposal proposals%ROWTYPE;
  v_case cases%ROWTYPE;
  v_project projects%ROWTYPE;
  v_biz_key text;
  v_mail_marker text;
  v_notif_id uuid;
BEGIN
  SELECT * INTO v_proposal FROM proposals WHERE id = p_proposal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'SL001', MESSAGE = 'proposal not found';
  END IF;

  IF v_proposal.status <> 'published' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'cannot remind unpublished proposal';
  END IF;

  SELECT * INTO v_case FROM cases WHERE id = v_proposal.case_id;
  IF v_case.state <> 'awaiting_client' THEN
    RAISE EXCEPTION USING ERRCODE = 'SL002', MESSAGE = 'case is not awaiting client';
  END IF;

  SELECT * INTO v_project FROM projects WHERE id = v_case.project_id;

  v_biz_key := 'remind-' || p_template_id || '-' || p_proposal_id::text;
  v_mail_marker := 'marker-remind-' || p_proposal_id::text;

  -- Insert only if not already enqueued
  INSERT INTO notifications (
    case_id, proposal_id, business_key, recipient, template_id,
    approved_content, state, mail_marker
  )
  VALUES (
    v_case.id,
    v_proposal.id,
    v_biz_key,
    v_project.client_email,
    p_template_id,
    jsonb_build_object(
      'project_name', v_project.name,
      'proposal_id', v_proposal.id,
      'proposal_version', v_proposal.version,
      'expires_at', v_proposal.expires_at,
      'review_link', 'http://localhost:5679/webhook/scopeledger-client-decide?proposal_id=' || v_proposal.id::text
    ),
    'pending',
    v_mail_marker
  )
  ON CONFLICT (business_key) DO NOTHING
  RETURNING id INTO v_notif_id;

  RETURN v_notif_id;
END;
$$;

-- 3. Function to reconcile stalled action leases (worker crashes, network drops)
CREATE OR REPLACE FUNCTION reconcile_stalled_actions(
  p_worker_id text,
  p_max_attempts integer DEFAULT 3,
  p_correlation_id text DEFAULT 'reconcile-stalled'
)
RETURNS TABLE(reconciled_action_id uuid, previous_state text, new_state text, attempt integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = scopeledger, public
AS $$
BEGIN
  -- 1. Reconcile stalled actions and log audit trail
  RETURN QUERY
  WITH stalled AS (
    SELECT a.id, a.case_id, a.state, a.attempt_count
      FROM actions a
     WHERE a.state = 'running'
       AND a.lease_until <= now()
     FOR UPDATE SKIP LOCKED
  ), updated AS (
    UPDATE actions a
       SET state = CASE WHEN s.attempt_count >= p_max_attempts THEN 'blocked' ELSE 'pending' END,
           last_error_code = CASE WHEN s.attempt_count >= p_max_attempts THEN 'MAX_ATTEMPTS_EXCEEDED' ELSE 'LEASE_TIMEOUT_REQUEUED' END,
           lease_owner = NULL,
           lease_until = NULL,
           updated_at = now()
      FROM stalled s
     WHERE a.id = s.id
     RETURNING a.id, s.state AS old_st, a.state AS new_st, a.attempt_count, a.case_id
  )
  INSERT INTO audit_events(case_id, correlation_id, actor_role, event_type, safe_details)
  SELECT u.case_id, p_correlation_id, 'reconciler', 'action_reconciled',
         jsonb_build_object(
           'action_id', u.id,
           'reconciled_by', p_worker_id,
           'previous_state', u.old_st,
           'new_state', u.new_st,
           'attempt_count', u.attempt_count
         )
    FROM updated u
  RETURNING (safe_details->>'action_id')::uuid,
            safe_details->>'previous_state',
            safe_details->>'new_state',
            (safe_details->>'attempt_count')::integer;

  -- 2. Update case state for blocked actions (T33: partially_applied visible)
  UPDATE cases c
     SET state = CASE
           WHEN EXISTS (SELECT 1 FROM actions a WHERE a.case_id = c.id AND a.state = 'verified') THEN 'partially_applied'
           ELSE 'blocked'
         END,
         last_error_code = 'ACTION_BLOCKED'
   WHERE c.id IN (SELECT case_id FROM updated WHERE new_st = 'blocked')
     AND c.state IN ('applying', 'accepted_pending_sync');

  -- 3. Release project execution leases for projects with no remaining running actions
  UPDATE projects p
     SET execution_lease_owner = NULL,
         execution_lease_until = NULL
   WHERE p.execution_lease_until IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM actions a JOIN cases c ON c.id = a.case_id
        WHERE c.project_id = p.id AND a.state = 'running'
     );
END;
$$;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION record_notification_result(uuid, text, text, text, text) TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION enqueue_proposal_reminder(uuid, text) TO scopeledger_worker, scopeledger_web;
GRANT EXECUTE ON FUNCTION reconcile_stalled_actions(text, integer, text) TO scopeledger_worker;

-- 4. Enhanced claim_next_action to prevent head-of-line blocking across projects
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
    FROM actions a
    JOIN cases c ON c.id = a.case_id
    JOIN projects p ON p.id = c.project_id
   WHERE a.state IN ('pending','retryable')
     AND coalesce(a.next_attempt_at, '-infinity'::timestamptz) <= now()
     AND (p.execution_lease_until IS NULL OR p.execution_lease_until <= now()
          OR p.execution_lease_owner = p_worker_id)
     AND NOT EXISTS (
       SELECT 1 FROM actions prior
        WHERE prior.case_id = a.case_id AND prior.id <> a.id
          AND prior.created_at < a.created_at AND prior.state <> 'verified'
     )
   ORDER BY a.created_at, a.id
   FOR UPDATE OF a, p SKIP LOCKED LIMIT 1;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT c.project_id INTO v_project_id FROM cases c WHERE c.id = v_action.case_id;

  UPDATE projects SET execution_lease_owner = p_worker_id,
                      execution_lease_until = now() + make_interval(secs => p_lease_seconds)
   WHERE id = v_project_id;

  UPDATE actions SET state = 'running', lease_owner = p_worker_id,
                     lease_until = now() + make_interval(secs => p_lease_seconds),
                     attempt_count = attempt_count + 1
   WHERE id = v_action.id RETURNING * INTO v_action;

  UPDATE cases SET state = 'applying' WHERE id = v_action.case_id
    AND state = 'accepted_pending_sync';

  RETURN NEXT v_action;
END;
$$;

GRANT EXECUTE ON FUNCTION claim_next_action(text, integer) TO scopeledger_worker;

-- 5. Enhanced record_action_result to reflect partially_applied on cases
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

  IF p_outcome = 'blocked' THEN
    IF EXISTS (SELECT 1 FROM actions WHERE case_id = v_action.case_id AND state = 'verified') THEN
      UPDATE cases SET state = 'partially_applied', last_error_code = coalesce(p_error_code, 'ACTION_BLOCKED') WHERE id = v_action.case_id;
    ELSE
      UPDATE cases SET state = 'blocked', last_error_code = coalesce(p_error_code, 'ACTION_BLOCKED') WHERE id = v_action.case_id;
    END IF;
  END IF;

  RETURN v_action;
END;
$$;

GRANT EXECUTE ON FUNCTION record_action_result(uuid, text, text, jsonb, jsonb, text, timestamptz) TO scopeledger_worker;
