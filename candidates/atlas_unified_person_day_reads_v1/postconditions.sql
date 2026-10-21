-- Run on the protected disposable production-schema clone, after applying the candidate.
DO $verify$
BEGIN
  IF to_regprocedure('public.personal_daily_raw_notes_self_api_v1(date)') IS NULL
    OR to_regprocedure('atlas.personal_daily_raw_notes_self_api_v1(date)') IS NULL THEN
    RAISE EXCEPTION 'Personal note read membranes missing';
  END IF;
  IF NOT has_function_privilege('authenticated',
      'public.personal_daily_raw_notes_self_api_v1(date)','EXECUTE')
    OR has_function_privilege('anon',
      'public.personal_daily_raw_notes_self_api_v1(date)','EXECUTE') THEN
    RAISE EXCEPTION 'Personal note reader public grants are wrong';
  END IF;
  IF to_regprocedure('public.connected_person_company_work_day_self_api_v1(date)') IS NULL THEN
    RAISE EXCEPTION 'Original connected-person day public RPC was lost';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas' AND p.proname='connected_person_company_work_day_self_api_v1'
      AND p.prosecdef AND p.provolatile='s'
  ) THEN
    RAISE EXCEPTION 'Protected connected-person read contract missing';
  END IF;
END
$verify$;
