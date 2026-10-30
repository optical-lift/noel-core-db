-- Read-only structural postconditions on disposable clone only.
DO $check$
DECLARE
  source_text text;
  writer regprocedure;
BEGIN
  writer:=to_regprocedure('atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)');
  IF writer IS NULL THEN RAISE EXCEPTION 'Existing owner planner missing'; END IF;
  source_text:=pg_get_functiondef(writer::oid);
  IF position('ledger_connection_direct_assignment' in source_text)=0
     OR position('person_has_native_ledger_connection_v1' in source_text)=0
     OR position('company_work_native_ledger_owner_self_v1' in source_text)=0
     OR position('company_work_execution_plan_window_check_v1' in source_text)=0
     OR position('establishment_basis->>''nativeLedgerId''=p_ledger_id::text' in source_text)=0
  THEN RAISE EXCEPTION 'Direct native owner planning or its existing source guards missing'; END IF;
  IF to_regprocedure('public.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)') IS NULL THEN
    RAISE EXCEPTION 'Existing public authenticated RPC membrane missing';
  END IF;
  -- These real source uniqueness constraints prevent two active allocations
  -- or competing current plans from making a one-row writer nondeterministic.
  -- A clone missing them must not be approved even if the function compiles.
  IF NOT EXISTS(
    SELECT 1 FROM pg_indexes
    WHERE schemaname='atlas' AND tablename='work_allocations'
      AND indexname='work_allocations_one_active_responsible_idx'
      AND indexdef LIKE 'CREATE UNIQUE INDEX%'
      AND indexdef LIKE '%(work_item_id)%'
      AND indexdef LIKE '%state = ''active''%'
  ) THEN RAISE EXCEPTION 'One active responsible allocation source constraint missing'; END IF;
  IF NOT EXISTS(
    SELECT 1 FROM pg_indexes
    WHERE schemaname='atlas' AND tablename='work_execution_plans'
      AND indexname='work_execution_plans_one_current_idx'
      AND indexdef LIKE 'CREATE UNIQUE INDEX%'
      AND indexdef LIKE '%(work_item_id)%'
      AND indexdef LIKE '%needs_replan%'
  ) THEN RAISE EXCEPTION 'One current plan source constraint missing'; END IF;
  RAISE NOTICE 'PASS source-only function/guard presence; signed behavior NOT TESTED';
END
$check$;
