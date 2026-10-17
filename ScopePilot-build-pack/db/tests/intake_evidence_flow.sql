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
VALUES ('Intake evidence test', 'manager-intake@example.test', 'client-intake@example.test',
        'scopeledger-test', 'intake-evidence', 'drive-folder-intake', 'USD')
RETURNING id AS project_id \gset

INSERT INTO scope_versions(project_id, version, normalized_scope, content_hash, status,
                           document_id, provider_revision)
VALUES (:'project_id', 1, '{"deliverables":[{"id":"csv-export","status":"active"}]}'::jsonb,
        canonical_jsonb_hash('{"deliverables":[{"id":"csv-export","status":"active"}]}'::jsonb),
        'active', 'google-doc-intake-test', 'docs-rev-1')
RETURNING id AS baseline_id \gset
UPDATE projects SET active_scope_id = :'baseline_id' WHERE id = :'project_id';

SELECT * FROM ingest_email_case(
  'gmail-test', 'unknown-message', 'unknown-thread', 'unknown@example.test',
  'Unknown sender', 'Do not route this message.'
) \gset unknown_
SELECT pg_temp.assert_true(
  (SELECT count(*) = 0 FROM cases WHERE mailbox_id = 'gmail-test' AND message_id = 'unknown-message'),
  'unknown sender must not create a case');

SELECT * FROM ingest_email_case(
  'gmail-test', 'provider-message-1', 'provider-thread-1', 'client-intake@example.test',
  'Dashboard request', 'Please swap CSV export for a dashboard.'
) \gset first_
SELECT pg_temp.assert_true(:'first_deduplicated' = 'f', 'first provider message must create a case');

SELECT * FROM ingest_email_case(
  'gmail-test', 'provider-message-1', 'provider-thread-1', 'client-intake@example.test',
  'Dashboard request', 'Please swap CSV export for a dashboard.'
) \gset replay_
SELECT pg_temp.assert_true(:'replay_case_id' = :'first_case_id', 'duplicate must return the original case');
SELECT pg_temp.assert_true(:'replay_deduplicated' = 't', 'duplicate must be identified');

SELECT * FROM record_investigation_result(
  :'first_case_id',
  '{"classification":"additional","confidence":0.91,"reasoning":"Dashboard is not in the active scope.","recommended_options":[]}'::jsonb,
  '[
    {"provider":"google_docs","resource_id":"google-doc-intake-test","provider_revision":"docs-rev-1","excerpt":"CSV export is active.","safe_url":"https://docs.google.com/document/d/google-doc-intake-test/edit"},
    {"provider":"github","resource_id":"scopeledger-test/intake-evidence:issues","provider_revision":"snapshot-1","excerpt":"Issue 2: CSV export, open.","safe_url":"https://github.com/scopeledger-test/intake-evidence/issues"}
  ]'::jsonb,
  'intake-evidence-test'
) \gset investigated_

SELECT pg_temp.assert_true(:'investigated_case_state' = 'awaiting_manager',
                           'valid investigation must transition to awaiting_manager');
SELECT pg_temp.assert_true(
  (SELECT count(*) = 2 FROM evidence WHERE case_id = :'first_case_id'),
  'scope and GitHub evidence must be versioned with the case');

SELECT 'intake_evidence_flow_ok';
ROLLBACK;
