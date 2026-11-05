-- UNI-OPS-01 / held Noel native-Ledger verifier schema reconciliation.
-- This is a source-owned validation candidate, not a released migration.
-- The old exact-source SQL helper statically binds retired/absent booking
-- tables at function creation, blocking disposable schema-only assembly.
-- Preserve EXACTLY its allowlist and FK predicates; absent source relations
-- prove NOTHING and must never create source_verified evidence.
-- No owner_attested evidence is promoted or fabricated by this function.
CREATE OR REPLACE FUNCTION atlas.company_work_native_ledger_exact_source_v1(
  p_work_item_id uuid, p_ledger_id uuid
) RETURNS TABLE(source_schema text,source_table text,source_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $exact$
BEGIN
  -- Only execute source-specific SQL if that real native table exists.
  -- Dynamic binding is necessary to support the canonical schema snapshot
  -- without those retired/unapplied historical booking source relations.
  IF pg_catalog.to_regclass('ledger.booking_requests') IS NOT NULL THEN
    RETURN QUERY EXECUTE $booking_request$
      SELECT 'ledger'::text,'booking_requests'::text,b.id
      FROM atlas.work_items w
      JOIN ledger.booking_requests b
        ON w.source_object_type='ledger_booking_request'
       AND w.source_object_id=b.id
      WHERE w.id=$1 AND b.ledger_id=$2
    $booking_request$ USING p_work_item_id,p_ledger_id;
  END IF;
  IF pg_catalog.to_regclass('ledger.booking_offerings') IS NOT NULL THEN
    RETURN QUERY EXECUTE $booking_offering$
      SELECT 'ledger'::text,'booking_offerings'::text,o.id
      FROM atlas.work_items w
      JOIN ledger.booking_offerings o
        ON w.source_object_type='ledger_booking_offering'
       AND w.source_object_id=o.id
      WHERE w.id=$1 AND o.ledger_id=$2
    $booking_offering$ USING p_work_item_id,p_ledger_id;
  END IF;
END;
$exact$;

REVOKE ALL ON FUNCTION atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated,service_role;

-- Fail closed on no-source and do not leak helper execution.
DO $assert$
BEGIN
  IF EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
      'f6000000-0000-4000-8000-000000000001'::uuid,
      'f6000000-0000-4000-8000-000000000002'::uuid)
  ) THEN
    RAISE EXCEPTION 'A missing original cannot verify native Ledger source';
  END IF;
  IF pg_catalog.has_function_privilege('authenticated',
    'atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)','EXECUTE')
    OR pg_catalog.has_function_privilege('anon',
    'atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)','EXECUTE')
  THEN
    RAISE EXCEPTION 'Private exact-source verifier became executable to clients';
  END IF;
  IF pg_catalog.to_regclass('ledger.booking_requests') IS NULL
     AND pg_catalog.to_regclass('ledger.booking_offerings') IS NULL
     AND EXISTS (
       SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
         'f6000000-0000-4000-8000-000000000003'::uuid,
         'f6000000-0000-4000-8000-000000000004'::uuid)
     )
  THEN
    RAISE EXCEPTION 'Absent booking tables cannot produce source verification';
  END IF;
  RAISE NOTICE 'PASS held native-Ledger exact-source verifier fail-closed compatibility';
END;
$assert$;
