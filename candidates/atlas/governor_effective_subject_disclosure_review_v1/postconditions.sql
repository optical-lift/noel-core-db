-- Run in disposable schema clone against the exact source candidate.
DO $proof$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
  WHERE n.nspname='atlas' AND p.proname='owner_effective_subject_disclosure_review_self_api_v1'
    AND p.prosecdef) THEN
  RAISE EXCEPTION 'Governor-only disclosure source missing';
 END IF;
 IF has_function_privilege('anon',
   'public.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous disclosure review exposure'; END IF;
 IF has_function_privilege('authenticated',
   'atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)',
   'EXECUTE') THEN RAISE EXCEPTION 'Internal disclosure review not private'; END IF;
END $proof$;
-- Real independently signed owner/worker/outsider and revocation still needed.
