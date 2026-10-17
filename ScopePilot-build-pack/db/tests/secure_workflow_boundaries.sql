\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
BEGIN;
SET search_path TO scopeledger, public;

CREATE OR REPLACE FUNCTION pg_temp.assert_true(p_condition boolean, p_message text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT coalesce(p_condition, false) THEN
    RAISE EXCEPTION 'assertion failed: %', p_message;
  END IF;
END;
$$;

INSERT INTO projects(name, manager_email, client_email, repo_owner, repo_name, drive_folder_id, currency)
VALUES ('Secure workflow test', 'manager@example.test', 'client@example.test',
        'scopeledger-test', 'secure-flow', 'drive-folder-secure-test', 'USD')
RETURNING id AS project_id \gset

INSERT INTO scope_versions(project_id, version, normalized_scope, content_hash, status,
                           document_id, provider_revision)
VALUES (:'project_id', 1,
        '{"deliverables":[{"id":"csv-export","status":"active"}]}'::jsonb,
        canonical_jsonb_hash('{"deliverables":[{"id":"csv-export","status":"active"}]}'::jsonb),
        'active', 'baseline-doc', 'rev-1')
RETURNING id AS baseline_id \gset

UPDATE projects SET active_scope_id = :'baseline_id' WHERE id = :'project_id';

INSERT INTO cases(project_id, mailbox_id, message_id, request_excerpt, state)
VALUES (:'project_id', 'mailbox-secure', 'message-secure',
        'Replace CSV export with an account dashboard.', 'awaiting_manager')
RETURNING id AS case_id \gset

SELECT * FROM request_manager_publication(
  :'case_id',
  '{
    "currency":"USD",
    "recipient_email":"client@example.test",
    "options":[{
      "id":"swap-dashboard-for-csv",
      "kind":"swap",
      "description":"Replace CSV export with an account dashboard.",
      "price_minor":"0",
      "effective_date":"2026-10-24",
      "added_deliverables":["account-dashboard"],
      "removed_deliverable_ids":["csv-export"],
      "normalized_scope":{"deliverables":[
        {"id":"csv-export","status":"superseded"},
        {"id":"account-dashboard","status":"active"}
      ]},
      "actions":[
        {"business_suffix":"github:create:dashboard","provider":"github","action_kind":"github_issue_create","approved_payload":{"title":"Build account dashboard","marker":"ScopePilot:test:dashboard"}},
        {"business_suffix":"docs:create:scope-v2","provider":"google_docs","action_kind":"scope_document_create","approved_payload":{"title":"Scope revision 2","marker":"ScopePilot:test:scope-v2"}}
      ]
    }]
  }'::jsonb,
  now() + interval '72 hours',
  '203.0.113.10'
) \gset manager_

SELECT pg_temp.assert_true(
  (SELECT expected_case_version IS NOT NULL FROM auth_challenges WHERE id = :'manager_challenge_id'),
  'manager challenge must bind the reviewed case version');
SELECT pg_temp.assert_true(
  (SELECT status = 'draft' FROM proposals WHERE id = :'manager_proposal_id'),
  'request step must leave the proposal as a draft');

SELECT * FROM confirm_manager_publication(
  :'manager_challenge_id', :'manager_one_time_code', 'secure-manager-confirm'
) \gset published_

SELECT pg_temp.assert_true(
  (SELECT status = 'published' FROM proposals WHERE id = :'published_proposal_id'),
  'confirmation step must publish the exact proposal');

SELECT * FROM request_client_decision_challenge(
  :'published_proposal_id', '203.0.113.11'
) \gset client_

SELECT pg_temp.assert_true(
  :'client_payload_hash' = :'published_payload_hash',
  'client challenge must expose the published immutable payload hash');

SELECT * FROM confirm_client_decision(
  :'client_challenge_id',
  :'client_one_time_code',
  'accept',
  'swap-dashboard-for-csv',
  'Approved in secure workflow test',
  'secure-client-confirm'
) \gset decision_

SELECT pg_temp.assert_true(:'decision_case_state' = 'accepted_pending_sync',
                           'client confirmation must atomically accept the proposal');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 2 FROM actions WHERE case_id = :'case_id'),
  'client confirmation must enqueue only the approved action set');

SELECT 'secure_workflow_boundaries_ok';
ROLLBACK;
