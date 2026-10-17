\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned
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
VALUES ('ScopePilot DB test', 'manager@example.test', 'client@example.test',
        'scopeledger-test', 'demo', 'drive-folder-test', 'USD')
RETURNING id AS project_id \gset

INSERT INTO scope_versions(project_id, version, normalized_scope, content_hash, status,
                           document_id, provider_revision)
VALUES (:'project_id', 1,
        '{"deliverables":[{"id":"marketing-site","status":"active"},{"id":"csv-export","status":"active"}]}'::jsonb,
        canonical_jsonb_hash('{"deliverables":[{"id":"marketing-site","status":"active"},{"id":"csv-export","status":"active"}]}'::jsonb),
        'active', 'baseline-doc', 'rev-1')
RETURNING id AS baseline_id \gset

UPDATE projects SET active_scope_id = :'baseline_id' WHERE id = :'project_id';

INSERT INTO cases(project_id, mailbox_id, message_id, thread_id, request_excerpt, state)
VALUES (:'project_id', 'mailbox-test', 'message-test', 'thread-test',
        'Please replace CSV export with an account dashboard.', 'awaiting_manager')
RETURNING id AS case_id, row_version AS case_version \gset

SELECT * FROM create_proposal_draft(
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
        {"id":"marketing-site","status":"active"},
        {"id":"csv-export","status":"superseded"},
        {"id":"account-dashboard","status":"active"}
      ]},
      "actions":[
        {"business_suffix":"github:create:dashboard","provider":"github","action_kind":"github_issue_create","approved_payload":{"title":"Build account dashboard","marker":"ScopePilot:test:dashboard"}},
        {"business_suffix":"docs:create:scope-v2","provider":"google_docs","action_kind":"scope_document_create","approved_payload":{"title":"Scope revision 2","marker":"ScopePilot:test:scope-v2"}}
      ]
    }]
  }'::jsonb,
  now() + interval '72 hours'
) \gset

SELECT pg_temp.assert_true((SELECT count(*) = 0 FROM actions WHERE case_id = :'case_id'),
                           'draft creation must not enqueue writes');

SELECT * FROM issue_auth_challenge(:'project_id', :'proposal_id', 'manager',
                                  'manager_publish', 'test-ip-manager') \gset manager_
SELECT * FROM verify_auth_challenge(:'manager_challenge_id', :'manager_one_time_code') \gset manager_verified_

SELECT * FROM publish_proposal(:'manager_verified_review_token', :'proposal_id',
                               :'case_version', 'test-manager-publish') \gset published_

SELECT pg_temp.assert_true(
  (SELECT state = 'awaiting_client' FROM cases WHERE id = :'case_id'),
  'manager publication must transition the case to awaiting_client');
SELECT pg_temp.assert_true(
  (SELECT status = 'published' FROM proposals WHERE id = :'proposal_id'),
  'manager publication must publish the proposal');
SELECT pg_temp.assert_true((SELECT count(*) = 0 FROM actions WHERE case_id = :'case_id'),
                           'publication must not enqueue provider writes');

CREATE OR REPLACE FUNCTION pg_temp.assert_proposal_immutable(p_proposal_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    UPDATE proposals SET payload = payload || '{"tampered":true}'::jsonb
     WHERE id = p_proposal_id;
    RAISE EXCEPTION 'immutability trigger did not reject published proposal update';
  EXCEPTION WHEN SQLSTATE 'SL003' THEN
    NULL;
  END;
END;
$$;
SELECT pg_temp.assert_proposal_immutable(:'proposal_id');

SELECT * FROM issue_auth_challenge(:'project_id', :'proposal_id', 'client',
                                  'client_decision', 'test-ip-client') \gset client_
SELECT * FROM verify_auth_challenge(:'client_challenge_id', :'client_one_time_code') \gset client_verified_

SELECT * FROM decide_proposal(
  :'client_verified_review_token', :'proposal_id', :'proposal_version', :'payload_hash',
  'accept', 'swap-dashboard-for-csv', NULL, 'test-client-accept'
) \gset accepted_

SELECT pg_temp.assert_true(:'accepted_case_state' = 'accepted_pending_sync',
                           'acceptance must return accepted_pending_sync');
SELECT pg_temp.assert_true((SELECT count(*) = 2 FROM actions WHERE case_id = :'case_id'),
                           'acceptance must atomically enqueue the exact approved actions');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 1 FROM scope_versions
    WHERE project_id = :'project_id' AND status = 'accepted_pending_sync'),
  'acceptance must create one pending scope version');

SELECT * FROM decide_proposal(
  :'client_verified_review_token', :'proposal_id', :'proposal_version', :'payload_hash',
  'accept', 'swap-dashboard-for-csv', NULL, 'test-client-accept-replay'
) \gset replay_
SELECT pg_temp.assert_true(:'replay_receipt_status' = 'duplicate_receipt',
                           'identical replay must return the original receipt');
SELECT pg_temp.assert_true((SELECT count(*) = 1 FROM decisions WHERE proposal_id = :'proposal_id'),
                           'identical replay must not create another decision');
SELECT pg_temp.assert_true((SELECT count(*) = 2 FROM actions WHERE case_id = :'case_id'),
                           'identical replay must not duplicate actions');

SELECT id AS first_action_id FROM claim_next_action('worker-test', 120) \gset
SELECT (record_action_result(:'first_action_id', 'worker-test', 'verified',
         '{"provider_id":"provider-resource-1"}'::jsonb,
         '{"read_back":true,"matched":true}'::jsonb, NULL, NULL)).id;
SELECT id AS second_action_id FROM claim_next_action('worker-test', 120) \gset
SELECT (record_action_result(:'second_action_id', 'worker-test', 'verified',
         '{"provider_id":"provider-resource-2"}'::jsonb,
         '{"read_back":true,"matched":true}'::jsonb, NULL, NULL)).id;

SELECT * FROM finalize_verified_case(:'case_id', 'scope-doc-v2', 'scope-rev-2',
                                    'test-finalize') \gset completed_
SELECT pg_temp.assert_true((SELECT state = 'completed' FROM cases WHERE id = :'case_id'),
                           'verified actions must allow case completion');
SELECT pg_temp.assert_true(
  (SELECT sv.status = 'active' AND sv.document_id = 'scope-doc-v2'
     FROM projects p JOIN scope_versions sv ON sv.id = p.active_scope_id
    WHERE p.id = :'project_id'),
  'completion must atomically activate the verified scope revision');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 2 FROM actions WHERE case_id = :'case_id' AND state = 'verified'),
  'all provider actions must remain independently verified');

SELECT 'authorization_flow_ok';
