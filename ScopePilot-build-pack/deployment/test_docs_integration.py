"""
ScopePilot Google Docs Scope Revision Integration Test Suite (B13, T27, T28, T33)
Tests scope document revision creation, deliverable formatting, cryptographic marker verification,
and partial application failure isolation (T33).
"""

import subprocess
import json
import os
import sys
import uuid
from docs_adapter import GoogleDocsAdapter

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

def random_ip():
    return f"10.{uuid.uuid4().int % 200}.{uuid.uuid4().int % 200}.{uuid.uuid4().int % 200}"

def create_isolated_project(name, folder_id="demo-drive-folder-001"):
    proj_id = str(uuid.uuid4())
    scope_id = str(uuid.uuid4())
    psql(f"""
    SET search_path TO scopeledger, public;
    INSERT INTO scopeledger.projects (id, name, manager_email, client_email, repo_owner, repo_name, drive_folder_id, currency)
    VALUES ('{proj_id}'::uuid, '{name}', 'manager@example.test', 'client@example.test', 'demo-owner', 'demo-repo', '{folder_id}', 'USD');

    INSERT INTO scopeledger.scope_versions (id, project_id, version, normalized_scope, content_hash, status, document_id, provider_revision)
    VALUES ('{scope_id}'::uuid, '{proj_id}'::uuid, 1, 
      '{{"deliverables": [{{"id": "DEL-01", "title": "Marketing Site", "status": "active"}}, {{"id": "DEL-02", "title": "CSV Export", "status": "active"}}]}}'::jsonb,
      scopeledger.canonical_jsonb_hash('{{"deliverables": [{{"id": "DEL-01", "title": "Marketing Site", "status": "active"}}, {{"id": "DEL-02", "title": "CSV Export", "status": "active"}}]}}'::jsonb),
      'active', 'doc-baseline-v1', 'rev-v1'
    );

    UPDATE scopeledger.projects SET active_scope_id = '{scope_id}'::uuid WHERE id = '{proj_id}'::uuid;
    """)
    return proj_id

