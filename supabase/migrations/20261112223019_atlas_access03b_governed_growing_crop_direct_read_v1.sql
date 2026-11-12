-- Atlas ACCESS-03B SOURCE-ONLY candidate. Never run directly on Production.
-- Retire ONLY legacy manager/owner RLS disclosure on growing_objects and crop_cycles.
-- Preserve authenticated table SELECT for existing SECURITY INVOKER dependent views
-- while limiting actual rows to a genuinely signed native governing Ledger root.
-- Preserve all records, all DML policies, all other tables and view definitions.
BEGIN;

DO $access03b_preflight$
DECLARE
  v_expected record;
BEGIN
  -- Fail closed on ANY additional policy, role or predicate change. Only these
  -- two SELECT policies are in this bounded source candidate.
  IF (SELECT count(*) FROM pg_catalog.pg_policies
      WHERE schemaname='atlas' AND tablename IN ('growing_objects','crop_cycles')) <> 2 THEN
    RAISE EXCEPTION 'ACCESS03B target table policy inventory drift';
  END IF;
  FOR v_expected IN SELECT * FROM (VALUES
    ('growing_objects'::text,'growing_objects_read_operations'::text),
    ('crop_cycles'::text,'crop_cycles_read_operations'::text)
  ) AS x(tablename,policyname)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
        JOIN pg_catalog.pg_class c ON c.oid=(format('%I.%I','atlas',v_expected.tablename))::regclass
        WHERE p.schemaname='atlas' AND p.tablename=v_expected.tablename
          AND p.policyname=v_expected.policyname AND p.cmd='SELECT'
          AND p.roles::text='{authenticated}'
          AND p.qual='atlas.can_read_farm_operations(farm_id)'
          AND c.relrowsecurity AND NOT c.relforcerowsecurity)
       OR NOT has_table_privilege('authenticated',format('%I.%I','atlas',v_expected.tablename),'SELECT')
       OR has_table_privilege('anon',format('%I.%I','atlas',v_expected.tablename),'SELECT')
    THEN
      RAISE EXCEPTION 'ACCESS03B table RLS/ACL baseline drift: %',v_expected.tablename;
    END IF;
  END LOOP;
  IF to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'ACCESS03B proposed helper already exists';
  END IF;
  -- ACCESS-03A and current guarded authorizations must already be in force.
  IF has_table_privilege('authenticated','atlas.zones','SELECT')
     OR has_table_privilege('authenticated','atlas.v_crop_cycle_registry','SELECT')
     OR md5(pg_catalog.pg_get_functiondef(
         'atlas.require_governed_farm_full_disclosure_self_v1(uuid)'::regprocedure
       )) <> 'cbcc8e98ac2530c60389c4f111793a5f'
     OR md5(pg_catalog.pg_get_functiondef(
         'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)'::regprocedure
       )) <> '429fa9bc47f4a4e17188b9d8d0b91167'
  THEN
    RAISE EXCEPTION 'ACCESS03B canonical signed native owner source drift';
  END IF;
  -- Protect the exact view surfaces that were the reason to retain base
  -- SELECT rather than blanket REVOKE. This does NOT itself prove usable UI.
  IF (SELECT count(*) FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas'
        AND c.relname IN ('farm_care_object_state_v1','v_farm_object_operational_state')
        AND c.relkind='v'
        AND 'security_invoker=true'=ANY(c.reloptions)
        AND has_table_privilege('authenticated',c.oid,'SELECT')) <> 2
  THEN
    RAISE EXCEPTION 'ACCESS03B two signed invoker view baselines changed';
  END IF;
END
$access03b_preflight$;

-- A boolean RLS adapter for the EXISTING canonical full-disclosure validator.
-- Never derive authority from legacy role, old membership, user_metadata, or a
-- Ledger seat alone. Only a live native Person/Principal root GOVERNING the
-- farm's active primary organization Ledger can see a full underlying row.
CREATE FUNCTION atlas.can_read_native_governed_farm_full_self_v1(p_farm_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $access03b_guard$
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  RETURN TRUE;
EXCEPTION WHEN SQLSTATE '42501' THEN
  RETURN FALSE;
END
$access03b_guard$;

REVOKE ALL ON FUNCTION atlas.can_read_native_governed_farm_full_self_v1(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION atlas.can_read_native_governed_farm_full_self_v1(uuid)
  TO authenticated;

ALTER POLICY growing_objects_read_operations ON atlas.growing_objects
  USING (atlas.can_read_native_governed_farm_full_self_v1(farm_id));
ALTER POLICY crop_cycles_read_operations ON atlas.crop_cycles
  USING (atlas.can_read_native_governed_farm_full_self_v1(farm_id));
COMMIT;
