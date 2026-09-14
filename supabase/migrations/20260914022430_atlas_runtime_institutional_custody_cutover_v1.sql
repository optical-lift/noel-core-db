-- Atlas Runtime Institutional Custody Cutover v1, recovery candidate.
-- Targeted canonical presentation/authority over preserved physical compatibility storage.
-- Existing global physical membership/owner helpers remain unchanged.
-- No historical row rehome, trigger bypass, FK rewrite, mail activation, polling, or send.

begin;

create or replace function atlas.effective_work_item_organization_v1(p_work_item_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_work atlas.work_items%rowtype;
  v_direct record;
  v_unit record;
  v_is_carrier boolean := false;
begin
  if p_work_item_id is null then return null; end if;

  select * into v_work from atlas.work_items where id=p_work_item_id;
  if v_work.id is null then return null; end if;

  select * into v_direct
  from atlas.effective_institutional_custody_v1(
    'atlas','work_items',v_work.id::text,v_work.organization_id,null
  );

  if v_direct.from_adjudication then
    if v_direct.disposition in ('physical','reassigned') then
      return v_direct.effective_organization_id;
    end if;
    return null;
  end if;

  if v_work.organization_unit_id is not null then
    select * into v_unit
    from atlas.effective_institutional_custody_v1(
      'atlas','organization_units',v_work.organization_unit_id::text,v_work.organization_id,null
    );
    if v_unit.from_adjudication
       and v_unit.disposition='reassigned'
       and v_unit.effective_organization_id is not null then
      return v_unit.effective_organization_id;
    end if;
  end if;

  select exists(
    select 1 from atlas.institutional_custody_carriers c
    where c.carrier_organization_id=v_work.organization_id and c.status='active'
  ) into v_is_carrier;

  if v_is_carrier then return null; end if;
  return v_work.organization_id;
end;
$function$;

create or replace function atlas.effective_communication_endpoint_organization_v1(p_endpoint_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_direct record;
  v_unit record;
  v_is_carrier boolean := false;
begin
  if p_endpoint_id is null then return null; end if;

  select * into v_endpoint from atlas.communication_endpoints where id=p_endpoint_id;
  if v_endpoint.id is null then return null; end if;

  select * into v_direct
  from atlas.effective_institutional_custody_v1(
    'atlas','communication_endpoints',v_endpoint.id::text,v_endpoint.organization_id,null
  );

  if v_direct.from_adjudication then
    if v_direct.disposition in ('physical','reassigned') then
      return v_direct.effective_organization_id;
    end if;
    return null;
  end if;

  if v_endpoint.organization_unit_id is not null then
    select * into v_unit
    from atlas.effective_institutional_custody_v1(
      'atlas','organization_units',v_endpoint.organization_unit_id::text,v_endpoint.organization_id,null
    );
    if v_unit.from_adjudication
       and v_unit.disposition='reassigned'
       and v_unit.effective_organization_id is not null then
      return v_unit.effective_organization_id;
    end if;
  end if;

  select exists(
    select 1 from atlas.institutional_custody_carriers c
    where c.carrier_organization_id=v_endpoint.organization_id and c.status='active'
  ) into v_is_carrier;

  if v_is_carrier then return null; end if;
  return v_endpoint.organization_id;
end;
$function$;

create or replace function atlas.current_effective_organization_membership_v1(p_organization_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select om.id
  from atlas.organization_memberships om
  left join atlas.institutional_custody_adjudications a
    on a.subject_schema='atlas'
   and a.subject_table='organization_memberships'
   and a.subject_key=om.id::text
  where om.person_id=atlas.current_person_id_v1()
    and om.active
    and (
      case
        when a.id is null then om.organization_id
        when a.disposition='reassigned' then a.canonical_organization_id
        else null
      end
    )=p_organization_id
  order by
    case when a.id is null and om.organization_id=p_organization_id then 0 else 1 end,
    case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end,
    om.created_at,
    om.id
  limit 1;
$function$;

create or replace function atlas.is_effective_organization_member_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select p_organization_id is not null
     and atlas.current_effective_organization_membership_v1(p_organization_id) is not null;
$function$;

create or replace function atlas.is_effective_organization_owner_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select p_organization_id is not null and (
    exists (
      select 1
      from atlas.organization_memberships om
      left join atlas.institutional_custody_adjudications a
        on a.subject_schema='atlas'
       and a.subject_table='organization_memberships'
       and a.subject_key=om.id::text
      where om.person_id=atlas.current_person_id_v1()
        and om.active
        and om.role='owner'
        and (
          case
            when a.id is null then om.organization_id
            when a.disposition='reassigned' then a.canonical_organization_id
            else null
          end
        )=p_organization_id
    )
    or exists (
      select 1
      from atlas.principal_ledger_authorities pla
      join atlas.ledger_organization_participations lop
        on lop.ledger_id=pla.ledger_id
       and lop.organization_id=p_organization_id
       and lop.status='active'
       and lop.participation_kind='governing'
       and lop.is_compatibility_primary
      join atlas.ledgers l on l.id=pla.ledger_id and l.status='active'
      where pla.principal_id=atlas.current_principal_id_v1()
        and pla.status='active'
        and pla.authority_kind='root_governing'
        and not exists (
          select 1 from atlas.institutional_custody_carriers c
          where c.carrier_ledger_id=pla.ledger_id
            and c.carrier_organization_id=p_organization_id
            and c.status='active'
        )
    )
  );
$function$;

revoke all on function atlas.effective_work_item_organization_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.effective_communication_endpoint_organization_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.current_effective_organization_membership_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.is_effective_organization_member_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.is_effective_organization_owner_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.effective_work_item_organization_v1(uuid) to service_role;
grant execute on function atlas.effective_communication_endpoint_organization_v1(uuid) to service_role;
grant execute on function atlas.current_effective_organization_membership_v1(uuid) to service_role;
grant execute on function atlas.is_effective_organization_member_v1(uuid) to service_role;
grant execute on function atlas.is_effective_organization_owner_v1(uuid) to service_role;

-- Selected Principal presentation: hide active compatibility-carrier Ledgers without changing legacy authority rows.
create or replace function atlas.principal_ledgers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v2',
      'state','principal_required','items','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(x.item order by x.sort_name,x.ledger_id),'[]'::jsonb)
  into v_items
  from (
    select
      l.id as ledger_id,
      coalesce(po.organization_name,l.name) as sort_name,
      jsonb_build_object(
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerName',l.name,
        'ledgerKind',l.ledger_kind,
        'ledgerStatus',l.status,
        'organizationId',po.organization_id,
        'organizationStableKey',po.organization_stable_key,
        'organizationName',po.organization_name,
        'organizations',coalesce(orgs.items,'[]'::jsonb),
        'authorityKind',a.authority_kind,
        'scopeState',coalesce(l.metadata->>'scope_state','canonical')
      ) as item
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    left join lateral (
      select o.id as organization_id,o.stable_key as organization_stable_key,o.name as organization_name
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id and o.status='active'
      where p.ledger_id=l.id and p.status='active' and p.is_compatibility_primary
      limit 1
    ) po on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'participationKind',p.participation_kind,
        'isCompatibilityPrimary',p.is_compatibility_primary
      ) order by o.name,p.participation_kind) as items
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id
      where p.ledger_id=l.id and p.status='active'
    ) orgs on true
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
      and not exists (
        select 1 from atlas.institutional_custody_carriers c
        where c.carrier_ledger_id=l.id and c.status='active'
      )
  ) x;

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v2',
    'state','ready','principalId',v_principal_id,'items',v_items,
    'compatibilityCarriersExcluded',true
  );
