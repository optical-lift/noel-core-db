-- Schema-clone gate for the native Person-to-Ledger connection reader.
-- The migration is additive and must not delete a credential or employee seat.
DO $check$
DECLARE v_source text;
BEGIN
 SELECT pg_get_functiondef(p.oid) INTO v_source
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas'
   AND p.proname='native_connected_ledger_access_self_api_v1'
   AND p.pronargs=0;

 IF v_source IS NULL THEN
   RAISE EXCEPTION 'Native connected Ledger reader missing';
 END IF;
 IF position('auth.uid()' in v_source)=0 OR
    position('current_person_id_v1()' in v_source)=0 OR
    position('current_principal_id_v1()' in v_source)=0 OR
    position('ledger.seats' in v_source)=0 OR
    position('reality.entities' in v_source)=0 OR
    position('atlas.ledger_organization_participations' in v_source)=0 THEN
   RAISE EXCEPTION 'Authenticated native Person-Ledger connection proof incomplete';
 END IF;
 IF position('organization_employee_seats' in v_source)>0 OR
    position('employee_seat_id' in v_source)>0 OR
    position('organization_memberships' in v_source)>0 OR
    position('organization_member_credentials' in v_source)>0 THEN
   RAISE EXCEPTION 'Native connection reader unexpectedly relies on legacy membership or seat';
 END IF;
 IF NOT has_function_privilege('authenticated',
   'atlas.native_connected_ledger_access_self_api_v1()', 'EXECUTE') THEN
   RAISE EXCEPTION 'Authenticated-only native access RPC is not callable';
 END IF;
 IF has_function_privilege('anon',
   'atlas.native_connected_ledger_access_self_api_v1()', 'EXECUTE') THEN
   RAISE EXCEPTION 'Unauthenticated direct access to Person connection RPC';
 END IF;
 IF NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='atlas' AND c.relname='organization_member_credentials'
 ) THEN
   RAISE EXCEPTION 'Credential source unexpectedly removed';
 END IF;
 IF to_regclass('atlas.organization_employee_seats') IS NULL THEN
   RAISE EXCEPTION 'Legacy seat retirement is a separate audited release';
 END IF;
END
$check$;
