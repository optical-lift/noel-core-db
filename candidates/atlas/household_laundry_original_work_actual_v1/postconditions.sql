DO $proof$
DECLARE n text;
 v_sql text;
 v_actor_pos integer;
 v_carrier_pos integer;
 v_result_pos integer;
 v_replay_pos integer;
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
 SELECT pg_get_functiondef(p.oid) INTO v_sql FROM pg_proc p
 JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='atlas'
   AND p.proname='record_household_laundry_wash_started_self_api_v1'
 LIMIT 1;
 v_actor_pos:=position('v_person:=atlas.household_work_actor_v1' IN v_sql);
 v_carrier_pos:=position('Physical Work Actual requires authorized original carrier' IN v_sql);
 v_result_pos:=position('SELECT id INTO v_result FROM atlas.care_result_events' IN v_sql);
 v_replay_pos:=position('IF v_result IS NOT NULL THEN' IN v_sql);
 IF v_sql IS NULL OR v_actor_pos=0 OR v_carrier_pos=0 OR
    v_result_pos=0 OR v_replay_pos=0 OR
    NOT (v_actor_pos<v_carrier_pos AND v_carrier_pos<v_result_pos
      AND v_result_pos<v_replay_pos)
 THEN
   RAISE EXCEPTION 'Physical-Actual replay must authorize the real owner/carrier before receipt lookup.';
 END IF;
 IF NOT (v_sql LIKE '%household_rhythm_explicit_decisions_v1%' AND
         v_sql LIKE '%explicitDecisionId%') THEN
   RAISE EXCEPTION 'Physical-Actual Rhythm satisfaction has no immutable signed decision.';
 END IF;
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
