-- Public-safe structural postconditions for the private Noel Mark photo-review candidate.
-- Run ONLY on the disposable full-schema validation clone after candidate.sql.
-- Never use these checks as a substitute for genuine owner/outsider/anon signed tests.
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  WHERE s.nspname='mark' AND c.relkind='r' AND c.relname IN
   ('photo_component_catalogues','photo_component_proposals',
    'photo_catalogue_admissions','photo_owner_review_events','photo_owner_review_decisions')
    AND c.relrowsecurity AND c.relforcerowsecurity;
  IF n<>5 THEN RAISE EXCEPTION 'The five private photo evidence tables must have enforced RLS'; END IF;

  SELECT count(*) INTO n
  FROM information_schema.triggers
  WHERE trigger_schema='mark' AND event_object_table IN
   ('photo_component_catalogues','photo_component_proposals',
    'photo_catalogue_admissions','photo_owner_review_events','photo_owner_review_decisions')
  AND trigger_name LIKE 'photo_%';
  IF n<15 THEN RAISE EXCEPTION 'Missing append-only or source-geometry triggers'; END IF;

  SELECT count(*) INTO n
  FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
  WHERE s.nspname='mark' AND p.proname IN
   ('photo_verify_catalogue_source','photo_verify_component_source',
    'photo_verify_catalogue_admission','photo_verify_owner_event',
    'photo_verify_review_rectangle','photo_deny_evidence_mutation') AND NOT p.prosecdef;
  IF n<>6 THEN RAISE EXCEPTION 'Photo guard functions must not run with definer rights'; END IF;

  IF has_schema_privilege('anon','mark','USAGE') OR
     has_schema_privilege('authenticated','mark','USAGE') OR
     has_schema_privilege('service_role','mark','USAGE') THEN
     RAISE EXCEPTION 'Private mark schema access was broadened';
  END IF;
  IF has_table_privilege('anon','mark.photo_owner_review_decisions','SELECT') OR
     has_table_privilege('authenticated','mark.photo_owner_review_decisions','SELECT') OR
     has_table_privilege('service_role','mark.photo_owner_review_decisions','SELECT') OR
     has_table_privilege('anon','mark.photo_component_proposals','INSERT') OR
     has_table_privilege('authenticated','mark.photo_owner_review_events','INSERT') THEN
     RAISE EXCEPTION 'Unauthenticated or broad application direct table rights detected';
  END IF;
  IF has_table_privilege('anon','mark.photo_owner_current_reviews','SELECT') OR
     has_table_privilege('authenticated','mark.photo_owner_current_reviews','SELECT') THEN
     RAISE EXCEPTION 'Owner review current view must not be publicly readable';
  END IF;

  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
  WHERE s.nspname='mark' AND c.relname='photo_owner_current_reviews'
    AND c.relkind='v' AND 'security_invoker=true'=ANY(c.reloptions);
  IF n<>1 THEN RAISE EXCEPTION 'Private current owner review view must be invoker-mode'; END IF;

  -- SQL structural postconditions do NOT verify user-session identity, row
  -- authorization, source rights, actual ink masks or learning quality.
END $$;
