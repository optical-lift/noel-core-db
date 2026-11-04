-- Only run AFTER U1B + U2A + R01/R02 source candidates + U2B within
-- a job-owned disposable BEGIN..ROLLBACK. NOT a production release test.
DO $checks$
BEGIN
 IF pg_catalog.to_regprocedure(
   'atlas.governor_approve_rhythm_opportunity_self_api_v1(uuid,uuid,uuid,text,uuid,text,date,date,smallint[],uuid)') IS NULL
   OR pg_catalog.to_regprocedure(
   'atlas.finalize_accepted_governed_prework_self_api_v1(uuid)') IS NULL
   OR pg_catalog.to_regprocedure(
   'public.finalize_accepted_governed_prework_self_api_v1(uuid)') IS NULL THEN
  RAISE EXCEPTION 'Exact R02 original writer or U2B accept-first transport missing';
 END IF;
 IF pg_catalog.has_function_privilege('anon',
    'public.finalize_accepted_governed_prework_self_api_v1(uuid)','EXECUTE')
   OR pg_catalog.has_function_privilege('authenticated',
    'atlas.finalize_accepted_governed_prework_self_api_v1(uuid)','EXECUTE')
   OR NOT pg_catalog.has_function_privilege('authenticated',
    'public.finalize_accepted_governed_prework_self_api_v1(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'U2B direct client execution boundary not closed'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.governed_prework_candidate_offers_v1
    WHERE offer_state IN ('accepted','fulfilled')) THEN
  RAISE EXCEPTION 'No synthetic worker acceptance or Work is authorized by structural test';
 END IF;
END;
$checks$;
