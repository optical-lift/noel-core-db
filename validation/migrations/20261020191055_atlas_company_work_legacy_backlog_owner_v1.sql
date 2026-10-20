-- Build 5 Venue-first legacy backlog: structural/non-mutating postconditions.
DO $checks$
DECLARE
  v_dupes integer;
BEGIN
  IF to_regclass('atlas.company_work_legacy_task_reviews_v1') IS NULL THEN
    RAISE EXCEPTION 'Legacy review ledger absent';
  END IF;
  IF to_regprocedure('atlas.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)') IS NULL OR
     to_regprocedure('atlas.decide_company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,uuid,boolean)') IS NULL THEN
    RAISE EXCEPTION 'Legacy review RPC contract absent';
  END IF;
  IF has_function_privilege('anon',
      'atlas.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)','EXECUTE') OR
     has_function_privilege('anon',
      'atlas.decide_company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,uuid,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous backlog review/mutation must not be executable';
  END IF;
  IF NOT has_function_privilege('authenticated',
      'atlas.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)','EXECUTE') OR
     NOT has_function_privilege('authenticated',
      'atlas.decide_company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,uuid,text,text,text,text,text,uuid,boolean)','EXECUTE') THEN
    RAISE EXCEPTION 'Owner gated RPC must be executable from authenticated Atlas';
  END IF;
  IF has_table_privilege('authenticated',
      'atlas.company_work_legacy_task_reviews_v1','SELECT') OR
     has_table_privilege('authenticated',
      'atlas.company_work_legacy_task_reviews_v1','INSERT') THEN
    RAISE EXCEPTION 'Recovery review evidence must not have browser table access';
  END IF;
  SELECT count(*) INTO v_dupes FROM (
    SELECT organization_id,source_object_id
      FROM atlas.work_items
      WHERE source_object_type='legacy_task' AND source_object_id IS NOT NULL
      GROUP BY organization_id,source_object_id HAVING count(*)>1
  ) x;
  IF v_dupes>0 THEN RAISE EXCEPTION 'Duplicate canonical legacy source Work identities'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes
    WHERE schemaname='atlas' AND tablename='work_items'
      AND indexname='work_items_one_legacy_source_per_org_v1') THEN
    RAISE EXCEPTION 'Canonical legacy source unique index absent';
  END IF;
END
$checks$;
