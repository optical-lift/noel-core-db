-- Disposable-clone postconditions; never run this as a production write.
DO $test$
DECLARE t text;
BEGIN
 FOR t IN SELECT unnest(ARRAY['work_items','work_allocations','work_execution_plans',
 'work_execution_plan_events','work_execution_results','work_result_acceptances',
 'work_item_context_links','work_time_contracts']) LOOP
  IF NOT EXISTS(
   SELECT 1 FROM information_schema.columns
   WHERE table_schema='atlas' AND table_name=t AND column_name='household_id'
    AND is_nullable='YES'
  ) THEN RAISE EXCEPTION 'Missing nullable household custody: %',t; END IF;
  IF NOT EXISTS(
   SELECT 1 FROM pg_constraint
   WHERE conrelid=('atlas.'||t)::regclass AND conname=t||'_one_native_custody_v1'
  ) THEN RAISE EXCEPTION 'Missing exclusive custodian check: %',t; END IF;
 END LOOP;
 IF has_table_privilege('authenticated','atlas.work_items','INSERT') OR
    has_table_privilege('authenticated','atlas.work_execution_results','INSERT')
 THEN RAISE EXCEPTION 'Direct authenticated canonical Work mutation exposure'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.rhythm_satisfactions'::regclass
   AND conname='rhythm_satisfactions_one_native_custody_v1'
 ) THEN RAISE EXCEPTION 'Single satisfaction registry custody not enforced'; END IF;
END $test$;
-- Required clone: existing Org/Event inserts, old allocation provenance,
-- Household Work source-only inserts, cross-Household FKs, and absence of
-- worker-credential inference all tested with BEGIN ... ROLLBACK fixtures.
