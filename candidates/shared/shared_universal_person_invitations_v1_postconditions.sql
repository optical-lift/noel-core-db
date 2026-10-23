BEGIN;
DO $test$
DECLARE v int;
BEGIN
 SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname IN (
  'prepare_universal_person_invitation_self_api_v1',
  'issue_universal_person_invitation_self_api_v1',
  'inspect_universal_person_invitation_self_api_v1',
  'claim_universal_person_invitation_self_api_v1',
  'decline_universal_person_invitation_self_api_v1',
  'transition_universal_person_invitation_self_api_v1',
  'list_universal_person_invitations_self_api_v1',
  'universal_person_invitation_history_self_api_v1');
 IF v<>8 THEN RAISE EXCEPTION 'Eight universal Person invitation RPCs required'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE '%universal_person_invitation%'
 AND (p.prosecdef OR has_function_privilege('anon',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Universal invitation membrane exposed to anonymous/definer'; END IF;
 IF has_table_privilege('authenticated','atlas.universal_person_invitations','SELECT')
 OR has_table_privilege('authenticated','atlas.universal_person_invitation_events','SELECT')
 THEN RAISE EXCEPTION 'Private invitations/events directly exposed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n
 ON n.oid=c.relnamespace WHERE n.nspname='atlas'
  AND c.relname='universal_person_invitations' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'Private invitation table RLS absent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='atlas'
  AND indexname='universal_person_invitation_one_open_v1')
 THEN RAISE EXCEPTION 'One pending invitation uniqueness absent'; END IF;
END $test$;
COMMIT;