end;
$function$;

-- Preserve mature physical self-API bodies behind private compatibility functions.
do $function$
begin
  if to_regprocedure('atlas.organization_access_physical_compatibility_internal_v1()') is null then
    execute 'alter function atlas.organization_access_self_api_v1() rename to organization_access_physical_compatibility_internal_v1';
  end if;
  if to_regprocedure('atlas.current_session_context_physical_compatibility_internal_v1()') is null then
    execute 'alter function atlas.current_session_context_api_v1() rename to current_session_context_physical_compatibility_internal_v1';
  end if;
  if to_regprocedure('atlas.principal_self_context_physical_compatibility_internal_v1()') is null then
    execute 'alter function atlas.principal_self_context_api_v1() rename to principal_self_context_physical_compatibility_internal_v1';
  end if;
  if to_regprocedure('atlas.institutional_communications_home_physical_compatibility_internal_v1()') is null then
    execute 'alter function atlas.institutional_communications_home_self_api_v1() rename to institutional_communications_home_physical_compatibility_internal_v1';
  end if;
end;
$function$;

revoke all on function atlas.organization_access_physical_compatibility_internal_v1() from public, anon, authenticated, service_role;
revoke all on function atlas.current_session_context_physical_compatibility_internal_v1() from public, anon, authenticated, service_role;
revoke all on function atlas.principal_self_context_physical_compatibility_internal_v1() from public, anon, authenticated, service_role;
revoke all on function atlas.institutional_communications_home_physical_compatibility_internal_v1() from public, anon, authenticated, service_role;

