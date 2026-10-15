-- Public-safe executable postconditions for the disposable production-schema clone ONLY.
-- No founder definitions or private token surfaces in log output.
DO $verify$
DECLARE
  v_exists integer;
  v_exposed integer;
  v_wrong_auth integer;
  v_lookup jsonb;
  v_queue jsonb;
BEGIN
 SELECT count(*) INTO v_exists
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='draft' AND
  ((p.proname='get_noel_mark_occurrence_context_v1'
    AND pg_get_function_identity_arguments(p.oid)='p_source_token_id text, p_form_limit integer')
   OR (p.proname='get_noel_mark_collision_review_queue_v1'
    AND pg_get_function_identity_arguments(p.oid)='p_limit integer, p_offset integer'));
 IF v_exists<>2 THEN
  RAISE EXCEPTION 'Expected both private Noel mark readers, found %',v_exists;
 END IF;
 SELECT count(*) INTO v_wrong_auth FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='draft'
  AND p.proname IN ('get_noel_mark_occurrence_context_v1','get_noel_mark_collision_review_queue_v1')
  AND (p.prosecdef OR p.provolatile='v'
    OR NOT ('search_path='=ANY(coalesce(p.proconfig,ARRAY[]::text[]))));
 IF v_wrong_auth<>0 THEN RAISE EXCEPTION 'Reader privileges/volatility/search path contract failed'; END IF;
 SELECT count(*) INTO v_exposed FROM pg_proc p
 JOIN pg_namespace n ON n.oid=p.pronamespace
 CROSS JOIN (VALUES('anon'),('authenticated')) roles(role_name)
 WHERE n.nspname='draft' AND p.proname IN
 ('get_noel_mark_occurrence_context_v1','get_noel_mark_collision_review_queue_v1')
 AND has_function_privilege(roles.role_name,p.oid,'EXECUTE');
 IF v_exposed<>0 THEN RAISE EXCEPTION 'Client-executable private Noel mark readers: %',v_exposed; END IF;
 SELECT draft.get_noel_mark_occurrence_context_v1('__noel_nonexistent_fixture__',3) INTO v_lookup;
 IF (v_lookup->>'found')::boolean IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Nonexistent source-token lookup invented an identity';
 END IF;
 SELECT draft.get_noel_mark_collision_review_queue_v1(1,0) INTO v_queue;
 IF NOT (v_queue ? 'total_collision_nmis' AND v_queue ? 'results') THEN
  RAISE EXCEPTION 'Review queue shape missing required members';
 END IF;
END;
$verify$;
