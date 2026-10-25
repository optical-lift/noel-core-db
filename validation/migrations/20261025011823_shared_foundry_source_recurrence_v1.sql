-- Disposable full-schema clone only, no direct production application.
DO $proof$
DECLARE v_fn text;
BEGIN
  IF to_regprocedure('atlas.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)') IS NULL
    OR to_regprocedure('public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)') IS NULL
  THEN RAISE EXCEPTION 'Foundry weekly source bridge is missing'; END IF;
  IF has_function_privilege('anon','public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)','EXECUTE')
    OR has_function_privilege('service_role','public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)','EXECUTE')
  THEN RAISE EXCEPTION 'Foundry schedule self API grants broken'; END IF;
  SELECT pg_get_functiondef(
    'atlas.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)'::regprocedure
  ) INTO v_fn;
  IF v_fn NOT ILIKE '%foundry_current_signed_principal_v1%'
    OR v_fn NOT ILIKE '%owner_principal_id=v_actor%'
    OR v_fn NOT ILIKE '%require_ledger_schedule_responsibility_v1%'
    OR v_fn NOT ILIKE '%upsert_ledger_recurrence_series_self_api_v1%'
    OR v_fn NOT ILIKE '%foundry_reality_input_v1%'
    OR v_fn NOT ILIKE '%Outside-source authority%'
    OR v_fn NOT ILIKE '%Already established; changes require a governed revision%'
  THEN RAISE EXCEPTION 'Foundry source, domain permission or anti-overwrite guard lost'; END IF;

  BEGIN
    PERFORM atlas.establish_foundry_weekly_recurrence_self_api_v1(
      'no-owned-workspace','foundry-reality-intake-nonexistent',0,
      '00000000-0000-0000-0000-000000000000'::uuid,
      'Thursday',4::smallint,'America/Chicago',
      '2026-10-29'::date,true,NULL::time,NULL::time);
    RAISE EXCEPTION 'Unsigned call unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END
$proof$;
