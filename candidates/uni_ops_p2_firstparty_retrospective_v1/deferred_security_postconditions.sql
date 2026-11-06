-- HELD read-only structural assertions for a future disposable clone;
-- not a substitute for true signed PostgREST/GoTrue or concurrency tests.
DO $post$
DECLARE v_fn text;
BEGIN
 IF pg_catalog.to_regclass('atlas.uni_ops_p2_firstparty_activity_reports_v1') IS NULL
 OR pg_catalog.to_regclass('atlas.uni_ops_p2_governor_activity_review_events_v1') IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_p2_submit_unassigned_activity_self_api_v1(uuid,uuid,text,timestamptz,uuid)'
 ) IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_p2_governor_review_activity_self_api_v1(uuid,uuid,text,text,uuid,uuid,uuid)'
 ) IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_p2_governor_case_history_self_api_v1(uuid,uuid,uuid)'
 ) IS NULL THEN
  RAISE EXCEPTION 'P2 source tables and three private signed-source functions not assembled';
 END IF;

 IF NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='atlas.uni_ops_p2_firstparty_activity_reports_v1'::regclass
    AND t.tgname='uni_ops_p2_reports_append_only_v1' AND t.tgenabled<>'D'
 ) OR NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger t
  WHERE t.tgrelid='atlas.uni_ops_p2_governor_activity_review_events_v1'::regclass
    AND t.tgname='uni_ops_p2_governor_review_append_only_v1'
    AND t.tgenabled<>'D'
 ) THEN
  RAISE EXCEPTION 'P2 append-only first-party/review history guards not attached';
 END IF;

 FOR v_fn IN SELECT unnest(ARRAY[
  'atlas.uni_ops_p2_submit_unassigned_activity_self_api_v1(uuid,uuid,text,timestamptz,uuid)',
  'atlas.uni_ops_p2_governor_review_activity_self_api_v1(uuid,uuid,text,text,uuid,uuid,uuid)',
  'atlas.uni_ops_p2_governor_case_history_self_api_v1(uuid,uuid,uuid)'])
 LOOP
  IF pg_catalog.has_function_privilege('anon',v_fn,'EXECUTE')
    OR pg_catalog.has_function_privilege('authenticated',v_fn,'EXECUTE')
    OR pg_catalog.has_function_privilege('service_role',v_fn,'EXECUTE')
  THEN
   RAISE EXCEPTION 'Private P2 source execution exposed: %',v_fn;
  END IF;
 END LOOP;

 IF NOT EXISTS (
  SELECT 1 FROM pg_catalog.pg_class c
  WHERE c.oid='atlas.uni_ops_p2_firstparty_activity_reports_v1'::regclass
  AND c.relrowsecurity AND c.relforcerowsecurity
 ) OR NOT EXISTS(
  SELECT 1 FROM pg_catalog.pg_class c
  WHERE c.oid='atlas.uni_ops_p2_governor_activity_review_events_v1'::regclass
  AND c.relrowsecurity AND c.relforcerowsecurity
 ) THEN
  RAISE EXCEPTION 'P2 private source table RLS/FORCE RLS required';
 END IF;


 -- Retrospective original-source custody requires actual linked firsthand
 -- source and no direct Work writer in P2.
 IF pg_catalog.to_regprocedure(
  'atlas.uni_ops_p2_governor_original_custody_preflight_held_v1(uuid,uuid,uuid)'
 ) IS NULL OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_p2_current_future_offer_separation_held_v1(uuid,uuid,uuid,uuid)'
 ) IS NULL THEN
   RAISE EXCEPTION 'P2 original-first source and independent U2 later-offer separation are missing';
 END IF;
 IF pg_catalog.has_function_privilege(
  'authenticated',
  'atlas.uni_ops_p2_governor_original_custody_preflight_held_v1(uuid,uuid,uuid)'::regprocedure,
  'EXECUTE')
  OR pg_catalog.has_function_privilege(
  'service_role',
  'atlas.uni_ops_p2_current_future_offer_separation_held_v1(uuid,uuid,uuid,uuid)'::regprocedure,
  'EXECUTE')
 THEN
  RAISE EXCEPTION 'P2 original/future-offer private source was exposed';
 END IF;
 IF position('uni_ops_p2_governor_original_custody_preflight_held_v1' IN
   pg_catalog.pg_get_functiondef(
     'atlas.uni_ops_p2_governor_review_activity_self_api_v1(uuid,uuid,text,text,uuid,uuid,uuid)'::regprocedure)
  )=0 THEN
   RAISE EXCEPTION 'P2 matched-original governor review is not source-qualified';
 END IF;

 RAISE NOTICE 'P2 structural ownership/ACL only; signed source evidence/Work non-creation remains DEFERRED';
END;
$post$;
