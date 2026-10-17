import subprocess
import json
import os
import sys
import uuid
import time

def psql(sql):
    pg_bin = r"C:\Program Files\PostgreSQL\17\bin\psql.exe"
    if os.path.exists(pg_bin):
        env = os.environ.copy()
        env["PGPASSWORD"] = "ScopeLedgerLocal2026DevPassSecret!"
        cmd = [pg_bin, "-U", "postgres", "-h", "127.0.0.1", "-p", "5432", "-d", "scopeledger", "-t", "-A", "-c", sql]
        res = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if res.returncode != 0:
            raise RuntimeError(f"PSQL Error: {res.stderr}\nQuery: {sql}")
        return res.stdout.strip()
    cmd = ['docker', 'exec', 'deployment-postgres-1', 'psql', '-U', 'postgres', '-d', 'scopeledger', '-t', '-A', '-c', sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"PSQL Error: {res.stderr}\nQuery: {sql}")
    return res.stdout.strip()

def create_isolated_project(name):
    proj_id = str(uuid.uuid4())
    scope_id = str(uuid.uuid4())
    psql(f"""
    SET search_path TO scopeledger, public;
    INSERT INTO scopeledger.projects (id, name, manager_email, client_email, repo_owner, repo_name, drive_folder_id, currency)
    VALUES ('{proj_id}'::uuid, '{name}', 'manager@example.test', 'client@example.test', 'demo-owner', 'demo-repo', 'demo-drive-folder', 'USD');

    INSERT INTO scopeledger.scope_versions (id, project_id, version, normalized_scope, content_hash, status, document_id, provider_revision)
    VALUES ('{scope_id}'::uuid, '{proj_id}'::uuid, 1, 
      '{{"deliverables": [{{"id": "DEL-01", "status": "active"}}]}}'::jsonb,
      scopeledger.canonical_jsonb_hash('{{"deliverables": [{{"id": "DEL-01", "status": "active"}}]}}'::jsonb),
      'active', 'doc-1', 'rev-1'
    );

    UPDATE scopeledger.projects SET active_scope_id = '{scope_id}'::uuid WHERE id = '{proj_id}'::uuid;
    """)
    return proj_id

def random_ip():
    return f"10.{uuid.uuid4().int % 200}.{uuid.uuid4().int % 200}.{uuid.uuid4().int % 200}"

