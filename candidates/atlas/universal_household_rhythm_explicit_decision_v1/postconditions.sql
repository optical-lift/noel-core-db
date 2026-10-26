DO $proof$ BEGIN
 IF has_table_privilege('authenticated',
     'atlas.household_rhythm_explicit_decisions_v1','SELECT') THEN
  RAISE EXCEPTION 'Private current Rhythm authority leaked'; END IF;
 IF has_function_privilege('anon',
   'public.household_laundry_explicit_rhythm_decide_self_api_v1(uuid,uuid,text,integer,text)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous Household Rhythm decision writer'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger WHERE
   tgrelid='atlas.household_rhythm_explicit_decisions_v1'::regclass
   AND tgname='household_rhythm_decision_append_only_v1'
 ) THEN RAISE EXCEPTION 'Missing append-only Rhythm decision history'; END IF;
END $proof$;
-- Required real signed acceptance:
-- calibration -> no decision and no capacity block;
-- explicit establish -> existing Household rhythm ID, one append-only decision;
-- retry -> identical ID, no extra event;
-- metadata-only forged source flag -> no satisfaction;
-- Actual wash-started -> precisely one conditional satisfaction;
-- repeated Actual -> no duplicate;
-- explicit withdraw -> later Actual yields zero new satisfactions;
-- unrelated household/Person/anon -> denied;
-- native Farm/Program/Event rhythms unaffected.
