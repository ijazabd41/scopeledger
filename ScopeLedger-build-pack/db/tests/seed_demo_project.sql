BEGIN;
SET search_path TO scopeledger, public;
SET session_replication_role = replica;

DELETE FROM audit_events WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM notifications WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM actions WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM decisions WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM review_tokens WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM auth_challenges WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo');
DELETE FROM proposals WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM evidence WHERE case_id IN (SELECT id FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo'));
DELETE FROM cases WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo');
UPDATE projects SET active_scope_id = NULL WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo';
DELETE FROM scope_versions WHERE project_id IN (SELECT id FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo');
DELETE FROM projects WHERE repo_owner = 'AbdurRehman-eng' AND repo_name = 'scopeledger-demo';

SET session_replication_role = DEFAULT;

INSERT INTO projects (
  id, name, manager_email, client_email, repo_owner, repo_name, drive_folder_id, currency
) VALUES (
  '11111111-1111-1111-1111-111111111111',
  'Acme Corp - Web & Reporting Platform',
  'shafiqueabdurrehman1@gmail.com',
  'client.acme@example.com',
  'AbdurRehman-eng',
  'scopeledger-demo',
  'demo-drive-folder-001',
  'USD'
);

INSERT INTO scope_versions (
  id, project_id, version, normalized_scope, content_hash, document_id, provider_revision, status
) VALUES (
  '22222222-2222-2222-2222-222222222222',
  '11111111-1111-1111-1111-111111111111',
  1,
  '{
    "deliverables": [
      {
        "id": "DEL-01",
        "title": "Marketing Website Landing Page",
        "description": "Public facing marketing landing page with responsive layout and SEO structure.",
        "status": "approved",
        "github_issue_number": 1
      },
      {
        "id": "DEL-02",
        "title": "CSV Data Export Feature",
        "description": "Export reports and transaction history to CSV format.",
        "status": "approved",
        "github_issue_number": 2
      }
    ]
  }'::jsonb,
  canonical_jsonb_hash('{
    "deliverables": [
      {
        "id": "DEL-01",
        "title": "Marketing Website Landing Page",
        "description": "Public facing marketing landing page with responsive layout and SEO structure.",
        "status": "approved",
        "github_issue_number": 1
      },
      {
        "id": "DEL-02",
        "title": "CSV Data Export Feature",
        "description": "Export reports and transaction history to CSV format.",
        "status": "approved",
        "github_issue_number": 2
      }
    ]
  }'::jsonb),
  'demo-doc-baseline-v1',
  '1',
  'active'
);

UPDATE projects SET active_scope_id = '22222222-2222-2222-2222-222222222222'
 WHERE id = '11111111-1111-1111-1111-111111111111';

COMMIT;
SELECT 'demo_project_seeded' AS result, id, name, repo_owner, repo_name FROM projects WHERE id = '11111111-1111-1111-1111-111111111111';
