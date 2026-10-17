-- NOLOGIN group roles. Map platform login roles to these groups after provisioning.
-- Keep the migration owner separate and do not grant table mutation to n8n webhooks.
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'scopeledger_reader') THEN
    CREATE ROLE scopeledger_reader NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'scopeledger_web') THEN
    CREATE ROLE scopeledger_web NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'scopeledger_worker') THEN
    CREATE ROLE scopeledger_worker NOLOGIN;
  END IF;
END;
$$;

REVOKE ALL ON SCHEMA scopeledger FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA scopeledger FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA scopeledger FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA scopeledger FROM PUBLIC;

GRANT USAGE ON SCHEMA scopeledger TO scopeledger_reader, scopeledger_web, scopeledger_worker;

GRANT SELECT ON scopeledger.projects, scopeledger.scope_versions, scopeledger.cases,
  scopeledger.evidence, scopeledger.proposals
  TO scopeledger_reader;

GRANT EXECUTE ON FUNCTION scopeledger.issue_auth_challenge(uuid,uuid,text,text,text)
  TO scopeledger_web;
GRANT EXECUTE ON FUNCTION scopeledger.verify_auth_challenge(uuid,text)
  TO scopeledger_web;
GRANT EXECUTE ON FUNCTION scopeledger.publish_proposal(text,uuid,bigint,text)
  TO scopeledger_web;
GRANT EXECUTE ON FUNCTION scopeledger.decide_proposal(text,uuid,integer,text,text,text,text,text)
  TO scopeledger_web;

GRANT EXECUTE ON FUNCTION scopeledger.create_proposal_draft(uuid,jsonb,timestamptz)
  TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION scopeledger.claim_next_action(text,integer)
  TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION scopeledger.record_action_result(uuid,text,text,jsonb,jsonb,text,timestamptz)
  TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION scopeledger.finalize_verified_case(uuid,text,text,text)
  TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION scopeledger.claim_next_notification(text,integer)
  TO scopeledger_worker;
GRANT EXECUTE ON FUNCTION scopeledger.expire_due_proposals(text)
  TO scopeledger_worker;

COMMIT;
