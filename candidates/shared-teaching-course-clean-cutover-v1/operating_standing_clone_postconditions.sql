-- Held M3.5 synthetic/clone assertions: proposals not institutional power.
DO $institutional_proposals$
DECLARE i record;
BEGIN
 IF to_regclass('atlas.teaching_course_operating_standings') IS NULL THEN
  RAISE EXCEPTION 'single-Course operating relationship table missing';
 END IF;
 IF NOT EXISTS (
  SELECT 1 FROM pg_class
  WHERE oid='atlas.teaching_course_operating_standings'::regclass
    AND relrowsecurity
 ) THEN RAISE EXCEPTION 'private operating relation RLS absent'; END IF;
 IF has_table_privilege('authenticated',
    'atlas.teaching_course_operating_standings','SELECT')
 OR has_table_privilege('authenticated',
    'atlas.teaching_course_operating_standings','INSERT')
 OR has_table_privilege('anon',
    'atlas.teaching_course_operating_standings','SELECT')
 THEN RAISE EXCEPTION 'Course operating proposal table exposed'; END IF;
 FOR i IN SELECT * FROM (VALUES
  ('public.shared_teaching_course_operating_propose_self_api_v1(uuid,uuid,uuid)'),
  ('public.shared_teaching_course_operating_withdraw_self_api_v1(uuid,uuid)'),
  ('public.shared_teaching_course_operating_proposals_self_api_v1(uuid)')
 ) t(signature)
 LOOP
  IF to_regprocedure(i.signature) IS NULL
   OR NOT has_function_privilege('authenticated',i.signature,'EXECUTE')
   OR has_function_privilege('anon',i.signature,'EXECUTE') THEN
   RAISE EXCEPTION 'unsafe operating proposal RPC privileges';
  END IF;
 END LOOP;
 IF to_regprocedure('public.shared_teaching_course_operating_accept_self_api_v1(uuid)')
 IS NOT NULL THEN
  RAISE EXCEPTION 'institution accept operation must remain held';
 END IF;
 IF EXISTS (
  SELECT 1 FROM pg_constraint k
  WHERE k.conrelid='atlas.teaching_course_operating_standings'::regclass
    AND k.contype='f' AND k.confrelid='atlas.ledgers'::regclass
 ) THEN
  RAISE EXCEPTION 'institutional Course standing depends on old atlas.ledgers';
 END IF;
END
$institutional_proposals$;
