-- HELD P0 release barrier: mandatory distinct-Person approval for EACH
-- immutable Carry event. This is NOT a production migration.
-- Must apply AFTER v3 ordinary/apply and F/G1/G2/G3 source, never before
-- their historical v3 legacy regression tests. P1 replaces this hold with
-- source-authorized per-event approval; never regrant old service_role writers.
BEGIN;

DO $preconditions$
BEGIN
 IF pg_catalog.to_regprocedure(
      'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)') IS NULL
 OR pg_catalog.to_regprocedure(
      'us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)') IS NULL
 OR pg_catalog.to_regprocedure(
      'us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint,text)') IS NULL
 OR pg_catalog.to_regprocedure(
      'us.carry_approve_and_open_primary_v3(uuid,uuid,text)') IS NULL
 OR NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_roles
   WHERE rolname='us_carry_backend' AND NOT rolsuper AND NOT rolbypassrls)
 THEN RAISE EXCEPTION 'P0 needs complete held G3 source and restricted role'
   USING ERRCODE='55000'; END IF;
END $preconditions$;

-- The old functions remain in the held source to preserve baseline test
-- evidence and existing history, but NO deployed role may call them.
-- They lack a live distinct canonical Person approval witness per event.
REVOKE ALL ON FUNCTION
 us.carry_append_ordinary_event_v3(uuid,uuid,text,text,date,text,text,jsonb,bigint)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
REVOKE ALL ON FUNCTION
 us.carry_adopt_derived_revision_v3(uuid,uuid,text,bigint,text)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
REVOKE ALL ON FUNCTION
 us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

-- G3 source can still call the v1 writer internally as its SECURITY DEFINER
-- owner; no EXECUTE grant of the raw v1 writer is necessary.
-- Keep G3 explicitly sourced approval routes available only to the backend.
DO $floor$
BEGIN
 IF NOT has_function_privilege(
  'us_carry_backend','us.carry_authorize_primary_open_approval_v3(uuid,uuid,text,timestamptz)','EXECUTE')
 OR NOT has_function_privilege(
  'us_carry_backend','us.carry_approve_and_open_primary_v3(uuid,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'P0 accidentally blocked distinct-Person G3 approval'
  USING ERRCODE='55000'; END IF;
END $floor$;

COMMIT;
