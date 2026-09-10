begin;

create or replace function atlas.organization_work_accountability_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_organizations jsonb;
  v_pending jsonb;
  v_recent jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok',false,'authenticated',false,'organizations','[]'::jsonb,'pending','[]'::jsonb,'recentCompletions','[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId',o.id,
    'organizationName',o.name
  ) order by o.name,o.id),'[]'::jsonb)
  into v_organizations
  from atlas.organizations o
  where o.status='active'
    and exists (
      select 1
      from atlas.organization_memberships om
      where om.organization_id=o.id
        and om.user_id=v_uid
        and om.active
        and om.role='owner'
    );

  select coalesce(jsonb_agg(item order by reported_at desc,result_id desc),'[]'::jsonb)
  into v_pending
  from (
    select
      r.reported_at,
      r.id as result_id,
      jsonb_strip_nulls(jsonb_build_object(
        'resultId',r.id,
        'workItemId',w.id,
        'organizationId',w.organization_id,
        'organizationName',o.name,
        'title',w.title,
        'resultKind',r.result_kind,
        'reportedAt',r.reported_at,
        'reportedByOrganizationMembershipId',r.reported_by_organization_membership_id,
        'reportedByName',isp.display_name,
        'positionTitle',position_row.display_title,
        'resultContractKey',r.result_contract_key,
        'companyWorkState',w.work_state
      )) as item
    from atlas.work_execution_results r
    join atlas.work_items w on w.id=r.work_item_id and w.organization_id=r.organization_id
    join atlas.organizations o on o.id=w.organization_id and o.status='active'
    join atlas.work_result_contract_policies p on p.contract_key=r.result_contract_key and p.active and p.acceptance_mode='manager_acceptance'
    left join atlas.organization_memberships reported_membership
      on reported_membership.id=r.reported_by_organization_membership_id
      and reported_membership.organization_id=r.organization_id
    left join atlas.identity_subject_projections isp
      on isp.organization_id=r.organization_id
      and isp.subject_id=reported_membership.identity_subject_id
    left join lateral (
      select pos.display_title
      from atlas.organization_position_appointments opa
      join atlas.organization_positions pos
        on pos.id=opa.position_id
        and pos.organization_id=opa.organization_id
        and pos.status='active'
      where opa.organization_id=r.organization_id
        and opa.organization_membership_id=r.reported_by_organization_membership_id
        and opa.status='active'
        and opa.begins_at<=r.reported_at
        and (opa.ends_at is null or opa.ends_at>r.reported_at)
      order by case when opa.appointment_kind='primary' then 0 else 1 end,opa.begins_at desc,opa.id
      limit 1
    ) position_row on true
    where exists (
      select 1
      from atlas.organization_memberships owner_membership
      where owner_membership.organization_id=r.organization_id
        and owner_membership.user_id=v_uid
        and owner_membership.active
        and owner_membership.role='owner'
    )
      and not exists (
        select 1 from atlas.work_result_acceptances a where a.execution_result_id=r.id
      )
    order by r.reported_at desc,r.id desc
    limit 50
  ) pending_rows;

  select coalesce(jsonb_agg(item order by established_at desc,entry_id desc),'[]'::jsonb)
  into v_recent
  from (
    select
      le.established_at,
      le.id as entry_id,
      jsonb_strip_nulls(jsonb_build_object(
        'ledgerEntryId',le.id,
        'organizationId',le.organization_id,
        'organizationName',o.name,
        'workItemId',le.payload->>'workItemId',
        'title',le.title,
        'occurredAt',le.occurred_at,
        'establishedAt',le.established_at,
        'completedAt',le.payload->>'completedAt',
        'resultKind',le.payload->>'resultKind',
        'acceptanceKind',le.payload->>'acceptanceKind',
        'reportedByOrganizationMembershipId',le.payload->>'reportedByOrganizationMembershipId',
        'positionTitle',le.payload->>'positionTitle',
        'truthStatus',le.truth_status
      )) as item
    from atlas.organization_ledger_entries le
    join atlas.organizations o on o.id=le.organization_id and o.status='active'
    where le.semantic_type='company_work_completed'
      and le.truth_status='established'
      and coalesce((le.provenance->>'institutionalOnly')::boolean,false)
      and coalesce((le.provenance->>'personalAtlasCausalityIncluded')::boolean,false)=false
      and exists (
        select 1
        from atlas.organization_memberships owner_membership
        where owner_membership.organization_id=le.organization_id
          and owner_membership.user_id=v_uid
          and owner_membership.active
          and owner_membership.role='owner'
      )
    order by le.established_at desc,le.id desc
    limit 50
  ) recent_rows;

  return jsonb_build_object(
    'ok',true,
    'authenticated',true,
    'organizations',v_organizations,
    'pending',v_pending,
    'recentCompletions',v_recent,
    'privacyBoundary',jsonb_build_object(
      'institutionalOnly',true,
      'personalAtlasCausalityIncluded',false
    )
  );
end;
$function$;

revoke all on function atlas.organization_work_accountability_self_api_v1() from public,anon;
grant execute on function atlas.organization_work_accountability_self_api_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values (
  'atlas.organization_work_accountability_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_organization_work_accountability_self_v1',
    'purpose','Expose owner-only institutional Company Work result review and established completion Ledger evidence.',
    'truthBoundary','Returns only organizations where the signed-in human has an active owner membership. Pending reports are manager-acceptance results without a decision. Recent completions are established institutional Ledger projections and deliberately omit Personal Atlas causality.',
    'classificationRuleVersion',3
  ),
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();

commit;