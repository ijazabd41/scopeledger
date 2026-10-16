\set ON_ERROR_STOP on
SET search_path TO scopeledger, public;
SELECT * FROM decide_proposal(
  'race-token-a','00000000-0000-0000-0000-000000000401',1,
  (SELECT payload_hash FROM proposals WHERE id='00000000-0000-0000-0000-000000000401'),
  'accept','accept-a',NULL,'race-a');
