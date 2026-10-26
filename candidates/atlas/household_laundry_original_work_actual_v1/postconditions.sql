DO $proof$
DECLARE n text;
BEGIN
 FOR n IN SELECT unnest(ARRAY[
  'record_household_laundry_observation_self_api_v1',
  'establish_household_laundry_original_work_self_api_v1',
  'record_household_laundry_wash_started_self_api_v1'
 ]) LOOP
  IF NOT EXISTS(
   SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='atlas' AND p.proname=n AND p.prosecdef
  ) THEN RAISE EXCEPTION 'Original Laundry source writer absent: %',n;END IF;
 END LOOP;
 IF has_function_privilege('anon',
  'public.record_household_laundry_wash_started_self_api_v1(uuid,uuid,text)',
  'EXECUTE') THEN RAISE EXCEPTION 'Anonymous physical-Actual writer exposed'; END IF;
END $proof$;
-- Disposable clone signed cases:
-- calibration alone creates 0 Need/Work/Rhythm; actual observation -> 0 Work;
-- explicit establish -> one household-origin work_items UUID + context link;
-- optional self/member without account; unassigned stays unassigned;
-- repeated establish -> same original UUID, no duplicate;
-- wash_started -> one care_result, one accepted work_result, one completed
-- original Work, only begin_cycle Need satisfied, Laundry state washing;
-- no explicit Rhythm -> zero satisfactions/windows changed;
-- explicit qualifying Rhythm -> one conditional satisfaction, next window;
-- cross-Household, anonymous, unrelated Person and forged result denied;
-- source action replays never duplicate or complete unrelated Work.
