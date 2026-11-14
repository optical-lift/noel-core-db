-- M3 canonical authoring postconditions. Read-only, synthetic/clone only.
-- Never treat this catalog check as genuine GoTrue signed browser proof.
DO $m3_gate$
DECLARE i record;
BEGIN
 IF to_regprocedure('atlas.require_private_course_author_self_v1(uuid,boolean)') IS NULL THEN
  RAISE EXCEPTION 'canonical author source guard absent';
 END IF;
 FOR i IN SELECT * FROM (VALUES
 ('public.shared_teaching_course_catalog_self_api_v1()'),
 ('public.shared_teaching_course_material_read_self_api_v1(uuid)'),
 ('public.shared_teaching_course_material_save_self_api_v1(uuid,uuid,integer,text)'),
 ('public.shared_teaching_course_outline_read_self_api_v1(uuid)'),
 ('public.shared_teaching_course_unit_create_self_api_v1(uuid,uuid,text,text)'),
 ('public.shared_teaching_course_unit_move_self_api_v1(uuid,uuid,text)'),
 ('public.shared_teaching_course_unit_read_self_api_v1(uuid)'),
 ('public.shared_teaching_course_unit_save_self_api_v1(uuid,uuid,integer,text)')
 ) t(signature)
 LOOP
  IF to_regprocedure(i.signature) IS NULL
   OR NOT has_function_privilege('authenticated',i.signature,'EXECUTE')
   OR has_function_privilege('anon',i.signature,'EXECUTE') THEN
   RAISE EXCEPTION 'unsafe or missing source RPC grant';
  END IF;
 END LOOP;
 IF has_function_privilege('authenticated',
      'atlas.require_private_course_author_self_v1(uuid,boolean)','EXECUTE')
 OR has_function_privilege('anon',
      'atlas.require_private_course_author_self_v1(uuid,boolean)','EXECUTE') THEN
  RAISE EXCEPTION 'private source guard is publicly executable';
 END IF;
 IF has_table_privilege('authenticated','atlas.teaching_courses','SELECT')
 OR has_table_privilege('authenticated','atlas.teaching_course_units','SELECT')
 OR has_table_privilege('authenticated',
     'atlas.teaching_course_manuscript_revisions','INSERT')
 OR has_table_privilege('authenticated',
     'atlas.teaching_course_unit_revisions','UPDATE')
 OR has_table_privilege('anon','atlas.teaching_course_units','SELECT') THEN
  RAISE EXCEPTION 'canonical source table directly exposed';
 END IF;
 IF EXISTS(
  SELECT 1 FROM pg_class c
  WHERE c.oid IN ('atlas.teaching_courses'::regclass,
   'atlas.teaching_course_units'::regclass,
   'atlas.teaching_course_manuscript_revisions'::regclass,
   'atlas.teaching_course_unit_revisions'::regclass)
  AND NOT c.relrowsecurity
 ) THEN
  RAISE EXCEPTION 'canonical teaching source RLS missing';
 END IF;
END
$m3_gate$;
