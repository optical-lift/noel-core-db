-- ACCESS-03C-PRE1 independent read-only postconditions for a disposable clone.
DO $access03c_pre1_postconditions$
BEGIN
  IF to_regprocedure('atlas.tending_task_context_v1(uuid,uuid,text)') IS NOT NULL
    OR to_regprocedure('atlas.tending_card_json_v1(uuid,jsonb,boolean)') IS NOT NULL
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 exact old pair not retired'; END IF;

  -- Current v2 legacy farm paths must not silently disappear with the v1 pair.
  IF md5(pg_catalog.pg_get_functiondef(
          'atlas.tending_task_context_v2(uuid,uuid,text,text)'::regprocedure))
         IS DISTINCT FROM '48a972d24a0b168211fbde6d8e6eb5d0'
    OR md5(pg_catalog.pg_get_functiondef(
          'atlas.tending_card_json_v2(uuid,uuid,jsonb,boolean)'::regprocedure))
         IS DISTINCT FROM '5621f5f54676f0310f54ea726cf7340e'
    OR md5(pg_catalog.pg_get_functiondef(
          'atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure))
         IS DISTINCT FROM 'ac9f651584032997fb5106433190e245'
    OR to_regprocedure('atlas.zone_registry_source_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.farm_care_zone_v1(uuid,text,integer)') IS NULL
    OR to_regclass('atlas.tending_task_track_v1') IS NULL
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 retained native and legacy reader source changed'; END IF;

  IF to_regclass('atlas.tasks') IS NULL
    OR to_regclass('atlas.zones') IS NULL
    OR to_regclass('atlas.growing_objects') IS NULL
    OR to_regclass('atlas.crop_cycles') IS NULL
    OR to_regclass('atlas.care_state_history') IS NULL
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 canonical work and physical records missing'; END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE p.prokind='f'
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND p.oid<> 'atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure
      AND (position('tending_task_context_v1' in pg_catalog.pg_get_functiondef(p.oid))>0
        OR position('tending_card_json_v1' in pg_catalog.pg_get_functiondef(p.oid))>0)
  ) THEN RAISE EXCEPTION 'ACCESS03C-PRE1 residual runtime function-body use'; END IF;

  IF to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NULL
    OR has_table_privilege('authenticated','atlas.zones','SELECT')
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 ACCESS03A/03B governance was not retained'; END IF;
END
$access03c_pre1_postconditions$;
