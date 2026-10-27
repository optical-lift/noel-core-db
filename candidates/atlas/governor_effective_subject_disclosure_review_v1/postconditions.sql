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

-- Current original Subject field-state projection remains bounded and source-derived.
DO $subject_review_fields$
DECLARE v_def text;
BEGIN
 SELECT pg_get_functiondef('atlas.owner_effective_subject_disclosure_review_self_api_v1(uuid,uuid,uuid,integer,uuid)'::regprocedure) INTO v_def;
 IF position('linkedSubjectDisclosure' in v_def)=0
 OR position('subject_disclosure_decision_events_v1' in v_def)=0
 OR position('has_current_subject_disclosure_v1' in v_def)=0
 OR position('LIMIT 21' in v_def)=0
 OR position('independentlySignedTargetProof' in v_def)=0
 THEN RAISE EXCEPTION 'Governor field-review source evidence incomplete'; END IF;
END $subject_review_fields$;
