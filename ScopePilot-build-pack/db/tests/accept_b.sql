\set ON_ERROR_STOP on
SET search_path TO scopeledger, public;
SELECT * FROM decide_proposal(
  'race-token-b','00000000-0000-0000-0000-000000000402',1,
  (SELECT payload_hash FROM proposals WHERE id='00000000-0000-0000-0000-000000000402'),
  'accept','accept-b',NULL,'race-b');
