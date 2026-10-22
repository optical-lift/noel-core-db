-- REVIEW-ONLY disposable production-schema clone postconditions.
-- Apply AFTER the corresponding generated migration, NEVER to live Supabase.
do $check$
declare v_source text;
begin
  if to_regprocedure(
    'atlas.connected_person_work_prerequisites_self_api_v1(uuid,uuid,uuid)') is null
    or to_regprocedure(
    'public.connected_person_work_prerequisites_self_api_v1(uuid,uuid,uuid)') is null
  then
    raise exception 'Connected-Person prerequisite reader was not installed.';
  end if;
  if pg_catalog.has_function_privilege('anon',
    'public.connected_person_work_prerequisites_self_api_v1(uuid,uuid,uuid)',
    'EXECUTE')
    or not pg_catalog.has_function_privilege('authenticated',
    'public.connected_person_work_prerequisites_self_api_v1(uuid,uuid,uuid)',
    'EXECUTE')
    or pg_catalog.has_function_privilege('authenticated',
    'atlas.connected_person_work_prerequisites_self_api_v1(uuid,uuid,uuid)',
    'EXECUTE')
  then
    raise exception 'Connected-Person source reader privileges are wrong.';
  end if;

  select pg_catalog.pg_get_functiondef(
    'atlas.connected_person_work_prerequisites_self_api_v1(uuid,uuid,uuid)'
    ::pg_catalog.regprocedure) into v_source;
  if position('reality_access_self_api_v1' in v_source)=0
    or position('current_person_id_v1' in v_source)=0
    or position('person_has_native_ledger_connection_v1' in v_source)=0
    or position('work_prerequisite_ledger_scope_v1' in v_source)=0
    or position('work_allocations' in v_source)=0
    or position('assignee_canonical_person_id' in v_source)=0
    or position('a.assignee_membership_id is null' in v_source)=0
    or position('a.allocation_role=' in v_source)=0
    or position('onlyCurrentLedgerEvidence' in v_source)=0
    or position('doesNotAuthorizeRelationChanges' in v_source)=0
    or position('doesNotInferCompletionOrSatisfaction' in v_source)=0
  then
    raise exception 'Actual signed Person plus exact original Work allocation guard missing.';
  end if;
  if position('insert into atlas.' in lower(v_source))>0
    or position('update atlas.' in lower(v_source))>0
    or position('delete from atlas.' in lower(v_source))>0
  then
    raise exception 'Connected-Person prerequisite read must not mutate Atlas.';
  end if;
  if exists (
    select 1 from atlas.work_item_relations r
    where r.relation_kind='depends_on' and r.organization_id is null
  ) then
    raise exception 'Original institutional relationship domain became inconsistent.';
  end if;
  raise notice 'CLONE structural postconditions PASS: worker read scope is exact and does not mutate Work.';
end
$check$;

-- STILL REQUIRED before deployment:
-- genuine distinct local GoTrue worker/owner/outsider sessions and matching
-- guarded person-native work allocations, preserving their actual establishment
-- provenance; neither an employee seat nor a forged JWT qualifies.