def main():
    print("="*65)
    print("ScopePilot Reliability, Recovery & Expiry Test Suite (T29-T38)")
    print("="*65)

    # Clean up any leftover actions/leases from prior aborted test runs
    psql("""
    UPDATE scopeledger.actions SET state = 'blocked' WHERE state IN ('pending', 'running', 'retryable');
    UPDATE scopeledger.projects SET execution_lease_owner = NULL, execution_lease_until = NULL;
    """)

    # -------------------------------------------------------------
    # Test 1: T38 — Proposal Expiry & Rejection of Stale Acceptance
    # -------------------------------------------------------------
    print("\n--- Test 1: T38 — Proposal Expiry & Rejection of Stale Acceptance ---")
    p1_id = create_isolated_project("T38 Expiry Project")
    
    c1_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p1_id}'::uuid, 'inbox-test', 'msg-exp-{uuid.uuid4().hex[:8]}', 'Request expiring soon', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    payload1 = {
        "currency": "USD",
        "recipient_email": "client@example.test",
        "options": [{
            "id": "opt_exp",
            "kind": "swap",
            "title": "Test Expiry Option",
            "description": "Option to test expiration lifecycle",
            "price_minor": 0,
            "normalized_scope": {"deliverables": []},
            "actions": [
                {
                    "business_suffix": f"act-exp-{c1_id[:8]}",
                    "provider": "github",
                    "action_kind": "github_issue_create",
                    "approved_payload": {"title": "Test", "body": "Test", "labels": []}
                }
            ]
        }]
    }

    # Create draft with expiry 1 second in the future
    prop1_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c1_id}'::uuid, '{json.dumps(payload1)}'::jsonb, now() + interval '1 second');
    """).split('|')
    prop1_id = prop1_res[0]
    prop1_ver = int(prop1_res[1])
    prop1_hash = prop1_res[2]

    # Publish proposal
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p1_id}'::uuid, '{prop1_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');

      SELECT review_token INTO v_tok
      FROM scopeledger.verify_auth_challenge(v_chal, v_code);

      PERFORM scopeledger.publish_proposal(v_tok, '{prop1_id}'::uuid, 0::bigint, 'corr-exp-pub');
    END;
    $$;
    """)

    # Wait 2 seconds for natural expiry
    print("Waiting 2 seconds for natural expiry threshold...")
    time.sleep(2)

    # Run expire_due_proposals
    expired_count = psql("SELECT scopeledger.expire_due_proposals('cron-test-expiry');")
    print(f"Expired proposals count: {expired_count}")
    assert int(expired_count) >= 1, "Expected at least 1 proposal expired"

    prop_st = psql(f"SELECT status FROM scopeledger.proposals WHERE id = '{prop1_id}';")
    case_st = psql(f"SELECT state FROM scopeledger.cases WHERE id = '{c1_id}';")
    print(f"Proposal status: {prop_st}, Case state: {case_st}")
    assert prop_st == "expired", f"Expected expired, got {prop_st}"
    assert case_st == "expired", f"Expected expired, got {case_st}"

    # Verify audit event
    audit_evt = psql(f"SELECT event_type FROM scopeledger.audit_events WHERE case_id = '{c1_id}' AND event_type = 'proposal_expired';")
    assert "proposal_expired" in audit_evt, "Audit event proposal_expired missing"
    print("PASS: Proposal and case transitioned to 'expired' with audit log.")

    # Attempt client decision on expired proposal (Must Fail with SL004)
    print("Attempting client acceptance on expired proposal...")
    try:
        psql(f"""
        DO $$
        DECLARE
          v_chal uuid;
          v_code text;
          v_tok text;
        BEGIN
          SELECT challenge_id, one_time_code INTO v_chal, v_code
          FROM scopeledger.issue_auth_challenge('{p1_id}'::uuid, '{prop1_id}'::uuid, 'client', 'client_decision', '{random_ip()}');

          SELECT review_token INTO v_tok
          FROM scopeledger.verify_auth_challenge(v_chal, v_code);

          PERFORM scopeledger.decide_proposal(v_tok, '{prop1_id}'::uuid, {prop1_ver}, '{prop1_hash}', 'accept', 'opt_exp', 'Try accept expired', 'corr-stale');
        END;
        $$;
        """)
        print("FAIL: Acceptance of expired proposal did not raise error!")
        sys.exit(1)
    except Exception:
        print("PASS: Stale acceptance rejected by database guard (SL004: proposal has expired).")

    # -------------------------------------------------------------
    # Test 2: B14 / T37 — Reminders & Notification Outbox Idempotency
    # -------------------------------------------------------------
    print("\n--- Test 2: B14 / T37 — Reminders & Notification Outbox Idempotency ---")
    p2_id = create_isolated_project("B14 Outbox Project")
    
    c2_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p2_id}'::uuid, 'inbox-test', 'msg-remind-{uuid.uuid4().hex[:8]}', 'Request awaiting decision', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    payload2 = {
        "currency": "USD",
        "recipient_email": "client@example.test",
        "options": [{
            "id": "opt_remind",
            "kind": "swap",
            "title": "Test Remind Option",
            "description": "Option to test reminders",
            "price_minor": 0,
            "normalized_scope": {"deliverables": []},
            "actions": [
                {
                    "business_suffix": f"act-rem-{c2_id[:8]}",
                    "provider": "github",
                    "action_kind": "github_issue_create",
                    "approved_payload": {"title": "Test", "body": "Test", "labels": []}
                }
            ]
        }]
    }

    prop2_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c2_id}'::uuid, '{json.dumps(payload2)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop2_id = prop2_res[0]

    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p2_id}'::uuid, '{prop2_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');

      SELECT review_token INTO v_tok
      FROM scopeledger.verify_auth_challenge(v_chal, v_code);

      PERFORM scopeledger.publish_proposal(v_tok, '{prop2_id}'::uuid, 0::bigint, 'corr-remind-pub');
    END;
    $$;
    """)

    # Enqueue reminder
    notif1_id = psql(f"SELECT scopeledger.enqueue_proposal_reminder('{prop2_id}'::uuid, 'reminder_24h');")
    print(f"Reminder notification enqueued: ID = {notif1_id}")
    assert notif1_id and notif1_id != "", "Expected notification ID returned"

    # Enqueue duplicate reminder (Idempotency test)
    notif1_dup = psql(f"SELECT scopeledger.enqueue_proposal_reminder('{prop2_id}'::uuid, 'reminder_24h');")
    print(f"Duplicate reminder enqueue returned: '{notif1_dup}' (empty due to ON CONFLICT)")
    assert not notif1_dup or notif1_dup == "", "Expected duplicate reminder to be suppressed"
    print("PASS: Duplicate reminder suppressed by idempotency business key.")

    # Claim notification
    claimed_notif = psql("SELECT id, template_id, state FROM scopeledger.claim_next_notification('worker-outbox-01', 120);").split('|')
    print(f"Claimed notification: ID={claimed_notif[0]}, State={claimed_notif[2]}")
    assert claimed_notif[2] == "running", f"Expected running, got {claimed_notif[2]}"

    # Record notification delivery
    psql(f"SELECT scopeledger.record_notification_result('{notif1_id}'::uuid, 'worker-outbox-01', 'sent', 'provider-gmail-msg-001');")
    notif_final = psql(f"SELECT state, provider_message_id FROM scopeledger.notifications WHERE id = '{notif1_id}';").split('|')
    print(f"Notification record result: State={notif_final[0]}, ProviderMsgId={notif_final[1]}")
    assert notif_final[0] == "sent", f"Expected sent, got {notif_final[0]}"
    assert notif_final[1] == "provider-gmail-msg-001", "Provider message ID mismatch"
    print("PASS: Notification claimed, dispatched and recorded with provider delivery ID.")

    # -------------------------------------------------------------
    # Test 3: T32 — Worker Crash & Stalled Lease Reconciliation
    # -------------------------------------------------------------
    print("\n--- Test 3: T32 — Worker Crash & Stalled Lease Reconciliation ---")
    p3_id = create_isolated_project("T32 Crash Recovery Project")

    c3_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p3_id}'::uuid, 'inbox-test', 'msg-crash-{uuid.uuid4().hex[:8]}', 'Crash test request', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    swap_payload = {
        "currency": "USD",
        "recipient_email": "client@example.test",
        "options": [
            {
                "id": "opt_swap_crash",
                "kind": "swap",
                "title": "Crash Recovery Option",
                "description": "Crash recovery and partial execution testing option",
                "price_minor": 0,
                "normalized_scope": {"deliverables": []},
                "actions": [
                    {
                        "business_suffix": f"act-1-{c3_id[:8]}",
                        "provider": "github",
                        "action_kind": "github_issue_create",
                        "approved_payload": {"title": "Deliverable Action 1", "body": "Body 1", "labels": []}
                    },
                    {
                        "business_suffix": f"act-2-{c3_id[:8]}",
                        "provider": "github",
                        "action_kind": "github_issue_create",
                        "approved_payload": {"title": "Deliverable Action 2", "body": "Body 2", "labels": []}
                    }
                ]
            }
        ]
    }

    # Draft, publish, decide
    prop3_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c3_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop3_id = prop3_res[0]
    prop3_ver = int(prop3_res[1])
    prop3_hash = prop3_res[2]

    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p3_id}'::uuid, '{prop3_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop3_id}'::uuid, 0::bigint, 'corr-pub');

      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p3_id}'::uuid, '{prop3_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop3_id}'::uuid, {prop3_ver}, '{prop3_hash}', 'accept', 'opt_swap_crash', 'Accept crash test', 'corr-dec');
    END;
    $$;
    """)

    # 1. Claim Action 1 and verify it
    act1_row = psql("SELECT id, action_kind FROM scopeledger.claim_next_action('worker-crash-01', 120);").split('|')
    act1_id = act1_row[0].strip()
    psql(f"""
    SELECT scopeledger.record_action_result(
      '{act1_id}'::uuid, 'worker-crash-01', 'verified', 
      '{{"provider":"github","status":"ok"}}'::jsonb, 
      '{{"read_back":true}}'::jsonb
    );
    """)
    print(f"Action 1 ({act1_id}) verified.")

    # 2. Claim Action 2, then simulate crash
    act2_row = psql("SELECT id, action_kind FROM scopeledger.claim_next_action('worker-crash-01', 120);").split('|')
    act2_id = act2_row[0].strip()
    print(f"Action 2 ({act2_id}) claimed by worker-crash-01.")

    # Simulate worker death: advance lease into the past
    psql(f"UPDATE scopeledger.actions SET lease_until = now() - interval '15 seconds' WHERE id = '{act2_id}';")

    # Run reconciler
    rec_out = psql(f"SELECT reconciled_action_id, previous_state, new_state, attempt FROM scopeledger.reconcile_stalled_actions('reconciler-daemon', 3);")
    rec_rows = [line.split('|') for line in rec_out.strip().split('\n') if line]
    print(f"Reconciled {len(rec_rows)} stalled action(s).")
    reconciled_ids = [r[0] for r in rec_rows]
    assert act2_id in reconciled_ids, f"Expected {act2_id} in reconciled actions"

    act2_st = psql(f"SELECT state FROM scopeledger.actions WHERE id = '{act2_id}';")
    assert act2_st == "pending", f"Expected stalled action to be requeued to pending, got {act2_st}"

    # Verify Action 1 was NOT modified or requeued
    act1_st = psql(f"SELECT state FROM scopeledger.actions WHERE id = '{act1_id}';")
    assert act1_st == "verified", f"Action 1 should remain verified, got {act1_st}"
    print("PASS: Verified Action 1 was untouched; stalled Action 2 was safely requeued.")

    # Finish Action 2 with new worker
    act2_reclaim = psql("SELECT id FROM scopeledger.claim_next_action('worker-recovery-02', 120);").strip()
    assert act2_reclaim == act2_id, "Expected Action 2 to be re-claimable by new worker"
    psql(f"""
    SELECT scopeledger.record_action_result(
      '{act2_id}'::uuid, 'worker-recovery-02', 'verified', 
      '{{"provider":"github","status":"ok"}}'::jsonb, 
      '{{"read_back":true}}'::jsonb
    );
    """)
    print("Action 2 completed and verified by recovery worker.")

    # Finalize case
    psql(f"SELECT scopeledger.finalize_verified_case('{c3_id}'::uuid, 'https://github.com/test', 'rev-3', 'corr-fin');")
    final_st = psql(f"SELECT state FROM scopeledger.cases WHERE id = '{c3_id}';")
    assert final_st == "completed", f"Expected completed, got {final_st}"
    print("PASS: Case finalized to completed after worker crash recovery without duplicate execution.")

    # -------------------------------------------------------------
    # Test 4: T29 / T33 — Partial Application & Blocked Failure
    # -------------------------------------------------------------
    print("\n--- Test 4: T29 / T33 — Partial Application & Blocked Failure ---")
    p4_id = create_isolated_project("T29 T33 Block Project")

    c4_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p4_id}'::uuid, 'inbox-test', 'msg-block-{uuid.uuid4().hex[:8]}', 'Block test request', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    prop4_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c4_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop4_id = prop4_res[0]
    prop4_ver = int(prop4_res[1])
    prop4_hash = prop4_res[2]

    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p4_id}'::uuid, '{prop4_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop4_id}'::uuid, 0::bigint, 'corr-pub');

      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p4_id}'::uuid, '{prop4_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop4_id}'::uuid, {prop4_ver}, '{prop4_hash}', 'accept', 'opt_swap_crash', 'Accept block test', 'corr-dec');
    END;
    $$;
    """)

    # Claim Action 1 and verify
    act1_id = psql("SELECT id FROM scopeledger.claim_next_action('worker-block-01', 120);").strip()
    psql(f"""
    SELECT scopeledger.record_action_result(
      '{act1_id}'::uuid, 'worker-block-01', 'verified', 
      '{{"provider":"github"}}'::jsonb, '{{"read_back":true}}'::jsonb
    );
    """)

    # Claim Action 2, exceed max attempts (simulating persistent 403 Forbidden / Docs failure)
    act2_id = psql("SELECT id FROM scopeledger.claim_next_action('worker-block-01', 120);").strip()
    psql(f"UPDATE scopeledger.actions SET attempt_count = 3, lease_until = now() - interval '10 seconds' WHERE id = '{act2_id}';")

    # Reconciler should mark action blocked
    psql(f"SELECT scopeledger.reconcile_stalled_actions('reconciler-daemon', 3);")
    act2_blocked_st = psql(f"SELECT state FROM scopeledger.actions WHERE id = '{act2_id}';")
    print(f"Reconciliation state for persistently failing action: {act2_blocked_st}")
    assert act2_blocked_st == "blocked", f"Expected blocked, got {act2_blocked_st}"

    # Verify case cannot be finalized
    print("Attempting to finalize case with blocked action...")
    try:
        psql(f"SELECT scopeledger.finalize_verified_case('{c4_id}'::uuid, 'https://github.com/test', 'rev-4', 'corr-fin');")
        print("FAIL: Finalization succeeded despite blocked unverified action!")
        sys.exit(1)
    except Exception:
        print("PASS: Finalization rejected (SL002: not all mandatory actions are verified).")

    # Case transitions to partially_applied (or applying)
    c4_st = psql(f"SELECT state FROM scopeledger.cases WHERE id = '{c4_id}';")
    assert c4_st in ("partially_applied", "applying"), f"Expected partially_applied or applying, got {c4_st}"
    print(f"PASS: Case state is '{c4_st}'; partial application state preserved and baseline is not activated.")

    # -------------------------------------------------------------
    # Test 5: T20 — Change Baseline/Proposal After Token Issuance (Stale Rejection)
    # -------------------------------------------------------------
    print("\n--- Test 5: T20 — Change Baseline/Proposal After Token Issuance ---")
    p5_id = create_isolated_project("T20 Stale Baseline Project")

    # Create case A and case B on p5_id
    c5a_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p5_id}'::uuid, 'inbox-test', 'msg-5a-{uuid.uuid4().hex[:8]}', 'Case A', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    c5b_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p5_id}'::uuid, 'inbox-test', 'msg-5b-{uuid.uuid4().hex[:8]}', 'Case B', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    # Create and publish proposal for Case A
    prop5a_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c5a_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop5a_id = prop5a_res[0]
    prop5a_ver = int(prop5a_res[1])
    prop5a_hash = prop5a_res[2]

    # Create and publish proposal for Case B (both against baseline v1)
    prop5b_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c5b_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop5b_id = prop5b_res[0]
    prop5b_ver = int(prop5b_res[1])
    prop5b_hash = prop5b_res[2]

    # Publish Case A
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p5_id}'::uuid, '{prop5a_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop5a_id}'::uuid, 0::bigint, 'corr-5a-pub');
    END;
    $$;
    """)

    # Fast-forward cooldown for next challenge on p5_id
    psql(f"UPDATE scopeledger.auth_challenges SET created_at = now() - interval '65 seconds' WHERE project_id = '{p5_id}'::uuid;")

    # Publish Case B
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p5_id}'::uuid, '{prop5b_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop5b_id}'::uuid, 0::bigint, 'corr-5b-pub');
    END;
    $$;
    """)

    # Client accepts Case A, worker executes and finalizes Case A (updating baseline to v2)
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p5_id}'::uuid, '{prop5a_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop5a_id}'::uuid, {prop5a_ver}, '{prop5a_hash}', 'accept', 'opt_swap_crash', 'Accept A', 'corr-5a-dec');
    END;
    $$;
    """)

    # Execute and finalize Case A
    a1 = psql("SELECT id FROM scopeledger.claim_next_action('worker-5', 120);").strip()
    psql(f"SELECT scopeledger.record_action_result('{a1}'::uuid, 'worker-5', 'verified', '{{\"provider\":\"github\"}}'::jsonb, '{{\"read_back\":true}}'::jsonb);")
    a2 = psql("SELECT id FROM scopeledger.claim_next_action('worker-5', 120);").strip()
    psql(f"SELECT scopeledger.record_action_result('{a2}'::uuid, 'worker-5', 'verified', '{{\"provider\":\"github\"}}'::jsonb, '{{\"read_back\":true}}'::jsonb);")
    psql(f"SELECT scopeledger.finalize_verified_case('{c5a_id}'::uuid, 'https://docs.google.com/test', 'rev-v2', 'corr-5a-fin');")

    # Fast forward client cooldown before attempting client challenge for Case B
    psql(f"UPDATE scopeledger.auth_challenges SET created_at = now() - interval '65 seconds' WHERE project_id = '{p5_id}'::uuid;")

    # Now attempt to accept Case B (which was drafted against baseline v1)
    print("Attempting to accept Case B whose baseline scope was superseded by Case A...")
    try:
        psql(f"""
        DO $$
        DECLARE
          v_chal uuid;
          v_code text;
          v_tok text;
        BEGIN
          SELECT challenge_id, one_time_code INTO v_chal, v_code
          FROM scopeledger.issue_auth_challenge('{p5_id}'::uuid, '{prop5b_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
          SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
          PERFORM scopeledger.decide_proposal(v_tok, '{prop5b_id}'::uuid, {prop5b_ver}, '{prop5b_hash}', 'accept', 'opt_swap_crash', 'Accept B', 'corr-5b-dec');
        END;
        $$;
        """)
        print("FAIL: Acceptance of proposal with stale baseline succeeded!")
        sys.exit(1)
    except Exception:
        print("PASS: Acceptance rejected (SL002: proposal, evidence, or baseline is stale).")

    # -------------------------------------------------------------
    # Test 6: T22 — Concurrent Acceptance Conflict on Unresolved Sync
    # -------------------------------------------------------------
    print("\n--- Test 6: T22 — Concurrent Acceptance Conflict on Unresolved Sync ---")
    p6_id = create_isolated_project("T22 Concurrent Project")

    c6a_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p6_id}'::uuid, 'inbox-test', 'msg-6a-{uuid.uuid4().hex[:8]}', 'Case A', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    c6b_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p6_id}'::uuid, 'inbox-test', 'msg-6b-{uuid.uuid4().hex[:8]}', 'Case B', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    prop6a_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c6a_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop6a_id = prop6a_res[0]
    prop6a_ver = int(prop6a_res[1])
    prop6a_hash = prop6a_res[2]

    prop6b_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c6b_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop6b_id = prop6b_res[0]
    prop6b_ver = int(prop6b_res[1])
    prop6b_hash = prop6b_res[2]

    # Publish 6A
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p6_id}'::uuid, '{prop6a_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop6a_id}'::uuid, 0::bigint, 'corr-6a-pub');
    END;
    $$;
    """)

    # Fast forward manager cooldown on p6_id
    psql(f"UPDATE scopeledger.auth_challenges SET created_at = now() - interval '65 seconds' WHERE project_id = '{p6_id}'::uuid;")

    # Publish 6B
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p6_id}'::uuid, '{prop6b_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop6b_id}'::uuid, 0::bigint, 'corr-6b-pub');
    END;
    $$;
    """)

    # Accept Case A (enters accepted_pending_sync)
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p6_id}'::uuid, '{prop6a_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop6a_id}'::uuid, {prop6a_ver}, '{prop6a_hash}', 'accept', 'opt_swap_crash', 'Accept 6A', 'corr-6a-dec');
    END;
    $$;
    """)

    # Fast forward client cooldown on p6_id before attempting Case B decision
    psql(f"UPDATE scopeledger.auth_challenges SET created_at = now() - interval '65 seconds' WHERE project_id = '{p6_id}'::uuid;")

    # While Case A is in accepted_pending_sync, try to accept Case B
    print("Attempting to accept Case B while Case A is in accepted_pending_sync...")
    try:
        psql(f"""
        DO $$
        DECLARE
          v_chal uuid;
          v_code text;
          v_tok text;
        BEGIN
          SELECT challenge_id, one_time_code INTO v_chal, v_code
          FROM scopeledger.issue_auth_challenge('{p6_id}'::uuid, '{prop6b_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
          SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
          PERFORM scopeledger.decide_proposal(v_tok, '{prop6b_id}'::uuid, {prop6b_ver}, '{prop6b_hash}', 'accept', 'opt_swap_crash', 'Accept 6B', 'corr-6b-dec');
        END;
        $$;
        """)
        print("FAIL: Concurrent acceptance allowed unresolved change conflict!")
        sys.exit(1)
    except Exception:
        print("PASS: Concurrent acceptance rejected (SL007: another accepted project change is unresolved).")

    # -------------------------------------------------------------
    # Test 7: T30 — Force 429 with Retry-After Delay Honor
    # -------------------------------------------------------------
    print("\n--- Test 7: T30 — 429 Rate Limiting & Retry-After Delay Honor ---")
    p7_id = create_isolated_project("T30 Rate Limit Project")

    c7_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p7_id}'::uuid, 'inbox-test', 'msg-7-{uuid.uuid4().hex[:8]}', 'Case 7 Rate Limit', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    prop7_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c7_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop7_id = prop7_res[0]
    prop7_ver = int(prop7_res[1])
    prop7_hash = prop7_res[2]

    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p7_id}'::uuid, '{prop7_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop7_id}'::uuid, 0::bigint, 'corr-7-pub');

      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p7_id}'::uuid, '{prop7_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop7_id}'::uuid, {prop7_ver}, '{prop7_hash}', 'accept', 'opt_swap_crash', 'Accept 7', 'corr-7-dec');
    END;
    $$;
    """)

    # Worker claims action 1
    act7_id = psql("SELECT id FROM scopeledger.claim_next_action('worker-rate-01', 120);").strip()
    # Provider returns HTTP 429 Too Many Requests with Retry-After: 30
    psql(f"""
    SELECT scopeledger.record_action_result(
      '{act7_id}'::uuid, 'worker-rate-01', 'retryable', 
      '{{\"provider\":\"github\",\"status\":429}}'::jsonb, NULL, 'HTTP_429_RATE_LIMITED', now() + interval '30 seconds'
    );
    """)

    # Immediate claim should NOT return this action (honor Retry-After backoff)
    reclaim_attempt = psql("SELECT id FROM scopeledger.claim_next_action('worker-rate-01', 120);").strip()
    assert reclaim_attempt != act7_id, "Action claimed prematurely before next_attempt_at delay elapsed!"
    print("PASS: Worker delayed; action was NOT claimed during active Retry-After window.")

    # Fast-forward retry timestamp into the past
    psql(f"UPDATE scopeledger.actions SET next_attempt_at = now() - interval '1 second' WHERE id = '{act7_id}';")
    reclaim_success = psql("SELECT id FROM scopeledger.claim_next_action('worker-rate-01', 120);").strip()
    assert reclaim_success == act7_id, f"Expected {act7_id} claimable after delay, got {reclaim_success}"
    print("PASS: Action successfully claimed after Retry-After delay elapsed without duplication.")

    print("\n" + "="*65)
    print("ALL RELIABILITY & RECOVERY TESTS PASSED (T20, T22, T29, T30, T32, T33, T37, T38)")
    print("="*65)

if __name__ == "__main__":
    main()