create or replace function atlas.organization_access_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  v_base:=atlas.organization_access_physical_compatibility_internal_v1();
  if coalesce((v_base->>'authenticated')::boolean,false)=false then return v_base; end if;

  select coalesce(jsonb_agg(
    (((item)::jsonb - 'organizationId'::text) - 'organizationName'::text) || jsonb_build_object(
      'organizationId',o.id,
      'organizationName',o.name,
      'physicalOrganizationId',(item->>'organizationId')::uuid,
      'custodyDisposition',ec.disposition
    ) order by o.name,o.id,item->>'employeeSeatId'
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item
  cross join lateral atlas.effective_institutional_custody_v1(
    'atlas','organization_memberships',item->>'organizationMembershipId',
    (item->>'organizationId')::uuid,null
  ) ec
  join atlas.organizations o on o.id=ec.effective_organization_id and o.status='active'
  where ec.disposition in ('physical','reassigned')
    and ec.effective_organization_id is not null;

  return v_base || jsonb_build_object(
    'contractVersion','organization_access_self_v2',
    'items',v_items,
    'institutionalCustodyMode','effective'
  );
end;
$function$;

create or replace function atlas.current_session_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_base jsonb;
  v_profile jsonb;
  v_memberships jsonb;
  v_profile_custody record;
begin
  v_base:=atlas.current_session_context_physical_compatibility_internal_v1();
  if v_base is null then return null; end if;

  v_profile:=v_base->'profile';
  if jsonb_typeof(v_profile)='object' and nullif(v_profile->>'default_organization_id','') is not null then
    select * into v_profile_custody
    from atlas.effective_institutional_custody_v1(
      'atlas','user_profiles',v_base->'user'->>'id',
      (v_profile->>'default_organization_id')::uuid,null
    );
    if v_profile_custody.disposition in ('physical','reassigned')
       and v_profile_custody.effective_organization_id is not null then
      v_profile:=v_profile || jsonb_build_object(
        'physical_default_organization_id',(v_profile->>'default_organization_id')::uuid,
        'default_organization_id',v_profile_custody.effective_organization_id,
        'organization_custody_disposition',v_profile_custody.disposition
      );
    else
      v_profile:=v_profile || jsonb_build_object(
        'physical_default_organization_id',(v_profile->>'default_organization_id')::uuid,
        'default_organization_id',null,
        'organization_custody_disposition',v_profile_custody.disposition
      );
    end if;
  end if;

  select coalesce(jsonb_agg(
    (((item)::jsonb - 'organization_id'::text) - 'organization'::text) || jsonb_build_object(
      'organization_id',o.id,
      'physical_organization_id',(item->>'organization_id')::uuid,
      'custody_disposition',ec.disposition,
      'organization',jsonb_build_object(
        'id',o.id,'stable_key',o.stable_key,'name',o.name,'status',o.status
      )
    ) order by o.name,item->>'id'
  ),'[]'::jsonb)
  into v_memberships
  from jsonb_array_elements(coalesce(v_base->'organizationMemberships','[]'::jsonb)) item
  cross join lateral atlas.effective_institutional_custody_v1(
    'atlas','organization_memberships',item->>'id',(item->>'organization_id')::uuid,null
  ) ec
  join atlas.organizations o on o.id=ec.effective_organization_id and o.status='active'
  where ec.disposition in ('physical','reassigned')
    and ec.effective_organization_id is not null;

  return v_base || jsonb_build_object(
    'profile',v_profile,
    'organizationMemberships',v_memberships,
    'institutionalCustodyMode','effective'
  );
end;
$function$;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_base jsonb;
  v_ledgers jsonb;
  v_orgs jsonb;
  v_principal jsonb;
  v_principal_id uuid;
  v_legacy_org jsonb;
begin
  v_base:=atlas.principal_self_context_physical_compatibility_internal_v1();
  if coalesce(v_base->>'state','')<>'ready' then return v_base; end if;

  v_principal_id:=atlas.current_principal_id_v1();
  v_ledgers:=atlas.principal_ledgers_self_api_v1();
  v_legacy_org:=v_base->'principal'->'organizationId';

  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId',q.id,
    'organizationStableKey',q.stable_key,
    'organizationName',q.name
  ) order by q.name,q.id),'[]'::jsonb)
  into v_orgs
  from (
    select distinct o.id,o.stable_key,o.name
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    join atlas.ledger_organization_participations p on p.ledger_id=l.id and p.status='active'
    join atlas.organizations o on o.id=p.organization_id and o.status='active'
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
      and not exists (
        select 1 from atlas.institutional_custody_carriers c
        where c.carrier_ledger_id=l.id and c.status='active'
      )
  ) q;

  v_principal:=(((v_base->'principal')::jsonb - 'organizationId'::text) || jsonb_build_object(
    'organizationId',null,
    'organizationIdSemantics','legacy_compatibility_only',
    'legacyCompatibilityOrganizationId',v_legacy_org
  ));

  return v_base || jsonb_build_object(
    'contractVersion','principal_self_context_v3',
    'principal',v_principal,
    'governedLedgers',coalesce(v_ledgers->'items','[]'::jsonb),
    'governedOrganizations',v_orgs,
    'institutionalRoot','principal_ledger_graph'
  );
