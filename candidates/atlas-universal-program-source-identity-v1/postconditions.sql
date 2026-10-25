DO $t$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='public'
  AND p.proname IN ('personal_program_author_create_distinct_self_api_v1',
                   'personal_program_author_same_sources_self_api_v1')
  AND has_function_privilege('anon',p.oid,'EXECUTE');
 IF n<>0 THEN RAISE EXCEPTION 'Unauthenticated source identity lookup or fork'; END IF;
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='atlas' AND c.relname='personal_program_author_distinct_import_decisions'
  AND c.relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT')
  AND NOT has_table_privilege('anon',c.oid,'SELECT');
 IF n<>1 THEN RAISE EXCEPTION 'Fork audit table is not private'; END IF;
 SELECT count(*) INTO n FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='atlas' AND c.relname='personal_program_author_distinct_import_decisions'
 AND t.tgname='personal_program_distinct_immutable_v1';
 IF n<>1 THEN RAISE EXCEPTION 'Fork author decisions not immutable'; END IF;
 SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='atlas' AND c.relname='personal_program_author_source_receipts'
  AND c.relrowsecurity AND NOT has_table_privilege('authenticated',c.oid,'SELECT')
  AND NOT has_table_privilege('anon',c.oid,'SELECT');
 IF n<>1 THEN RAISE EXCEPTION 'Source history receipts are not private'; END IF;
 SELECT count(*) INTO n FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 JOIN pg_namespace ns ON ns.oid=c.relnamespace
 WHERE ns.nspname='atlas' AND c.relname='personal_program_author_source_receipts'
   AND t.tgname='personal_program_source_receipts_immutable_v1';
 IF n<>1 THEN RAISE EXCEPTION 'Source identity history is not immutable'; END IF;
END;
$t$;