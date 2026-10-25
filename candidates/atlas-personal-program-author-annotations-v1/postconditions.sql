-- Run only in a disposable production-shaped schema clone AFTER candidate.sql.
-- Static proof does not replace independently signed GoTrue/PostgREST owner/outsider tests.
DO $test$
DECLARE v_count integer;
BEGIN
 SELECT count(*) INTO v_count FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='atlas' AND c.relname='personal_program_author_note_events'
 AND c.relrowsecurity AND c.relforcerowsecurity;
 IF v_count<>1 THEN RAISE EXCEPTION 'Private annotation event table missing RLS'; END IF;

 IF has_table_privilege('anon','atlas.personal_program_author_note_events','SELECT')
 OR has_table_privilege('authenticated','atlas.personal_program_author_note_events','SELECT')
 OR has_table_privilege('service_role','atlas.personal_program_author_note_events','SELECT')
 OR has_table_privilege('authenticated','atlas.personal_program_author_note_events','INSERT')
 THEN RAISE EXCEPTION 'Annotation table grants exceeded API membrane'; END IF;

 SELECT count(*) INTO v_count FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN
 ('personal_program_author_note_create_self_api_v1',
 'personal_program_author_note_revise_self_api_v1',
 'personal_program_author_notes_read_self_api_v1')
 AND p.prosecdef AND has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE');
 IF v_count<>3 THEN RAISE EXCEPTION 'Owner-only public annotation API not admitted'; END IF;

 SELECT count(*) INTO v_count FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname IN
 ('personal_program_author_note_guard_v1',
 'personal_program_author_note_create_self_v1',
 'personal_program_author_note_revise_self_v1',
 'personal_program_author_notes_read_self_v1')
 AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE');
 IF v_count<>4 THEN RAISE EXCEPTION 'Private internal annotation RPC was exposed'; END IF;

 -- New code must never edit the existing approved Program/version contracts.
 SELECT count(*) INTO v_count FROM pg_catalog.pg_constraint c
 JOIN pg_catalog.pg_class t ON t.oid=c.conrelid
 JOIN pg_catalog.pg_namespace n ON n.oid=t.relnamespace
 WHERE n.nspname='atlas' AND t.relname='personal_program_author_note_events'
 AND c.conname IN ('program_note_revision_unique',
                   'program_note_request_unique',
                   'program_note_component_key_bound',
                   'program_note_excerpt_bound');
 IF v_count<>4 THEN RAISE EXCEPTION 'Event or annotation anchor constraints absent'; END IF;

 IF EXISTS(SELECT 1 FROM atlas.personal_program_author_note_events
  WHERE visibility<>'author_private' OR standing NOT IN ('open','resolved','superseded'))
 THEN RAISE EXCEPTION 'Annotation privacy/standing contract violated'; END IF;
END;
$test$;
