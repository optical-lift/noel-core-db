-- Postconditions after source candidate on disposable full-schema clone.
DO $proof$ BEGIN
 IF NOT EXISTS(select 1 from pg_constraint where conname='work_decomposition_once_per_parent'
   and conrelid='atlas.work_decomposition_groups'::regclass) THEN
   RAISE EXCEPTION 'Original parent idempotence constraint missing'; END IF;
 IF NOT EXISTS(select 1 from pg_constraint where conname='work_decomposition_member_distinct_subject'
   and conrelid='atlas.work_decomposition_members'::regclass) THEN
   RAISE EXCEPTION 'Distinct original subjects not source-enforced'; END IF;
 IF has_function_privilege('anon',
   'public.split_original_canonical_work_owner_self_api_v1(uuid,uuid,uuid,jsonb,uuid,text)',
   'EXECUTE') THEN RAISE EXCEPTION 'Anonymous Work decomposition exposure'; END IF;
 IF has_table_privilege('authenticated','atlas.work_decomposition_members','SELECT')
    OR has_table_privilege('authenticated','atlas.work_decomposition_groups','SELECT') THEN
   RAISE EXCEPTION 'Private provenance table exposed'; END IF;
END $proof$;
-- Signed owner/worker/outsider direct RPC denial, idempotent retry, result
-- acceptance and preserved plan/allocation/history readbacks are outstanding.
