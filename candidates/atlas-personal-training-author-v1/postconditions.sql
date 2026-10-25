-- Structural security checks on isolated PostgreSQL, not a production-release receipt.
DO $test$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  WHERE s.nspname='atlas' AND c.relname IN
   ('personal_training_programs','personal_training_program_versions','personal_training_program_edit_receipts') AND c.relrowsecurity;
 IF n<>3 THEN RAISE EXCEPTION 'Program table RLS missing'; END IF;
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='public' AND p.proname LIKE 'personal_training_author_%_self_api_v1'
   AND p.prosecdef;
 IF n<>4 THEN RAISE EXCEPTION 'Expected four definer public Program RPCs, found %',n; END IF;
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='public' AND p.proname LIKE 'personal_training_author_%_self_api_v1'
   AND has_function_privilege('anon',p.oid,'EXECUTE');
 IF n<>0 THEN RAISE EXCEPTION 'Anonymous Program execute privilege leak'; END IF;
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  WHERE s.nspname='atlas' AND c.relname IN
   ('personal_training_programs','personal_training_program_versions','personal_training_program_edit_receipts')
   AND (has_table_privilege('anon',c.oid,'SELECT')
    OR has_table_privilege('authenticated',c.oid,'SELECT')
    OR has_table_privilege('authenticated',c.oid,'UPDATE')
    OR has_table_privilege('authenticated',c.oid,'INSERT'));
 IF n<>0 THEN RAISE EXCEPTION 'Direct Program table privilege leaked'; END IF;
END;
$test$;
