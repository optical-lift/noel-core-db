-- Source-custody postconditions for the canonical combined migration.
-- Read-only; no fixtures, production data, publication or permission changes.
DO $postconditions$
DECLARE
  v_func regprocedure;
  v_role text;
  v_policy_count int;
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='transcript_core'
      AND t.typname='asset_provenance_class' AND e.enumlabel='manuscript_source'
  ) THEN RAISE EXCEPTION 'Native authored manuscript source type absent'; END IF;

  IF to_regclass('transcript_core.delivery_package_artifacts') IS NULL OR
    NOT EXISTS (
      SELECT 1 FROM pg_class
      WHERE oid='transcript_core.delivery_package_artifacts'::regclass AND relrowsecurity
    ) THEN RAISE EXCEPTION 'Private listening binding table/RLS missing'; END IF;
  IF EXISTS(SELECT 1 FROM transcript_core.delivery_package_artifacts) THEN
    RAISE EXCEPTION 'Migration must not seed canonical media artifacts'; END IF;
  IF (SELECT count(*) FROM pg_policies
      WHERE schemaname='storage' AND tablename='objects'
      AND policyname LIKE 'transcript_core_manuscript_original_%_v1')<>4
    OR (SELECT count(*) FROM pg_policies
      WHERE schemaname='storage' AND tablename='objects'
      AND policyname LIKE 'transcript_core_listening_render_%_v1')<>4 THEN
    RAISE EXCEPTION 'Exact guarded native source and render Storage policies required'; END IF;
  IF EXISTS(
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
    AND (policyname LIKE 'transcript_core_manuscript_original_%_v1'
      OR policyname LIKE 'transcript_core_listening_render_%_v1')
      AND (permissive <> 'RESTRICTIVE'
        AND policyname NOT IN ('transcript_core_listening_render_insert_v1'))
  ) THEN RAISE EXCEPTION 'Expected restrictive private Storage policies missing'; END IF;

  FOREACH v_func IN ARRAY ARRAY[
    'transcript_core.register_verified_manuscript_original_v1(uuid,uuid,text,text,bigint,text)'::regprocedure,
    'transcript_core.require_verified_listening_object_v1(uuid,uuid,text,text,text,bigint)'::regprocedure,
    'transcript_core.register_verified_listening_render_v1(uuid,storage.objects,text,text,bigint)'::regprocedure,
    'transcript_core.complete_verified_listening_production_v1(uuid,uuid,integer,uuid,text,jsonb,jsonb,jsonb)'::regprocedure,
    'transcript_core.bind_verified_listening_delivery_artifact_v1(uuid,uuid,text,bigint,text,text)'::regprocedure
  ] LOOP
    IF (SELECT prosecdef FROM pg_proc WHERE oid=v_func) THEN
      RAISE EXCEPTION 'Unexpected privileged private receipt registration function: %',v_func;
    END IF;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      IF has_function_privilege(v_role,v_func,'EXECUTE') THEN
        RAISE EXCEPTION 'Unexpected client or service-role private completion grant';
      END IF;
    END LOOP;
  END LOOP;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_table_privilege(v_role,'transcript_core.delivery_package_artifacts','SELECT')
       OR has_table_privilege(v_role,'transcript_core.delivery_package_artifacts','INSERT')
       OR has_table_privilege(v_role,'transcript_core.delivery_package_artifacts','UPDATE')
       OR has_table_privilege(v_role,'transcript_core.delivery_package_artifacts','DELETE')
    THEN RAISE EXCEPTION 'Unexpected exposed private artifact binding'; END IF;
  END LOOP;
END $postconditions$;
SELECT 'PASS source-owned manuscript + listening candidate: private source, exact ACL and zero-seed release postconditions' AS result;