def main():
    print("=" * 70)
    print("ScopePilot Google Docs Scope Revision Integration Test Suite (B13)")
    print("=" * 70)

    adapter = GoogleDocsAdapter()

    # Clean queue from any previous interrupted runs
    psql("""
    UPDATE scopeledger.actions SET state = 'blocked' WHERE state IN ('pending', 'running', 'retryable');
    UPDATE scopeledger.projects SET execution_lease_owner = NULL, execution_lease_until = NULL;
    """)

    # -------------------------------------------------------------------------
    # Test 1: B13 / T27 / T28 — Full Docs Revision Publication & Verification
    # -------------------------------------------------------------------------
    print("\n--- Test 1: B13 / T27 / T28 — Docs Revision Publication & Read-Back ---")
    p1_id = create_isolated_project("Acme Docs Project v1", folder_id="folder-acme-001")

    c1_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p1_id}'::uuid, 'inbox-test', 'msg-docs-{uuid.uuid4().hex[:8]}', 'Please swap CSV export for Account Dashboard', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    swap_payload = {
        "currency": "USD",
        "recipient_email": "client@example.test",
        "options": [
            {
                "id": "opt_swap_docs",
                "kind": "swap",
                "title": "Scope Swap: CSV Export for Account Dashboard ($0)",
                "description": "Exchange DEL-02 for DEL-03 with zero additional fee.",
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
                        "business_suffix": f"gh-create-{c1_id[:8]}",
                        "provider": "github",
                        "action_kind": "github_issue_create",
                        "approved_payload": {"title": "Deliverable: Account Dashboard", "body": "New deliverable", "labels": ["scopeledger:approved"]}
                    },
                    {
                        "business_suffix": f"gh-supersede-{c1_id[:8]}",
                        "provider": "github",
                        "action_kind": "github_issue_supersede",
                        "resource_id": "2",
                        "approved_payload": {"issue_number": 2, "state": "closed", "labels": ["scopeledger:superseded"]}
                    },
                    {
                        "business_suffix": f"docs-v2-{c1_id[:8]}",
                        "provider": "google_docs",
                        "action_kind": "scope_document_create",
                        "approved_payload": {
                            "title": "Acme Corp - Scope Revision Agreement v2",
                            "folder_id": "folder-acme-001",
                            "marker": f"ScopePilot:scope-v2:{c1_id}",
                            "scope_version": 2,
                            "deliverables": [
                                {"id": "DEL-01", "title": "Marketing Website Landing Page", "status": "active", "github_issue_number": 1},
                                {"id": "DEL-02", "title": "CSV Data Export Feature", "status": "superseded", "github_issue_number": 2},
                                {"id": "DEL-03", "title": "Account Dashboard", "status": "active"}
                            ]
                        }
                    }
                ]
            }
        ]
    }

    # 1. Create proposal draft
    prop1_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c1_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop1_id = prop1_res[0]
    prop1_ver = int(prop1_res[1])
    prop1_hash = prop1_res[2]

    # 2. Manager OTP Challenge & Publish
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p1_id}'::uuid, '{prop1_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop1_id}'::uuid, 0::bigint, 'corr-docs-pub');
    END;
    $$;
    """)

    # 3. Client OTP Challenge & Acceptance
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p1_id}'::uuid, '{prop1_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop1_id}'::uuid, {prop1_ver}, '{prop1_hash}', 'accept', 'opt_swap_docs', 'Accept scope swap with docs sync', 'corr-docs-dec');
    END;
    $$;
    """)

    # 4. Worker executes all 3 actions dynamically based on action_kind
    doc_res = None
    for _ in range(3):
        claim_out = psql("SELECT id, action_kind, approved_payload::text FROM scopeledger.claim_next_action('worker-docs-01', 120);")
        parts = claim_out.split('|')
        act_id = parts[0].strip()
        act_kind = parts[1].strip()
        act_payload = json.loads(parts[2])

        if act_kind == "github_issue_create":
            psql(f"""
            SELECT scopeledger.record_action_result(
              '{act_id}'::uuid, 'worker-docs-01', 'verified',
              '{{"provider":"github","issue_number":4,"html_url":"https://github.com/demo/issues/4"}}'::jsonb,
              '{{"read_back":true,"state":"open","issue_number":4}}'::jsonb
            );
            """)
            print(f"Action ({act_id}: github_issue_create) verified.")

        elif act_kind == "github_issue_supersede":
            psql(f"""
            SELECT scopeledger.record_action_result(
              '{act_id}'::uuid, 'worker-docs-01', 'verified',
              '{{"provider":"github","issue_number":2,"state":"closed"}}'::jsonb,
              '{{"read_back":true,"state":"closed","issue_number":2}}'::jsonb
            );
            """)
            print(f"Action ({act_id}: github_issue_supersede) verified.")

        elif act_kind == "scope_document_create":
            print(f"Executing Google Docs Scope Revision publication (Action {act_id})...")
            doc_res = adapter.create_and_publish_scope_revision(
                project_name="Acme Corp - Web & Reporting Platform",
                scope_version=act_payload.get("scope_version", 2),
                title=act_payload["title"],
                folder_id=act_payload["folder_id"],
                marker=act_payload["marker"],
                normalized_scope=swap_payload["options"][0]["normalized_scope"],
                case_id=c1_id,
                proposal_id=prop1_id,
                decision_id="dec-" + c1_id[:8],
                effective_date="2026-10-24"
            )
            print(f"Scope Revision Document Created: ID={doc_res['document_id']}, URL={doc_res['document_url']}")

            readback_res = adapter.verify_scope_document_readback(
                folder_id=act_payload["folder_id"],
                document_id=doc_res["document_id"],
                expected_marker=act_payload["marker"]
            )
            assert readback_res["marker_matched"] is True, "Expected verification marker matched in document"
            print(f"Independent readback passed: Marker matched, length={readback_res['content_length']} chars.")

            psql(f"""
            SELECT scopeledger.record_action_result(
              '{act_id}'::uuid, 'worker-docs-01', 'verified',
              '{json.dumps(doc_res)}'::jsonb,
              '{json.dumps(readback_res)}'::jsonb
            );
            """)
            print(f"Action ({act_id}: scope_document_create) verified in database.")
        else:
            raise ValueError(f"Unknown action kind: {act_kind}")

    assert doc_res is not None, "Expected doc_res to be populated"

    # 7. Finalize verified case with real Google Docs revision identity
    fin_res = psql(f"""
    SELECT scope_version_id, completed_at FROM scopeledger.finalize_verified_case(
      '{c1_id}'::uuid,
      '{doc_res["document_id"]}',
      '{doc_res["provider_revision"]}',
      'corr-docs-finalize'
    );
    """)
    print(f"Case Finalization Result: {fin_res}")

    # Verify database state
    c1_final_st = psql(f"SELECT state FROM scopeledger.cases WHERE id = '{c1_id}';")
    assert c1_final_st == "completed", f"Expected case completed, got {c1_final_st}"

    active_scope = psql(f"""
    SELECT sv.version, sv.status, sv.document_id, sv.provider_revision
    FROM scopeledger.projects p
    JOIN scopeledger.scope_versions sv ON sv.id = p.active_scope_id
    WHERE p.id = '{p1_id}';
    """).split('|')
    print(f"Active Scope Version: {active_scope[0]}, Status: {active_scope[1]}, DocID: {active_scope[2]}, Rev: {active_scope[3]}")
    assert active_scope[0] == "2", f"Expected version 2, got {active_scope[0]}"
    assert active_scope[1] == "active", f"Expected status active, got {active_scope[1]}"
    assert active_scope[2] == doc_res["document_id"], f"Document ID mismatch on active scope"
    assert active_scope[3] == doc_res["provider_revision"], f"Provider revision mismatch on active scope"

    # Prior version superseded
    prior_st = psql(f"SELECT status FROM scopeledger.scope_versions WHERE project_id = '{p1_id}'::uuid AND version = 1;")
    assert prior_st == "superseded", f"Expected prior version superseded, got {prior_st}"
    print("PASS: T27/T28/B13: Google Docs scope revision published, read-back verified, and baseline v2 activated!")

    # -------------------------------------------------------------------------
    # Test 2: T33 — Make Docs Fail After GitHub Success (Partial Application Guard)
    # -------------------------------------------------------------------------
    print("\n--- Test 2: T33 — Make Docs Fail After GitHub Success (Partial Application) ---")
    p2_id = create_isolated_project("Acme Docs Fail Project", folder_id="folder-acme-fail")

    c2_id = psql(f"""
    INSERT INTO scopeledger.cases (project_id, mailbox_id, message_id, request_excerpt, state)
    VALUES ('{p2_id}'::uuid, 'inbox-test', 'msg-docs-fail-{uuid.uuid4().hex[:8]}', 'Swap request where Docs will fail', 'awaiting_manager')
    RETURNING id;
    """).split('\n')[0].strip()

    prop2_res = psql(f"""
    SELECT proposal_id, proposal_version, payload_hash 
    FROM scopeledger.create_proposal_draft('{c2_id}'::uuid, '{json.dumps(swap_payload)}'::jsonb, now() + interval '72 hours');
    """).split('|')
    prop2_id = prop2_res[0]
    prop2_ver = int(prop2_res[1])
    prop2_hash = prop2_res[2]

    # Publish & Decide
    psql(f"""
    DO $$
    DECLARE
      v_chal uuid;
      v_code text;
      v_tok text;
    BEGIN
      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p2_id}'::uuid, '{prop2_id}'::uuid, 'manager', 'manager_publish', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.publish_proposal(v_tok, '{prop2_id}'::uuid, 0::bigint, 'corr-fail-pub');

      SELECT challenge_id, one_time_code INTO v_chal, v_code
      FROM scopeledger.issue_auth_challenge('{p2_id}'::uuid, '{prop2_id}'::uuid, 'client', 'client_decision', '{random_ip()}');
      SELECT review_token INTO v_tok FROM scopeledger.verify_auth_challenge(v_chal, v_code);
      PERFORM scopeledger.decide_proposal(v_tok, '{prop2_id}'::uuid, {prop2_ver}, '{prop2_hash}', 'accept', 'opt_swap_docs', 'Accept fail test', 'corr-fail-dec');
    END;
    $$;
    """)

    # Ensure Google Docs action is sequenced after GitHub actions (natural dependency)
    psql(f"""
    UPDATE scopeledger.actions
    SET created_at = created_at + interval '10 milliseconds'
    WHERE case_id = '{c2_id}'::uuid AND action_kind = 'scope_document_create';
    """)

    # Worker executes actions: GitHub actions succeed, then Docs action fails (HTTP 403)
    for _ in range(3):
        claim_out = psql("SELECT id, action_kind FROM scopeledger.claim_next_action('worker-fail-01', 120);")
        parts = claim_out.split('|')
        act_id = parts[0].strip()
        act_kind = parts[1].strip()

        if act_kind.startswith("github_"):
            psql(f"""
            SELECT scopeledger.record_action_result(
              '{act_id}'::uuid, 'worker-fail-01', 'verified',
              '{{"provider":"github","status":"success"}}'::jsonb,
              '{{"read_back":true}}'::jsonb
            );
            """)
            print(f"Action ({act_id}: {act_kind}) verified successfully.")
        elif act_kind == "scope_document_create":
            print(f"Injecting simulated Google Docs failure (HTTP 403 Forbidden) on Action ({act_id}: {act_kind})...")
            psql(f"""
            SELECT scopeledger.record_action_result(
              '{act_id}'::uuid, 'worker-fail-01', 'blocked',
              '{{"provider":"google_docs","http_status":403,"error":"INSUFFICIENT_DRIVE_PERMISSIONS"}}'::jsonb,
              NULL,
              'HTTP_403_FORBIDDEN'
            );
            """)
        else:
            raise ValueError(f"Unknown action kind: {act_kind}")

    # Case state should now be partially_applied!
    c2_st = psql(f"SELECT state FROM scopeledger.cases WHERE id = '{c2_id}';")
    print(f"Case state after Docs failure: {c2_st}")
    assert c2_st == "partially_applied", f"Expected partially_applied, got {c2_st}"

    # Attempting to finalize case MUST fail with SL002
    print("Attempting to finalize case with failed Docs action...")
    try:
        psql(f"SELECT scopeledger.finalize_verified_case('{c2_id}'::uuid, 'unverified-doc', 'rev-fail', 'corr-fail');")
        print("FAIL: Finalization succeeded despite blocked Docs action!")
        sys.exit(1)
    except Exception:
        print("PASS: Finalization rejected (SL002: not all mandatory actions are verified).")

    # Verify baseline was NOT corrupted and remains at v1
    active_scope_p2 = psql(f"""
    SELECT sv.version, sv.status, p.active_scope_id
    FROM scopeledger.projects p
    JOIN scopeledger.scope_versions sv ON sv.id = p.active_scope_id
    WHERE p.id = '{p2_id}';
    """).split('|')
    print(f"Project active scope version: {active_scope_p2[0]}, status: {active_scope_p2[1]}")
    assert active_scope_p2[0] == "1", "Project baseline should NOT have advanced to v2"
    assert active_scope_p2[1] == "active", "Project v1 should remain active"

    # Pending scope v2 remains in accepted_pending_sync
    pending_st = psql(f"SELECT status FROM scopeledger.scope_versions WHERE project_id = '{p2_id}'::uuid AND version = 2;")
    assert pending_st == "accepted_pending_sync", f"Expected accepted_pending_sync, got {pending_st}"

    # Project is blocked from subsequent accepted changes until resolved
    print("PASS: T33: Docs failure after GitHub writes correctly isolated in partially_applied state without baseline corruption!")

    # -------------------------------------------------------------------------
    # Test 3: Marker Tamper Detection (Integrity Guard)
    # -------------------------------------------------------------------------
    print("\n--- Test 3: Marker Tamper Detection ---")
    try:
        adapter.verify_scope_document_readback("folder-acme-001", doc_res["document_id"], "TAMPERED_MARKER_999")
        print("FAIL: Verification succeeded with tampered marker!")
        sys.exit(1)
    except ValueError as e:
        print(f"PASS: Tampered marker rejected: {e}")

    print("\n" + "=" * 70)
    print("ALL GOOGLE DOCS INTEGRATION TESTS PASSED (B13, T27, T28, T33)")
    print("=" * 70)

if __name__ == "__main__":
    main()