end;
$function$;

create or replace function atlas.institutional_communications_home_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_base jsonb;
  v_items jsonb;
begin
  v_base:=atlas.institutional_communications_home_physical_compatibility_internal_v1();

  select coalesce(jsonb_agg(
    (((item)::jsonb - 'organizationId'::text) - 'organizationName'::text) || jsonb_build_object(
      'organizationId',o.id,
      'organizationName',o.name,
      'physicalOrganizationId',(item->>'organizationId')::uuid,
      'effectiveOrganizationMembershipId',atlas.current_effective_organization_membership_v1(o.id),
      'institutionalCustodyMode','effective'
    ) order by o.name,item->>'address'
  ),'[]'::jsonb)
  into v_items
  from jsonb_array_elements(coalesce(v_base->'items','[]'::jsonb)) item
  join atlas.organizations o
    on o.id=atlas.effective_communication_endpoint_organization_v1((item->>'communicationEndpointId')::uuid)
   and o.status='active';

  return v_base || jsonb_build_object(
    'contractVersion','institutional_communications_home_v2',
    'items',v_items,
    'institutionalCustodyMode','effective'
  );
end;
$function$;

create or replace function atlas.organization_work_accountability_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
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
    'organizationId',o.id,'organizationName',o.name
  ) order by o.name,o.id),'[]'::jsonb)
  into v_organizations
  from atlas.organizations o
  where o.status='active' and atlas.is_effective_organization_owner_v1(o.id);

  select coalesce(jsonb_agg(item order by reported_at desc,result_id desc),'[]'::jsonb)
  into v_pending
  from (
    select r.reported_at,r.id as result_id,
      jsonb_strip_nulls(jsonb_build_object(
        'resultId',r.id,
        'workItemId',w.id,
        'organizationId',effective_org.id,
        'organizationName',effective_org.name,
        'physicalOrganizationId',w.organization_id,
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
    join atlas.organizations effective_org
      on effective_org.id=atlas.effective_work_item_organization_v1(w.id)
     and effective_org.status='active'
    join atlas.work_result_contract_policies p
      on p.contract_key=r.result_contract_key and p.active and p.acceptance_mode='manager_acceptance'
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
        on pos.id=opa.position_id and pos.organization_id=opa.organization_id and pos.status='active'
      where opa.organization_id=r.organization_id
        and opa.organization_membership_id=r.reported_by_organization_membership_id
        and opa.status='active'
        and opa.begins_at<=r.reported_at
        and (opa.ends_at is null or opa.ends_at>r.reported_at)
      order by case when opa.appointment_kind='primary' then 0 else 1 end,opa.begins_at desc,opa.id
      limit 1
    ) position_row on true
    where atlas.is_effective_organization_owner_v1(effective_org.id)
      and not exists (select 1 from atlas.work_result_acceptances a where a.execution_result_id=r.id)
    order by r.reported_at desc,r.id desc
    limit 50
  ) pending_rows;

  select coalesce(jsonb_agg(item order by established_at desc,entry_id desc),'[]'::jsonb)
  into v_recent
  from (
    select le.established_at,le.id as entry_id,
      jsonb_strip_nulls(jsonb_build_object(
        'ledgerEntryId',le.id,
        'organizationId',effective_org.id,
        'organizationName',effective_org.name,
        'physicalOrganizationId',le.organization_id,
        'physicalLedgerId',le.ledger_id,
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
    left join atlas.work_items work_source on work_source.id::text=le.payload->>'workItemId'
    join atlas.organizations effective_org on effective_org.id=coalesce(
      atlas.effective_work_item_organization_v1(work_source.id),
      (select ec.effective_organization_id
       from atlas.effective_institutional_custody_v1('atlas','organization_ledger_entries',le.id::text,le.organization_id,le.ledger_id) ec
       where ec.disposition in ('physical','reassigned'))
    ) and effective_org.status='active'
    where le.semantic_type='company_work_completed'
      and le.truth_status='established'
      and coalesce((le.provenance->>'institutionalOnly')::boolean,false)
      and coalesce((le.provenance->>'personalAtlasCausalityIncluded')::boolean,false)=false
      and atlas.is_effective_organization_owner_v1(effective_org.id)
    order by le.established_at desc,le.id desc
    limit 50
  ) recent_rows;

  return jsonb_build_object(
    'ok',true,'authenticated',true,
    'contractVersion','organization_work_accountability_v2',
    'organizations',v_organizations,
    'pending',v_pending,
    'recentCompletions',v_recent,
    'institutionalCustodyMode','effective',
    'privacyBoundary',jsonb_build_object('institutionalOnly',true,'personalAtlasCausalityIncluded',false)
  );
end;
$function$;

create or replace function atlas.organization_owner_decide_company_work_result_api_v1(
  p_execution_result_id uuid,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_result atlas.work_execution_results%rowtype;
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_existing atlas.work_result_acceptances%rowtype;
  v_acceptance atlas.work_result_acceptances%rowtype;
  v_authority_membership_id uuid;
  v_authority_principal_id uuid;
  v_effective_organization_id uuid;
  v_projection_id uuid;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_execution_result_id is null then raise exception 'Company Work result required.' using errcode='22023'; end if;
  if v_decision not in ('accepted','rejected') then raise exception 'Decision must be accepted or rejected.' using errcode='22023'; end if;

  select * into v_result from atlas.work_execution_results r where r.id=p_execution_result_id;
  if v_result.id is null then raise exception 'Company Work result was not found.' using errcode='P0002'; end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id and w.organization_id=v_result.organization_id
  for update;
  if v_work.id is null then raise exception 'Company Work item was not found.' using errcode='P0002'; end if;

  v_effective_organization_id:=atlas.effective_work_item_organization_v1(v_work.id);
  if v_effective_organization_id is null
     or not atlas.is_effective_organization_owner_v1(v_effective_organization_id) then
    raise exception 'Organization owner authority required.' using errcode='42501';
  end if;

  v_authority_membership_id:=atlas.current_effective_organization_membership_v1(v_effective_organization_id);
  v_authority_principal_id:=atlas.current_principal_id_v1();

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_result.result_contract_key and p.active;
  if v_policy.contract_key is null or v_policy.acceptance_mode<>'manager_acceptance' then
    raise exception 'This Company Work result is not governed by manager acceptance.' using errcode='23514';
  end if;

  select * into v_existing from atlas.work_result_acceptances a where a.execution_result_id=v_result.id;
  if v_existing.id is not null then
    if v_existing.decision<>v_decision then
      raise exception 'This Company Work result already has a different institutional decision.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'state','deduplicated','executionResultId',v_result.id,'workItemId',v_work.id,
      'organizationId',v_effective_organization_id,'physicalOrganizationId',v_work.organization_id,
      'decision',v_existing.decision,'companyWorkState',v_work.work_state
    );
  end if;

  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,decision,acceptance_kind,accepted_by_domain,evidence,metadata
  ) values(
    v_work.organization_id,v_work.id,v_result.id,v_decision,
    'organization_owner_review','organization',
    jsonb_strip_nulls(jsonb_build_object(
      'reason',nullif(btrim(coalesce(p_reason,'')),''),
      'authorityOrganizationId',v_effective_organization_id,
      'authorityOrganizationMembershipId',v_authority_membership_id,
      'authorityPrincipalId',v_authority_principal_id,
      'ownerUserId',v_uid,
      'physicalOrganizationId',v_work.organization_id,
      'reportedByOrganizationMembershipId',v_result.reported_by_organization_membership_id
    )),
    jsonb_build_object(
      'source','organization_owner_decide_company_work_result_api_v1',
      'institutionalCustodyMode','effective'
    )
  ) returning * into v_acceptance;

  if v_decision='accepted' and v_result.result_kind='completed' and v_work.work_state='open' then
    update atlas.work_items
      set work_state='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
      where id=v_work.id;
    update atlas.work_allocations
      set state='completed',completed_at=coalesce(completed_at,now()),updated_at=now()
      where id=v_result.responsible_allocation_id and state='active';
  elsif v_decision='rejected' and v_result.result_kind='completed' then
    begin
      v_projection_id:=nullif(v_result.metadata->>'projectionId','')::uuid;
    exception when invalid_text_representation then
      v_projection_id:=null;
    end;
    if v_projection_id is not null
       and v_result.reported_by_farm_membership_id is not null
       and v_result.reported_by_organization_membership_id is not null
       and exists(
         select 1 from atlas.worker_delivery_pilot_events e
         where e.projection_id=v_projection_id
           and e.delivery_membership_id=v_result.reported_by_farm_membership_id
           and e.event_kind='done_reported'
           and not exists(
             select 1 from atlas.worker_delivery_pilot_events r
             where r.projection_id=e.projection_id
               and r.delivery_membership_id=e.delivery_membership_id
               and r.event_seq>e.event_seq
               and r.event_kind='completion_reopened'
           )
       ) then
      insert into atlas.worker_delivery_pilot_events(
        organization_id,organization_membership_id,delivery_membership_id,projection_id,
        session_id,actor_user_id,event_kind,effective_at,metadata
      ) values(
        v_work.organization_id,v_result.reported_by_organization_membership_id,
        v_result.reported_by_farm_membership_id,v_projection_id,null,v_uid,
        'completion_reopened',clock_timestamp(),
        jsonb_strip_nulls(jsonb_build_object(
          'source','organization_owner_decide_company_work_result_api_v1',
          'executionResultId',v_result.id,
          'authorityOrganizationId',v_effective_organization_id,
          'reason',nullif(btrim(coalesce(p_reason,'')),'')
        ))
      );
    end if;
  end if;

  select * into v_work from atlas.work_items w where w.id=v_work.id;
  return jsonb_build_object(
    'state','decided','executionResultId',v_result.id,'workItemId',v_work.id,
    'organizationId',v_effective_organization_id,'physicalOrganizationId',v_work.organization_id,
    'decision',v_acceptance.decision,'acceptanceId',v_acceptance.id,
    'companyWorkState',v_work.work_state,'workerReportPreserved',true
  );
end;
$function$;

-- Restore original public API privilege boundaries after compatibility renames.
revoke all on function atlas.organization_access_self_api_v1() from public, anon;
revoke all on function atlas.current_session_context_api_v1() from public, anon;
revoke all on function atlas.principal_self_context_api_v1() from public, anon;
revoke all on function atlas.institutional_communications_home_self_api_v1() from public, anon;
grant execute on function atlas.organization_access_self_api_v1() to authenticated, service_role;
grant execute on function atlas.current_session_context_api_v1() to authenticated, service_role;
grant execute on function atlas.principal_self_context_api_v1() to authenticated, service_role;
grant execute on function atlas.institutional_communications_home_self_api_v1() to authenticated, service_role;

comment on function atlas.current_effective_organization_membership_v1(uuid) is
  'Canonical/effective membership resolver for selected runtime cutover surfaces. Existing physical current_organization_membership_v1 remains unchanged.';
comment on function atlas.is_effective_organization_owner_v1(uuid) is
  'Effective Organization-owner compatibility predicate for selected canonical surfaces only; excludes active custody carriers and does not replace physical is_organization_owner.';
comment on function atlas.effective_work_item_organization_v1(uuid) is
  'Resolves work-item Organization custody by direct adjudication, then explicit Organization-Unit adjudication. Never guesses an active compatibility carrier as canonical.';
comment on function atlas.effective_communication_endpoint_organization_v1(uuid) is
  'Resolves endpoint Organization custody by direct adjudication, then explicit Organization-Unit adjudication. Transport rows remain physical.';

commit;
