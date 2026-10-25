-- Candidate-side security and coexisting contract checks.
DO $test$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='public'
 AND p.proname IN ('personal_program_author_create_self_api_v2',
                  'personal_program_author_save_self_api_v2',
                  'personal_program_author_approve_self_api_v2',
                  'personal_program_author_read_self_api_v2')
 AND p.prosecdef;
 IF n<>4 THEN RAISE EXCEPTION 'Missing v2 guarded Program author commands'; END IF;
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='public'
 AND p.proname IN ('personal_program_author_create_self_api_v2',
                  'personal_program_author_save_self_api_v2',
                  'personal_program_author_approve_self_api_v2',
                  'personal_program_author_read_self_api_v2')
 AND has_function_privilege('anon',p.oid,'EXECUTE');
 IF n<>0 THEN RAISE EXCEPTION 'Program v2 anonymous authorization leak'; END IF;
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='atlas' AND c.relname IN (
 'personal_training_programs','personal_training_program_versions',
 'personal_training_program_edit_receipts') AND c.relrowsecurity
 AND NOT has_table_privilege('authenticated',c.oid,'SELECT')
 AND NOT has_table_privilege('anon',c.oid,'SELECT');
 IF n<>3 THEN RAISE EXCEPTION 'Original author Program table privacy altered'; END IF;
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='atlas' AND c.relkind='r' AND c.relname LIKE 'personal%program%';
 IF n<>3 THEN RAISE EXCEPTION 'Unexpected parallel author Program store detected'; END IF;
END;
$test$;
