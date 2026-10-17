import subprocess
import json

case_id = "08d6fa6c-f5db-4e55-9ebb-356d765a68c8"
project_id = "11111111-1111-1111-1111-111111111111"
proposal_id = "e308b3a4-8f59-492a-bf4c-98d0f8068f82"
payload_hash = "ccbcaa4d37f646c5de335d484dbb8cc9236eb71602940cc8ed9bfa49e2292145"

sql = f"""
DO $$
DECLARE
  v_challenge_id uuid;
  v_email text;
  v_code text;
  v_expires timestamptz;
  v_review_token text;
  v_token_expires timestamptz;
  v_decision_id uuid;
  v_case_id uuid;
  v_state text;
  v_receipt_status text;
  v_action_count int;
BEGIN
  -- 1. Issue client challenge
  SELECT challenge_id, delivery_email, one_time_code, expires_at
    INTO v_challenge_id, v_email, v_code, v_expires
    FROM scopeledger.issue_auth_challenge(
      '{project_id}'::uuid,
      '{proposal_id}'::uuid,
      'client',
      'client_decision',
      '127.0.0.1'
    );
  RAISE NOTICE 'Client challenge: % (email %, code %)', v_challenge_id, v_email, v_code;

  -- 2. Verify challenge
  SELECT review_token, token_expires_at
    INTO v_review_token, v_token_expires
    FROM scopeledger.verify_auth_challenge(v_challenge_id, v_code);
  RAISE NOTICE 'Client verified: token length %', length(v_review_token);

  -- 3. Decide proposal (Accept option_b_swap)
  SELECT decision_id, case_id, case_state, receipt_status
    INTO v_decision_id, v_case_id, v_state, v_receipt_status
    FROM scopeledger.decide_proposal(
      v_review_token,
      '{proposal_id}'::uuid,
      1, -- proposal_version
      '{payload_hash}',
      'accept',
      'option_b_swap',
      'Confirmed scope swap: replace CSV Export with Account Dashboard',
      'corr-client-001'
    );
  RAISE NOTICE 'Decision: % (case_state %, receipt %)', v_decision_id, v_state, v_receipt_status;

  SELECT count(*) INTO v_action_count FROM scopeledger.actions WHERE case_id = '{case_id}'::uuid;
  RAISE NOTICE 'Enqueued actions count: %', v_action_count;
END;
$$;
"""

cmd = ['docker', 'exec', 'deployment-postgres-1', 'psql', '-U', 'postgres', '-d', 'scopeledger', '-c', sql]
res = subprocess.run(cmd, capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
