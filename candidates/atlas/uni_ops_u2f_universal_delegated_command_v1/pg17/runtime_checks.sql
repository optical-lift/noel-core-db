\set ON_ERROR_STOP on
-- PostgreSQL 17, disposable SYNTHETIC fixture only, never production.
\ir synthetic_fixture.sql
\ir ../02_native_ledger_carrier_identity_held.sql

-- The source really compiles and is not exposed to application roles.
DO $u2f_acl$
BEGIN
  IF (SELECT p.prosecdef FROM pg_catalog.pg_proc p
      WHERE p.oid='atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(uuid,uuid)'::regprocedure)
  THEN RAISE EXCEPTION 'U2F identity function must not be SECURITY DEFINER'; END IF;
  IF has_function_privilege('anon','atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(uuid,uuid)','EXECUTE')
     OR has_function_privilege('service_role','atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(uuid,uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'U2F identity reader escaped private role boundary'; END IF;
  IF to_regclass('atlas.tasks') IS NOT NULL
     OR to_regclass('atlas.task_release_queue_items') IS NOT NULL
     OR to_regclass('atlas.work_items') IS NOT NULL
  THEN RAISE EXCEPTION 'A legacy or Work engine was wrongly added to the synthetic identity fixture'; END IF;
END
$u2f_acl$;

-- Test-only internal role, on an isolated container. Not a proposed live grant.
GRANT USAGE ON SCHEMA atlas,ledger TO u2f_synthetic_reader;
GRANT SELECT ON atlas.delegated_agent_carriers,atlas.principals,
  atlas.delegated_agent_authorizations,ledger.ledgers,ledger.seats
TO u2f_synthetic_reader;
GRANT EXECUTE ON FUNCTION
  atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(uuid,uuid)
TO u2f_synthetic_reader;

-- IdentityAligned TRUE never means authority to issue original Work.
CREATE FUNCTION pg_temp.u2f_assert(
 p_expected boolean,p_case text,
 p_auth uuid DEFAULT '66666666-6666-4666-8666-666666666666',
 p_ledger uuid DEFAULT '44444444-4444-4444-8444-444444444444'
) RETURNS void LANGUAGE plpgsql AS $test$
DECLARE j jsonb; flag text;
BEGIN
 SELECT atlas.uni_ops_u2f_native_ledger_carrier_identity_held_v1(p_auth,p_ledger) INTO j;
 IF (j->>'identityAligned')::boolean IS DISTINCT FROM p_expected
 THEN RAISE EXCEPTION '% identity misclassification: %',p_case,j; END IF;
 FOREACH flag IN ARRAY ARRAY[
   'workIssuerAuthorized','governingRootVerified','workCandidateAccepted',
   'rulebookAndNeedVerified','originalWorkCreated'
 ] LOOP
   IF j->>flag IS DISTINCT FROM 'false'
   THEN RAISE EXCEPTION '% gained authority via %: %',p_case,flag,j; END IF;
 END LOOP;
 IF j->>'sourceOnly' IS DISTINCT FROM 'true'
 THEN RAISE EXCEPTION '% forgot source-only boundary',p_case; END IF;
END
$test$;

-- Run one actual SEC INVOKER synthetic positive with a SELECT-limited role.
SET ROLE u2f_synthetic_reader;
SELECT pg_temp.u2f_assert(true,'valid exact native actor identity');
RESET ROLE;

SELECT pg_temp.u2f_assert(false,'unknown authorization',
  '77777777-7777-4777-8777-777777777777');
SELECT pg_temp.u2f_assert(false,'wrong native Ledger',DEFAULT,
  '77777777-7777-4777-8777-777777777777');
SELECT pg_temp.u2f_assert(false,'null authorization',NULL);
SELECT pg_temp.u2f_assert(false,'null ledger',DEFAULT,NULL);

BEGIN;
-- All mutations are deliberate negative synthetic tests and are rolled back.
UPDATE atlas.delegated_agent_authorizations SET authorization_state='revoked';
SELECT pg_temp.u2f_assert(false,'authorization revoked state');
UPDATE atlas.delegated_agent_authorizations SET authorization_state='active',revoked_at=now();
SELECT pg_temp.u2f_assert(false,'authorization revoked time');
UPDATE atlas.delegated_agent_authorizations SET revoked_at=NULL,begins_at=now()+interval '1 day';
SELECT pg_temp.u2f_assert(false,'authorization not yet begun');
UPDATE atlas.delegated_agent_authorizations SET begins_at=now()-interval '1 hour',ends_at=now()-interval '1 minute';
SELECT pg_temp.u2f_assert(false,'authorization expired');
UPDATE atlas.delegated_agent_authorizations SET ends_at=now()+interval '1 day',delegating_seat_id=NULL;
SELECT pg_temp.u2f_assert(false,'no delegating seat');
UPDATE atlas.delegated_agent_authorizations SET delegating_seat_id='55555555-5555-4555-8555-555555555555';

UPDATE atlas.delegated_agent_carriers SET status='retired';
SELECT pg_temp.u2f_assert(false,'carrier retired state');
UPDATE atlas.delegated_agent_carriers SET status='active',retired_at=now();
SELECT pg_temp.u2f_assert(false,'carrier retired timestamp');
UPDATE atlas.delegated_agent_carriers SET retired_at=NULL;

UPDATE atlas.principals SET status='inactive';
SELECT pg_temp.u2f_assert(false,'principal inactive');
UPDATE atlas.principals SET status='active',person_id=NULL;
SELECT pg_temp.u2f_assert(false,'principal missing Person');
UPDATE atlas.principals SET person_id='77777777-7777-4777-8777-777777777777';
SELECT pg_temp.u2f_assert(false,'principal does not own seat');
UPDATE atlas.principals SET person_id='33333333-3333-4333-8333-333333333333';

UPDATE ledger.ledgers SET ledger_state='retired';
SELECT pg_temp.u2f_assert(false,'native Ledger retired state');
UPDATE ledger.ledgers SET ledger_state='active',retired_at=now();
SELECT pg_temp.u2f_assert(false,'native Ledger retired timestamp');
UPDATE ledger.ledgers SET retired_at=NULL;

UPDATE ledger.seats SET seat_state='suspended';
SELECT pg_temp.u2f_assert(false,'seat suspended');
UPDATE ledger.seats SET seat_state='active',began_at=now()+interval '1 day';
SELECT pg_temp.u2f_assert(false,'seat not begun');
UPDATE ledger.seats SET began_at=now()-interval '1 day',ended_at=now()-interval '1 second';
SELECT pg_temp.u2f_assert(false,'seat ended');
ROLLBACK;

-- Synthetic fixtures exactly restored; no Work or queue created.
SELECT pg_temp.u2f_assert(true,'after negative scenario rollback');
DO $u2f_post$
BEGIN
  IF (SELECT count(*) FROM atlas.delegated_agent_carriers)<>1
     OR (SELECT count(*) FROM atlas.delegated_agent_authorizations)<>1
     OR (SELECT count(*) FROM atlas.principals)<>1
     OR (SELECT count(*) FROM ledger.ledgers)<>1
     OR (SELECT count(*) FROM ledger.seats)<>1
  THEN RAISE EXCEPTION 'U2F synthetic source damaged identity fixture'; END IF;
  IF to_regclass('atlas.work_items') IS NOT NULL
  THEN RAISE EXCEPTION 'unexpected original Work created'; END IF;
END
$u2f_post$;
\echo 'U2F_NATIVE_LEDGER_IDENTITY_PG17_SYNTHETIC=PASS'
\echo 'SIGNED_CURRENT_SCHEMA_TEST=NOT_RUN'
\echo 'CAN_ISSUE_ORIGINAL_WORK=NO'
\echo 'PRODUCTION_MUTATION=NONE'
