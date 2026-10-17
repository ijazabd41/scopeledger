import subprocess
import json

case_id = "08d6fa6c-f5db-4e55-9ebb-356d765a68c8"
project_id = "11111111-1111-1111-1111-111111111111"

payload = {
    "currency": "USD",
    "recipient_email": "client@example.test",
    "options": [
        {
            "id": "option_a_charge",
            "kind": "charge",
            "title": "Add Account Dashboard (+ $2,500)",
            "description": "Retain all approved deliverables (DEL-01, DEL-02) and add Account Dashboard.",
            "price_minor": 250000,
            "effective_date": "2026-10-24",
            "normalized_scope": {
                "deliverables": [
                    {"id": "DEL-01", "title": "Marketing Website Landing Page", "status": "active", "github_issue_number": 1},
                    {"id": "DEL-02", "title": "CSV Data Export Feature", "status": "active", "github_issue_number": 2},
                    {"id": "DEL-03", "title": "Account Dashboard", "status": "active"}
                ]
            },
            "actions": [
                {
                    "business_suffix": "gh-create-account-dashboard",
                    "provider": "github",
                    "action_kind": "github_issue_create",
                    "approved_payload": {
                        "title": "Deliverable: Account Dashboard",
                        "body": "Client approved addition: Account Dashboard deliverable.",
                        "labels": ["scopeledger:approved"]
                    }
                }
            ]
        },
        {
            "id": "option_b_swap",
            "kind": "swap",
            "title": "Scope Swap: CSV Export for Account Dashboard ($0)",
            "description": "Exchange DEL-02 (CSV Data Export Feature) for DEL-03 (Account Dashboard) with zero additional fee.",
            "price_minor": 0,
            "effective_date": "2026-10-24",
            "normalized_scope": {
                "deliverables": [
                    {"id": "DEL-01", "title": "Marketing Website Landing Page", "status": "active", "github_issue_number": 1},
                    {"id": "DEL-02", "title": "CSV Data Export Feature", "status": "superseded", "github_issue_number": 2},
                    {"id": "DEL-03", "title": "Account Dashboard", "status": "active"}
                ]
            },
            "actions": [
                {
                    "business_suffix": "gh-create-account-dashboard",
                    "provider": "github",
                    "action_kind": "github_issue_create",
                    "approved_payload": {
                        "title": "Deliverable: Account Dashboard",
                        "body": "Client approved Scope Swap: Account Dashboard replacing CSV Data Export Feature.",
                        "labels": ["scopeledger:approved"]
                    }
                },
                {
                    "business_suffix": "gh-supersede-csv-export",
                    "provider": "github",
                    "action_kind": "github_issue_supersede",
                    "resource_id": "2",
                    "approved_payload": {
                        "issue_number": 2,
                        "state": "closed",
                        "labels": ["scopeledger:superseded"]
                    }
                }
            ]
        }
    ]
}

sql = f"""
DO $$
DECLARE
  v_prop_id uuid;
  v_version int;
  v_hash text;
  v_challenge_id uuid;
  v_email text;
  v_code text;
  v_expires timestamptz;
  v_review_token text;
  v_token_expires timestamptz;
  v_pub_id uuid;
  v_pub_ver int;
  v_pub_hash text;
  v_pub_expires timestamptz;
BEGIN
  -- 1. Create draft
  SELECT proposal_id, proposal_version, payload_hash
    INTO v_prop_id, v_version, v_hash
    FROM scopeledger.create_proposal_draft(
      '{case_id}'::uuid,
      '{json.dumps(payload)}'::jsonb,
      now() + interval '72 hours'
    );
  RAISE NOTICE 'Draft created: % (version %)', v_prop_id, v_version;

  -- 2. Issue challenge
  SELECT challenge_id, delivery_email, one_time_code, expires_at
    INTO v_challenge_id, v_email, v_code, v_expires
    FROM scopeledger.issue_auth_challenge(
      '{project_id}'::uuid,
      v_prop_id,
      'manager',
      'manager_publish',
      '127.0.0.1'
    );
  RAISE NOTICE 'Challenge issued: % (email %, code %)', v_challenge_id, v_email, v_code;

  -- 3. Verify challenge
  SELECT review_token, token_expires_at
    INTO v_review_token, v_token_expires
    FROM scopeledger.verify_auth_challenge(v_challenge_id, v_code);
  RAISE NOTICE 'Challenge verified: token length %', length(v_review_token);

  -- 4. Publish proposal
  SELECT proposal_id, proposal_version, payload_hash, expires_at
    INTO v_pub_id, v_pub_ver, v_pub_hash, v_pub_expires
    FROM scopeledger.publish_proposal(
      v_review_token,
      v_prop_id,
      0::bigint, -- expected_case_version
      'corr-manager-001'
    );
  RAISE NOTICE 'Proposal published: % (version %)', v_pub_id, v_pub_ver;
END;
$$;
"""

cmd = ['docker', 'exec', 'deployment-postgres-1', 'psql', '-U', 'postgres', '-d', 'scopeledger', '-c', sql]
res = subprocess.run(cmd, capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
