-- Structural protected-clone-only guard for existing completed/active dated Work.
-- No signed user behavior is established by passing this SQL.
BEGIN;
DO $check$
DECLARE
 v_i oid:=to_regprocedure('atlas.connected_person_company_work_day_self_api_v1(date)');
 v_p oid:=to_regprocedure('public.connected_person_company_work_day_self_api_v1(date)');
 v_def text;
BEGIN
 IF v_i IS NULL OR v_p IS NULL THEN
  RAISE EXCEPTION 'Original signed dated Work reader and public bridge missing';
 END IF;
 IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_i)
 OR has_function_privilege('anon',v_i,'EXECUTE')
 OR has_function_privilege('anon',v_p,'EXECUTE')
 OR NOT has_function_privilege('authenticated',v_p,'EXECUTE') THEN
   RAISE EXCEPTION 'Dated Work existing public ACL envelope invalid';
 END IF;
 v_def:=pg_get_functiondef(v_i);
 IF v_def NOT LIKE '%reality_access_self_api_v1%'
  OR v_def NOT LIKE '%person_has_native_ledger_connection_v1%'
  OR v_def NOT LIKE '%company_work_native_ledger_relevance%'
  OR v_def NOT LIKE '%company_work_native_ledger_exact_source_v1%'
  OR v_def NOT LIKE '%rel.attribution_state=%'
  OR v_def NOT LIKE '%a.assignee_membership_id IS NULL%'
  OR v_def NOT LIKE '%p.plan_state=%'
  OR v_def NOT LIKE '%w.work_state=%'
  OR v_def NOT LIKE '%res.acceptance_decision%'
  OR v_def NOT LIKE '%connected_person_work_field_currently_approved_v1%'
  OR v_def NOT LIKE '%connected_person_company_work_day_v1%' THEN
  RAISE EXCEPTION 'Dated Work lost completed/active original identity or source deny';
 END IF;
 IF v_def LIKE '%''instructions'',w.instructions%'
  OR v_def LIKE '%w.metadata->>''taskClassification''%' THEN
  RAISE EXCEPTION 'Dated Work still returns unapproved instruction or task classification';
 END IF;
END;
$check$;
ROLLBACK;
