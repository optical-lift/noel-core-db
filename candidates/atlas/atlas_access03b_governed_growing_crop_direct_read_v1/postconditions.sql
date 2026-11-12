-- ACCESS-03B disposable clone postconditions: never write or mutate rows.
DO $access03b_post$
DECLARE
  v_target record;
BEGIN
  IF to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_proc p
       WHERE p.oid='atlas.can_read_native_governed_farm_full_self_v1(uuid)'::regprocedure
         AND p.prosecdef AND p.provolatile='s'
         AND pg_catalog.pg_get_functiondef(p.oid)
             LIKE '%PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id)%'
     )
     OR NOT has_function_privilege('authenticated',
          'atlas.can_read_native_governed_farm_full_self_v1(uuid)','EXECUTE')
     OR has_function_privilege('anon',
          'atlas.can_read_native_governed_farm_full_self_v1(uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'ACCESS03B source-only boolean native guard missing or too broad';
  END IF;
  IF (SELECT count(*) FROM pg_catalog.pg_policies
      WHERE schemaname='atlas' AND tablename IN ('growing_objects','crop_cycles')) <> 2
  THEN RAISE EXCEPTION 'ACCESS03B unexpected target policies after repair';
  END IF;
  FOR v_target IN SELECT * FROM (VALUES
      ('growing_objects'::text,'growing_objects_read_operations'::text),
      ('crop_cycles'::text,'crop_cycles_read_operations'::text)
  ) AS x(tablename,policyname)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_policies p
       JOIN pg_catalog.pg_class c
         ON c.oid=(format('%I.%I','atlas',v_target.tablename))::regclass
       WHERE p.schemaname='atlas' AND p.tablename=v_target.tablename
         AND p.policyname=v_target.policyname AND p.cmd='SELECT'
         AND p.roles::text='{authenticated}'
         AND p.qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)'
         AND c.relrowsecurity)
       OR NOT has_table_privilege('authenticated',
           format('%I.%I','atlas',v_target.tablename),'SELECT')
       OR has_table_privilege('anon',
           format('%I.%I','atlas',v_target.tablename),'SELECT')
    THEN RAISE EXCEPTION 'ACCESS03B repaired table RLS/ACL postcondition failed: %',
       v_target.tablename;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas'
        AND c.relname IN ('farm_care_object_state_v1','v_farm_object_operational_state')
        AND c.relkind='v'
        AND 'security_invoker=true'=ANY(c.reloptions)
        AND has_table_privilege('authenticated',c.oid,'SELECT')) <> 2
  THEN
    RAISE EXCEPTION 'ACCESS03B dependent invoker views lost original view ACL';
  END IF;
  IF md5(pg_catalog.pg_get_functiondef(
       'atlas.require_governed_farm_full_disclosure_self_v1(uuid)'::regprocedure
     )) <> 'cbcc8e98ac2530c60389c4f111793a5f'
     OR md5(pg_catalog.pg_get_functiondef(
       'atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)'::regprocedure
     )) <> '429fa9bc47f4a4e17188b9d8d0b91167'
     OR has_table_privilege('authenticated','atlas.zones','SELECT')
     OR has_table_privilege('authenticated','atlas.v_crop_cycle_registry','SELECT')
  THEN
    RAISE EXCEPTION 'ACCESS03B prior native/zone source authorization changed';
  END IF;
END
$access03b_post$;
