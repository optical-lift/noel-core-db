BEGIN;
DO $validation$
DECLARE
 v_fn text;
BEGIN
 IF to_regprocedure('public.personal_atlas_bookplate_self_api_v2()') IS NULL
  OR to_regprocedure('public.set_personal_atlas_bookplate_self_api_v2(jsonb)') IS NULL
  OR to_regprocedure('atlas.personal_atlas_bookplate_self_api_v2()') IS NULL
  OR to_regprocedure('atlas.set_personal_atlas_bookplate_self_api_v2(jsonb)') IS NULL
 THEN RAISE EXCEPTION 'Bookplate v2 public gateway or internal owner-checked function missing'; END IF;
 IF has_function_privilege('anon','public.personal_atlas_bookplate_self_api_v2()','EXECUTE')
  OR has_function_privilege('anon','public.set_personal_atlas_bookplate_self_api_v2(jsonb)','EXECUTE')
  OR has_function_privilege('authenticated','atlas.personal_atlas_bookplate_self_api_v2()','EXECUTE')
  OR has_function_privilege('authenticated','atlas.set_personal_atlas_bookplate_self_api_v2(jsonb)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.personal_atlas_bookplate_self_api_v2()','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.set_personal_atlas_bookplate_self_api_v2(jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'Bookplate v2 public Auth gateway privilege isolation failed'; END IF;
 IF has_table_privilege('authenticated','atlas.personal_atlas_bookplate_events','UPDATE')
  OR has_table_privilege('authenticated','atlas.personal_atlas_bookplate_events','SELECT')
 THEN RAISE EXCEPTION 'Bookplate event table improperly exposed to Auth caller'; END IF;
 SELECT pg_get_functiondef('atlas.set_personal_atlas_bookplate_self_api_v2(jsonb)'::regprocedure) INTO v_fn;
 IF position('auth.uid()' in v_fn)=0
  OR position('atlas.set_personal_atlas_bookplate_self_api_v1' in v_fn)=0
  OR position('idempotentReplay' in v_fn)=0
  OR position('contactEmails' in v_fn)=0 OR position('dateOfBirth' in v_fn)=0
 THEN RAISE EXCEPTION 'Bookplate v2 source no longer protects person or contact custody'; END IF;
 IF (SELECT count(*) FROM atlas.authenticated_rpc_registry
     WHERE signature in ('atlas.personal_atlas_bookplate_self_api_v2()',
       'atlas.set_personal_atlas_bookplate_self_api_v2(p_input jsonb)')
     AND review_status='active' AND authenticated_execute_expected AND NOT anonymous_execute_expected)<>2
 THEN RAISE EXCEPTION 'Bookplate v2 governed API registry incomplete'; END IF;
END $validation$;
ROLLBACK;
