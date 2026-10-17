\set ON_ERROR_STOP on
SET search_path TO scopeledger, public;
BEGIN;

DELETE FROM audit_events WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM notifications WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM actions WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM decisions WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM review_tokens WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM auth_challenges WHERE project_id='00000000-0000-0000-0000-000000000101';
DELETE FROM proposals WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM evidence WHERE case_id IN (SELECT id FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101');
DELETE FROM cases WHERE project_id='00000000-0000-0000-0000-000000000101';
UPDATE projects SET active_scope_id=NULL WHERE id='00000000-0000-0000-0000-000000000101';
DELETE FROM scope_versions WHERE project_id='00000000-0000-0000-0000-000000000101';
DELETE FROM projects WHERE id='00000000-0000-0000-0000-000000000101';

INSERT INTO projects(id, name, manager_email, client_email, repo_owner, repo_name,
                     drive_folder_id, currency)
VALUES ('00000000-0000-0000-0000-000000000101', 'Concurrency test',
        'manager@example.test', 'client@example.test', 'scopeledger-test', 'demo',
        'drive-race', 'USD');
INSERT INTO scope_versions(id, project_id, version, normalized_scope, content_hash, status,
                           document_id, provider_revision)
VALUES ('00000000-0000-0000-0000-000000000201',
        '00000000-0000-0000-0000-000000000101', 1,
        '{"deliverables":[{"id":"baseline","status":"active"}]}'::jsonb,
        canonical_jsonb_hash('{"deliverables":[{"id":"baseline","status":"active"}]}'::jsonb),
        'active', 'race-baseline', 'race-rev-1');
UPDATE projects SET active_scope_id = '00000000-0000-0000-0000-000000000201'
 WHERE id = '00000000-0000-0000-0000-000000000101';

INSERT INTO cases(id, project_id, mailbox_id, message_id, request_excerpt, state)
VALUES
 ('00000000-0000-0000-0000-000000000301','00000000-0000-0000-0000-000000000101',
  'race-mailbox','race-message-a','Change A','awaiting_client'),
 ('00000000-0000-0000-0000-000000000302','00000000-0000-0000-0000-000000000101',
  'race-mailbox','race-message-b','Change B','awaiting_client');

WITH payloads(case_id, proposal_id, suffix) AS (
  VALUES
   ('00000000-0000-0000-0000-000000000301'::uuid,'00000000-0000-0000-0000-000000000401'::uuid,'a'::text),
   ('00000000-0000-0000-0000-000000000302'::uuid,'00000000-0000-0000-0000-000000000402'::uuid,'b'::text)
), built AS (
  SELECT case_id, proposal_id,
         jsonb_build_object(
           'currency','USD',
           'recipient_email','client@example.test',
           'options',jsonb_build_array(jsonb_build_object(
             'id','accept-' || suffix,
             'kind','swap',
             'description','Concurrent project change ' || upper(suffix),
             'price_minor','0',
             'normalized_scope',jsonb_build_object('deliverables',jsonb_build_array(
               jsonb_build_object('id','baseline','status','active'),
               jsonb_build_object('id','change-' || suffix,'status','active'))),
             'actions',jsonb_build_array(jsonb_build_object(
               'business_suffix','github:create:' || suffix,
               'provider','github',
               'action_kind','github_issue_create',
               'approved_payload',jsonb_build_object('title','Change ' || upper(suffix))))
           ))) AS payload
    FROM payloads
)
INSERT INTO proposals(id, case_id, version, baseline_scope_id, evidence_version, payload,
                      payload_hash, status, published_at, expires_at)
SELECT proposal_id, case_id, 1, '00000000-0000-0000-0000-000000000201', 1,
       payload, canonical_jsonb_hash(payload), 'published', now(), now() + interval '1 hour'
  FROM built;

INSERT INTO auth_challenges(id, project_id, proposal_id, actor_email, actor_role, stage,
                            secret_hash, attempts, expires_at, consumed_at)
VALUES
 ('00000000-0000-0000-0000-000000000501','00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000401','client@example.test','client','client_decision',
  'test:consumed',1,now() + interval '1 hour',now()),
 ('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000402','client@example.test','client','client_decision',
  'test:consumed',1,now() + interval '1 hour',now());

INSERT INTO review_tokens(id, challenge_id, case_id, proposal_id, actor_email, actor_role,
                          stage, token_hash, expected_payload_hash, expires_at)
SELECT '00000000-0000-0000-0000-000000000601',
       '00000000-0000-0000-0000-000000000501',
       '00000000-0000-0000-0000-000000000301', p.id,
       'client@example.test','client','client_decision',
       encode(digest(convert_to('race-token-a','UTF8'),'sha256'),'hex'), p.payload_hash,
       now() + interval '1 hour'
  FROM proposals p WHERE p.id = '00000000-0000-0000-0000-000000000401';
INSERT INTO review_tokens(id, challenge_id, case_id, proposal_id, actor_email, actor_role,
                          stage, token_hash, expected_payload_hash, expires_at)
SELECT '00000000-0000-0000-0000-000000000602',
       '00000000-0000-0000-0000-000000000502',
       '00000000-0000-0000-0000-000000000302', p.id,
       'client@example.test','client','client_decision',
       encode(digest(convert_to('race-token-b','UTF8'),'sha256'),'hex'), p.payload_hash,
       now() + interval '1 hour'
  FROM proposals p WHERE p.id = '00000000-0000-0000-0000-000000000402';

SELECT 'concurrency_seed_ok';
COMMIT;
