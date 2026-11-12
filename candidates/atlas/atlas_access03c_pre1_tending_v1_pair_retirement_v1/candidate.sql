-- ACCESS-03C-PRE1 SOURCE ONLY: pair-retire two inherited Tending v1 functions.
-- NOT a migration, production release, permission grant or client acceptance.
-- Requires separately released ACCESS-03B and an independently accepted
-- current-schema signed clone. Never run against live production during review.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
DO $access03c_pre1_preflight$
DECLARE
  v_context oid := to_regprocedure('atlas.tending_task_context_v1(uuid,uuid,text)');
  v_card oid := to_regprocedure('atlas.tending_card_json_v1(uuid,jsonb,boolean)');
  v_audit oid := to_regprocedure('atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)');
  v_candidate record;
BEGIN
  -- An unmerged RLS candidate is not a released security prerequisite.
  IF to_regprocedure('atlas.can_read_native_governed_farm_full_self_v1(uuid)') IS NULL
    OR (SELECT count(*) FROM pg_catalog.pg_policies
        WHERE schemaname='atlas'
          AND ((tablename='growing_objects' AND policyname='growing_objects_read_operations')
            OR (tablename='crop_cycles' AND policyname='crop_cycles_read_operations'))
          AND cmd='SELECT'
          AND qual='atlas.can_read_native_governed_farm_full_self_v1(farm_id)') <> 2
    OR has_table_privilege('authenticated','atlas.zones','SELECT')
  THEN
    RAISE EXCEPTION 'ACCESS03C-PRE1 requires separately released ACCESS03B with ACCESS03A zone denial';
  END IF;

  IF v_context IS NULL OR v_card IS NULL OR v_audit IS NULL
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 expected function identities absent'; END IF;

  FOR v_candidate IN SELECT * FROM (VALUES
    ('atlas.tending_task_context_v1(uuid,uuid,text)'::text,
     '26ca1f7a3d1a16f1fc5b1aed9f2fae42'::text,true,true,false),
    ('atlas.tending_card_json_v1(uuid,jsonb,boolean)',
     '510f783e3162b1052b6081fb8fa3271b',false,false,true)
  ) t(signature,source_md5,is_definer,allow_authenticated,allow_service_role)
  LOOP
    IF md5(pg_catalog.pg_get_functiondef(to_regprocedure(v_candidate.signature)))
          IS DISTINCT FROM v_candidate.source_md5
      OR (SELECT p.prosecdef FROM pg_catalog.pg_proc p
            WHERE p.oid=to_regprocedure(v_candidate.signature))
          IS DISTINCT FROM v_candidate.is_definer
      OR has_function_privilege('authenticated',to_regprocedure(v_candidate.signature),'EXECUTE')
          IS DISTINCT FROM v_candidate.allow_authenticated
      OR has_function_privilege('service_role',to_regprocedure(v_candidate.signature),'EXECUTE')
          IS DISTINCT FROM v_candidate.allow_service_role
      OR has_function_privilege('anon',to_regprocedure(v_candidate.signature),'EXECUTE')
    THEN RAISE EXCEPTION 'ACCESS03C-PRE1 definition/security/ACL drift: %',v_candidate.signature;
    END IF;
  END LOOP;

  -- The effective-disclosure API is a source-reviewed *literal list*
  -- of broad retired-reader names, not permission to call them.
  -- Keep this exact source and Atlas's corresponding validator intact.
  IF md5(pg_catalog.pg_get_functiondef(v_audit)) IS DISTINCT FROM
       'ac9f651584032997fb5106433190e245'
    OR position('''tending_task_context_v1''' in pg_catalog.pg_get_functiondef(v_audit))=0
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 governor disclosure audit source drift'; END IF;

  -- RESTRICT catches catalog dependencies, but PL/pgSQL function-body
  -- references must also be checked explicitly across non-system schemas.
  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_depend d
    WHERE d.refobjid=ANY(ARRAY[v_context,v_card])
      AND d.deptype NOT IN ('i','e')
  ) THEN RAISE EXCEPTION 'ACCESS03C-PRE1 unexpected catalog dependency'; END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE p.prokind='f'
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND p.oid<>ALL(ARRAY[v_context,v_card,v_audit])
      AND (position('tending_task_context_v1' in pg_catalog.pg_get_functiondef(p.oid))>0
        OR position('tending_card_json_v1' in pg_catalog.pg_get_functiondef(p.oid))>0)
  ) THEN RAISE EXCEPTION 'ACCESS03C-PRE1 unexpected runtime function-body consumer'; END IF;

  -- Do not confuse the legacy v2 Tending interface with universal Work.
  -- Retain it unchanged for known old farm-atlas callers until separately cut over.
  IF md5(pg_catalog.pg_get_functiondef(
          'atlas.tending_task_context_v2(uuid,uuid,text,text)'::regprocedure))
         IS DISTINCT FROM '48a972d24a0b168211fbde6d8e6eb5d0'
    OR md5(pg_catalog.pg_get_functiondef(
          'atlas.tending_card_json_v2(uuid,uuid,jsonb,boolean)'::regprocedure))
         IS DISTINCT FROM '5621f5f54676f0310f54ea726cf7340e'
    OR to_regclass('atlas.tending_task_track_v1') IS NULL
    OR to_regprocedure('atlas.zone_registry_source_v1(uuid)') IS NULL
    OR to_regprocedure('atlas.farm_care_zone_v1(uuid,text,integer)') IS NULL
  THEN RAISE EXCEPTION 'ACCESS03C-PRE1 retained readers/source drift'; END IF;
END
$access03c_pre1_preflight$;

-- Only the exact two verified functions; never CASCADE.
DROP FUNCTION atlas.tending_task_context_v1(uuid,uuid,text) RESTRICT;
DROP FUNCTION atlas.tending_card_json_v1(uuid,jsonb,boolean) RESTRICT;
COMMIT;
