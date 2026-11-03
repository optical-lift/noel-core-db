-- R01 DISPOSABLE CLONE ONLY; never include in a production migration.
-- Exact live Noel pg_get_functiondef on 2026-11-02 (America/Chicago).
-- Original missing from the older, isolated RiverSong schema-only clone.
-- Fingerprint of installed function prosrc: 7570082f04024397227545e685a4c071.
-- Must execute only inside the single BEGIN ... ROLLBACK test transaction.
DO $r01_clone_prereq$
BEGIN
 IF current_database() <> 'noel_schema_clone'
    OR inet_server_addr() IS NOT NULL
    OR current_setting('port') <> '55432'
 THEN RAISE EXCEPTION 'R01 exact-source parity allowed only in the isolated local PG17 clone';
 END IF;
 IF to_regclass('atlas.work_items') IS NULL
   OR to_regclass('ledger.booking_requests') IS NULL
   OR to_regclass('ledger.booking_offerings') IS NULL
 THEN RAISE EXCEPTION 'The local clone lacks source tables required by the real native Ledger source';
 END IF;
 IF to_regprocedure('atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)')
      IS NOT NULL
    AND (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=
      to_regprocedure('atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)'))
      IS DISTINCT FROM '7570082f04024397227545e685a4c071'
 THEN RAISE EXCEPTION 'Existing local native Ledger source conflicts with the actual verified live source';
 END IF;
END;
$r01_clone_prereq$;

-- Exact installed definition; restoring its source shape in the test
-- transaction is NOT a signed authorization or evidence of full schema parity.
CREATE OR REPLACE FUNCTION atlas.company_work_native_ledger_exact_source_v1(
 p_work_item_id uuid, p_ledger_id uuid)
 RETURNS TABLE(source_schema text, source_table text, source_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select 'ledger'::text,'booking_requests'::text,b.id
  from atlas.work_items w
  join ledger.booking_requests b
    on w.source_object_type='ledger_booking_request'
   and w.source_object_id=b.id
  where w.id=p_work_item_id and b.ledger_id=p_ledger_id
  union all
  select 'ledger'::text,'booking_offerings'::text,o.id
  from atlas.work_items w
  join ledger.booking_offerings o
    on w.source_object_type='ledger_booking_offering'
   and w.source_object_id=o.id
  where w.id=p_work_item_id and o.ledger_id=p_ledger_id;
$function$;

DO $r01_clone_source$
BEGIN
 IF (SELECT md5(p.prosrc) FROM pg_proc p
      WHERE p.oid='atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)'::regprocedure)
       IS DISTINCT FROM '7570082f04024397227545e685a4c071'
 THEN RAISE EXCEPTION 'R01 local source parity digest differs from installed Noel source';
 END IF;
END;
$r01_clone_source$;
