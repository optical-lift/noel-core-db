-- Run ONLY against isolated production-schema clone after generated migration.
-- No public client may read/write the private translation map or invoke its readers.
DO $audit$
DECLARE n_tables int;n_rls int;n_functions int;n_exposed int;n_private int;
        bogus jsonb;reverse jsonb;
BEGIN
 SELECT count(*) INTO n_tables FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='draft' AND c.relkind='r' AND c.relname IN (
  'noel_mark_lxx_choice_occurrences_v1',
  'noel_mark_song_anchor_choices_v1',
  'noel_mark_translation_constraints_v1',
  'noel_mark_translation_constraint_witnesses_v1');
 IF n_tables<>4 THEN RAISE EXCEPTION 'Expected 4 private translation tables, found %',n_tables; END IF;

 SELECT count(*) INTO n_rls FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='draft' AND c.relkind='r' AND c.relrowsecurity
 AND c.relname IN (
  'noel_mark_lxx_choice_occurrences_v1','noel_mark_song_anchor_choices_v1',
  'noel_mark_translation_constraints_v1','noel_mark_translation_constraint_witnesses_v1');
 IF n_rls<>4 THEN RAISE EXCEPTION 'Expected RLS on all 4 tables, found %',n_rls; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger t
  JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='draft' AND c.relname='noel_mark_translation_constraints_v1'
  AND t.tgname='noel_mark_translation_permission_guard_v1' AND NOT t.tgisinternal
 ) THEN RAISE EXCEPTION 'Missing anti-invention Song priority/canon exclusion trigger'; END IF;

 SELECT count(*) INTO n_functions FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='draft'
 AND p.proname IN ('get_noel_mark_translation_reality_v1','get_noel_greek_to_hebrew_marks_v1')
 AND p.provolatile='s' AND p.prosecdef=false
 AND 'search_path=""'=ANY(coalesce(p.proconfig,ARRAY[]::text[]));
 IF n_functions<>2 THEN RAISE EXCEPTION 'Expected 2 stable security-invoker private readers with empty search_path, found %',n_functions; END IF;

 SELECT count(*) INTO n_exposed
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN (VALUES ('anon'),('authenticated')) role(role_name)
 WHERE n.nspname='draft' AND c.relname IN (
 'noel_mark_lxx_choice_occurrences_v1','noel_mark_song_anchor_choices_v1',
 'noel_mark_translation_constraints_v1','noel_mark_translation_constraint_witnesses_v1')
 AND (has_table_privilege(role.role_name,c.oid,'SELECT')
 OR has_table_privilege(role.role_name,c.oid,'INSERT')
 OR has_table_privilege(role.role_name,c.oid,'UPDATE')
 OR has_table_privilege(role.role_name,c.oid,'DELETE'));
 IF n_exposed>0 THEN RAISE EXCEPTION 'Client roles can access Noel private tables: %',n_exposed; END IF;

 SELECT count(*) INTO n_private FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 CROSS JOIN (VALUES ('anon'),('authenticated')) role(role_name)
 WHERE n.nspname='draft' AND p.proname IN ('get_noel_mark_translation_reality_v1','get_noel_greek_to_hebrew_marks_v1')
 AND has_function_privilege(role.role_name,p.oid,'EXECUTE');
 IF n_private>0 THEN RAISE EXCEPTION 'Client roles can execute Noel private readers: %',n_private; END IF;

 SELECT draft.get_noel_mark_translation_reality_v1('__missing_source_token_fixture__',5) INTO bogus;
 IF (bogus->>'found')::boolean IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Reader invented a Hebrew source identity'; END IF;

 SELECT draft.get_noel_greek_to_hebrew_marks_v1('__missing_lxx_lexeme_fixture__',5) INTO reverse;
 IF jsonb_array_length(reverse->'hebrew_marks')<>0
 THEN RAISE EXCEPTION 'Reverse reader invented Hebrew crossreferences'; END IF;
END
$audit$;