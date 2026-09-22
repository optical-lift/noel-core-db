begin;

-- Atlas Company Work Institutional Adjudication Authority v1
--
-- Explicit domain-local authority for accepting/rejecting Company Work Results.
-- Organization ownership may establish/revoke grants, but is not itself
-- decision authority after this cutover.

create table if not exists atlas.company_work_adjudication_authority_grants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references atlas.organizations(id) on delete cascade,
  membership_id uuid not null
    references atlas.organization_memberships(id) on delete cascade,
  authority_kind text not null
    check (authority_kind in ('result_acceptance')),
  scope_kind text not null
    check (scope_kind in ('organization','work_item')),
  scope_id uuid not null,
  grant_state text not null default 'active'
    check (grant_state in ('active','revoked')),
  granted_by_membership_id uuid
    references atlas.organization_memberships(id) on delete set null,
  grant_basis_kind text not null
    check (grant_basis_kind in (
      'organization_owner_compatibility_cutover',
      'explicit_owner_grant'
    )),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (revoked_at is null or grant_state='revoked')
);

create unique index if not exists
  company_work_adjudication_authority_grants_active_unique
on atlas.company_work_adjudication_authority_grants(
  organization_id,membership_id,authority_kind,scope_kind,scope_id
)
where grant_state='active';

alter table atlas.company_work_adjudication_authority_grants enable row level security;
revoke all on table atlas.company_work_adjudication_authority_grants
  from public,anon,authenticated,service_role;


create or replace function atlas.guard_company_work_adjudication_authority_grant_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_target atlas.organization_memberships%rowtype;
  v_grantor atlas.organization_memberships%rowtype;
  v_work_org uuid;
begin
  select * into v_target
  from atlas.organization_memberships m
  where m.id=new.membership_id;

  if v_target.id is null
     or v_target.organization_id<>new.organization_id then
    raise exception 'Adjudication authority target must belong to the grant Organization.'
      using errcode='23514';
  end if;

  if tg_op='INSERT' and new.grant_state='active'
     and not atlas.organization_membership_present_effective_at_v1(
       v_target.id,v_target.organization_id,now()
     ) then
    raise exception 'New adjudication authority requires a present-effective target Membership.'
      using errcode='23514';
  end if;

  if new.granted_by_membership_id is not null then
    select * into v_grantor
    from atlas.organization_memberships m
    where m.id=new.granted_by_membership_id;

    if v_grantor.id is null
       or v_grantor.organization_id<>new.organization_id then
      raise exception 'Adjudication grantor must belong to the same Organization.'
        using errcode='23514';
    end if;
  end if;

  if new.scope_kind='organization' then
    if new.scope_id<>new.organization_id then
      raise exception 'Organization-scoped adjudication authority must identify its own Organization.'
        using errcode='23514';
    end if;
  elsif new.scope_kind='work_item' then
    v_work_org:=atlas.effective_work_item_organization_v1(new.scope_id);
    if v_work_org is null or v_work_org<>new.organization_id then
      raise exception 'Work-scoped adjudication authority must identify Company Work in the same Organization.'
        using errcode='23514';
    end if;
  else
    raise exception 'Unsupported Company Work adjudication scope.'
      using errcode='22023';
  end if;

  if tg_op='UPDATE' then
    if old.organization_id is distinct from new.organization_id
       or old.membership_id is distinct from new.membership_id
       or old.authority_kind is distinct from new.authority_kind
       or old.scope_kind is distinct from new.scope_kind
       or old.scope_id is distinct from new.scope_id
       or old.granted_by_membership_id is distinct from new.granted_by_membership_id
       or old.grant_basis_kind is distinct from new.grant_basis_kind
       or old.granted_at is distinct from new.granted_at then
      raise exception 'Company Work adjudication grant identity/provenance is immutable.'
        using errcode='23514';
    end if;

    if old.grant_state='revoked' and new.grant_state<>'revoked' then
      raise exception 'Revoked Company Work adjudication authority cannot be reactivated.'
        using errcode='23514';
    end if;
  end if;

  if new.grant_state='active' and new.revoked_at is not null then
    raise exception 'Active adjudication authority cannot have a revocation timestamp.'
      using errcode='23514';
  end if;

  if new.grant_state='revoked' and new.revoked_at is null then
    new.revoked_at:=now();
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;

drop trigger if exists guard_company_work_adjudication_authority_grant_v1
  on atlas.company_work_adjudication_authority_grants;

create trigger guard_company_work_adjudication_authority_grant_v1
before insert or update on atlas.company_work_adjudication_authority_grants
for each row execute function atlas.guard_company_work_adjudication_authority_grant_v1();


-- Materialize current owner compatibility into explicit authority data.
insert into atlas.company_work_adjudication_authority_grants(
  organization_id,membership_id,authority_kind,scope_kind,scope_id,
  grant_state,granted_by_membership_id,grant_basis_kind,metadata
)
select
  om.organization_id,
  om.id,
  'result_acceptance',
  'organization',
  om.organization_id,
  'active',
  om.id,
  'organization_owner_compatibility_cutover',
  jsonb_build_object(
    'source','atlas_company_work_institutional_adjudication_authority_v1',
    'reason','Materialize previously implicit owner Result-adjudication compatibility as explicit authority.'
  )
from atlas.organization_memberships om
where om.role='owner'
  and atlas.organization_membership_present_effective_at_v1(
    om.id,om.organization_id,now()
  )
  and not exists (
    select 1
    from atlas.company_work_adjudication_authority_grants g
    where g.organization_id=om.organization_id
      and g.membership_id=om.id
      and g.authority_kind='result_acceptance'
      and g.scope_kind='organization'
      and g.scope_id=om.organization_id
      and g.grant_state='active'
  );


create or replace function atlas.company_work_result_adjudication_authority_v1(
  p_execution_result_id uuid,
  p_membership_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_result atlas.work_execution_results%rowtype;
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_grant atlas.company_work_adjudication_authority_grants%rowtype;
begin
  if p_execution_result_id is null or p_membership_id is null then
    return jsonb_build_object(
      'contractVersion','company_work_result_adjudication_authority_v1',
      'authorized',false,
      'reason','missing_subject',
      'truthBoundary',jsonb_build_object(
        'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true
      )
    );
  end if;

  select * into v_result
  from atlas.work_execution_results r
  where r.id=p_execution_result_id;

  if v_result.id is null then
    return jsonb_build_object(
      'contractVersion','company_work_result_adjudication_authority_v1',
      'authorized',false,
      'reason','result_not_found',
      'truthBoundary',jsonb_build_object(
        'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true
      )
    );
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id
    and w.organization_id=v_result.organization_id;

  if v_work.id is null then
    return jsonb_build_object(
      'contractVersion','company_work_result_adjudication_authority_v1',
      'authorized',false,
      'reason','work_not_found',
      'truthBoundary',jsonb_build_object(
        'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true
      )
    );
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_result.result_contract_key
    and p.active;

  if v_policy.contract_key is null
     or v_policy.acceptance_mode<>'manager_acceptance' then
    return jsonb_build_object(
      'contractVersion','company_work_result_adjudication_authority_v1',
      'authorized',false,
      'reason','result_not_governed_by_manager_acceptance',
      'organizationId',v_work.organization_id,
      'workItemId',v_work.id,
      'executionResultId',v_result.id,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true
      )
    );
  end if;

  select * into v_member
  from atlas.organization_memberships m
  where m.id=p_membership_id
    and m.organization_id=v_work.organization_id;

  if v_member.id is null
     or not atlas.organization_membership_present_effective_at_v1(
       v_member.id,v_member.organization_id,now()
     ) then
    return jsonb_build_object(
      'contractVersion','company_work_result_adjudication_authority_v1',
      'authorized',false,
      'reason','membership_not_present_effective',
      'organizationId',v_work.organization_id,
      'workItemId',v_work.id,
      'executionResultId',v_result.id,
      'actorOrganizationMembershipId',p_membership_id,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true
      )
    );
  end if;

  select * into v_grant
  from atlas.company_work_adjudication_authority_grants g
  where g.organization_id=v_work.organization_id
    and g.membership_id=v_member.id
    and g.authority_kind='result_acceptance'
    and g.grant_state='active'
    and (
      (g.scope_kind='work_item' and g.scope_id=v_work.id)
      or
      (g.scope_kind='organization' and g.scope_id=v_work.organization_id)
    )
  order by
    case g.scope_kind when 'work_item' then 0 else 1 end,
    case g.grant_basis_kind when 'explicit_owner_grant' then 0 else 1 end,
    g.granted_at desc,
    g.id
  limit 1;

  if v_grant.id is null then
    return jsonb_build_object(
      'contractVersion','company_work_result_adjudication_authority_v1',
      'authorized',false,
      'reason','explicit_adjudication_grant_required',
      'organizationId',v_work.organization_id,
      'workItemId',v_work.id,
      'executionResultId',v_result.id,
      'actorOrganizationMembershipId',v_member.id,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true,
        'doesNotInferFromOwnerRole',true,
        'doesNotInferFromFarmRole',true,
        'doesNotInferFromResponsibility',true,
        'doesNotInferFromWorkAllocation',true
      )
    );
  end if;

  return jsonb_build_object(
    'contractVersion','company_work_result_adjudication_authority_v1',
    'authorized',true,
    'reason','explicit_adjudication_grant',
    'organizationId',v_work.organization_id,
    'workItemId',v_work.id,
    'executionResultId',v_result.id,
    'actorOrganizationMembershipId',v_member.id,
    'authorityKind',v_grant.authority_kind,
    'grantId',v_grant.id,
    'grantBasisKind',v_grant.grant_basis_kind,
    'scopeKind',v_grant.scope_kind,
    'scopeId',v_grant.scope_id,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,'doesNotGrantAuthority',true,'doesNotDecide',true,
      'explicitGrantRequired',true
    )
  );
end;
$function$;

comment on function atlas.company_work_result_adjudication_authority_v1(uuid,uuid) is
  'Internal read-only authority resolver for Company Work Result acceptance. It recognizes only an active explicit Company Work adjudication grant; owner/manager/Farm/Responsibility/Work Allocation roles are not decision authority.';

revoke all on function atlas.company_work_result_adjudication_authority_v1(uuid,uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.set_company_work_adjudication_authority_self_api_v1(
  p_membership_id uuid,
  p_scope_kind text,
  p_scope_id uuid,
  p_enabled boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_scope_kind text:=lower(btrim(coalesce(p_scope_kind,'')));
  v_organization_id uuid;
  v_actor atlas.organization_memberships%rowtype;
  v_target atlas.organization_memberships%rowtype;
  v_existing atlas.company_work_adjudication_authority_grants%rowtype;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if p_membership_id is null or p_scope_id is null then
    raise exception 'Target Membership and adjudication scope are required.'
      using errcode='22023';
  end if;

  if v_scope_kind='organization' then
    v_organization_id:=p_scope_id;
  elsif v_scope_kind='work_item' then
    v_organization_id:=atlas.effective_work_item_organization_v1(p_scope_id);
    if v_organization_id is null then
      raise exception 'Company Work scope was not found.' using errcode='P0002';
    end if;
  else
    raise exception 'Adjudication scope must be organization or work_item.'
      using errcode='22023';
  end if;

  select * into v_actor
  from atlas.organization_memberships m
  where m.id=atlas.current_effective_organization_membership_v1(v_organization_id);

  if v_actor.id is null or v_actor.role<>'owner' then
    raise exception 'Present-effective Organization owner grant authority required.'
      using errcode='42501';
  end if;

  select * into v_target
  from atlas.organization_memberships m
  where m.id=p_membership_id
    and m.organization_id=v_organization_id;

  if v_target.id is null then
    raise exception 'Adjudication grant target must belong to the scoped Organization.'
      using errcode='23514';
  end if;

  if p_enabled
     and not atlas.organization_membership_present_effective_at_v1(
       v_target.id,v_target.organization_id,now()
     ) then
    raise exception 'New adjudication authority requires a present-effective target Membership.'
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.company_work_adjudication_authority_grants g
  where g.organization_id=v_organization_id
    and g.membership_id=v_target.id
    and g.authority_kind='result_acceptance'
    and g.scope_kind=v_scope_kind
    and g.scope_id=p_scope_id
    and g.grant_state='active'
  order by g.granted_at desc,g.id
  limit 1
  for update;

  if p_enabled then
    if v_existing.id is null then
      insert into atlas.company_work_adjudication_authority_grants(
        organization_id,membership_id,authority_kind,scope_kind,scope_id,
        granted_by_membership_id,grant_basis_kind,metadata
      ) values(
        v_organization_id,v_target.id,'result_acceptance',v_scope_kind,p_scope_id,
        v_actor.id,'explicit_owner_grant',
        jsonb_build_object(
          'source','set_company_work_adjudication_authority_self_api_v1',
          'reason',nullif(btrim(coalesce(p_reason,'')),'')
        )
      )
      returning * into v_existing;
    elsif v_existing.grant_basis_kind='organization_owner_compatibility_cutover' then
      update atlas.company_work_adjudication_authority_grants
      set grant_state='revoked',
          revoked_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'revocationReason','superseded_by_explicit_owner_grant',
            'revokedByMembershipId',v_actor.id,
            'reason',nullif(btrim(coalesce(p_reason,'')),'')
          )
      where id=v_existing.id;

      insert into atlas.company_work_adjudication_authority_grants(
        organization_id,membership_id,authority_kind,scope_kind,scope_id,
        granted_by_membership_id,grant_basis_kind,metadata
      ) values(
        v_organization_id,v_target.id,'result_acceptance',v_scope_kind,p_scope_id,
        v_actor.id,'explicit_owner_grant',
        jsonb_build_object(
          'source','set_company_work_adjudication_authority_self_api_v1',
          'reason',nullif(btrim(coalesce(p_reason,'')),''),
          'supersedesCompatibilityGrantId',v_existing.id
        )
      )
      returning * into v_existing;
    end if;
  else
    if v_existing.id is not null then
      update atlas.company_work_adjudication_authority_grants
      set grant_state='revoked',
          revoked_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'revocationReason',coalesce(
              nullif(btrim(coalesce(p_reason,'')),''),
              'explicit_owner_revocation'
            ),
            'revokedByMembershipId',v_actor.id
          )
      where id=v_existing.id
      returning * into v_existing;
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','company_work_adjudication_authority_grant_v1',
    'organizationId',v_organization_id,
    'membershipId',v_target.id,
    'authorityKind','result_acceptance',
    'scopeKind',v_scope_kind,
    'scopeId',p_scope_id,
    'enabled',p_enabled,
    'grantId',v_existing.id,
    'grantBasisKind',v_existing.grant_basis_kind,
    'grantState',v_existing.grant_state
  );
end;
$function$;

comment on function atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text) is
  'Organization-owner grant administration for explicit Company Work Result-adjudication authority. Ownership establishes/revokes the grant; it is not itself the decision authority.';

revoke all on function atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text)
  from public,anon;
grant execute on function atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text)
  to authenticated,service_role;


create or replace function atlas.organization_decide_company_work_result_self_api_v1(
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
  v_authority jsonb;
  v_projection_id uuid;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_execution_result_id is null then raise exception 'Company Work result required.' using errcode='22023'; end if;
  if v_decision not in ('accepted','rejected') then
    raise exception 'Decision must be accepted or rejected.' using errcode='22023';
  end if;

  select * into v_result
  from atlas.work_execution_results r
  where r.id=p_execution_result_id;

  if v_result.id is null then
    raise exception 'Company Work result was not found.' using errcode='P0002';
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id
    and w.organization_id=v_result.organization_id
  for update;

  if v_work.id is null then
    raise exception 'Company Work item was not found.' using errcode='P0002';
  end if;

  v_authority_membership_id:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id
  );

  if v_authority_membership_id is null then
    raise exception 'Present-effective Organization membership required.'
      using errcode='42501';
  end if;

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    v_result.id,v_authority_membership_id
  );

  if not coalesce((v_authority->>'authorized')::boolean,false) then
    raise exception 'Explicit Company Work Result-adjudication authority required.'
      using errcode='42501';
  end if;

  v_authority_principal_id:=atlas.current_principal_id_v1();

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_result.result_contract_key
    and p.active;

  if v_policy.contract_key is null
     or v_policy.acceptance_mode<>'manager_acceptance' then
    raise exception 'This Company Work result is not governed by manager acceptance.'
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.work_result_acceptances a
  where a.execution_result_id=v_result.id;

  if v_existing.id is not null then
    if v_existing.decision<>v_decision then
      raise exception 'This Company Work result already has a different institutional decision.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'state','deduplicated',
      'executionResultId',v_result.id,
      'workItemId',v_work.id,
      'organizationId',v_work.organization_id,
      'decision',v_existing.decision,
      'companyWorkState',v_work.work_state,
      'authorityGrantId',v_authority->>'grantId'
    );
  end if;

  insert into atlas.work_result_acceptances(
    organization_id,work_item_id,execution_result_id,decision,
    acceptance_kind,accepted_by_domain,evidence,metadata
  ) values(
    v_work.organization_id,v_work.id,v_result.id,v_decision,
    'institutional_adjudication_authority','organization',
    jsonb_strip_nulls(jsonb_build_object(
      'reason',nullif(btrim(coalesce(p_reason,'')),''),
      'authorityOrganizationId',v_work.organization_id,
      'authorityOrganizationMembershipId',v_authority_membership_id,
      'authorityPrincipalId',v_authority_principal_id,
      'authorityGrantId',v_authority->>'grantId',
      'authorityGrantBasisKind',v_authority->>'grantBasisKind',
      'authorityScopeKind',v_authority->>'scopeKind',
      'authorityScopeId',v_authority->>'scopeId',
      'actorUserId',v_uid,
      'reportedByOrganizationMembershipId',v_result.reported_by_organization_membership_id
    )),
    jsonb_build_object(
      'source','organization_decide_company_work_result_self_api_v1',
      'institutionalCustodyMode','effective',
      'explicitAdjudicationAuthority',true
    )
  )
  returning * into v_acceptance;

  if v_decision='accepted'
     and v_result.result_kind='completed'
     and v_work.work_state='open' then

    update atlas.work_items
    set work_state='completed',
        completed_at=coalesce(completed_at,now()),
        updated_at=now()
    where id=v_work.id;

    update atlas.work_allocations
    set state='completed',
        completed_at=coalesce(completed_at,now()),
        updated_at=now()
    where id=v_result.responsible_allocation_id
      and state='active';

  elsif v_decision='rejected'
        and v_result.result_kind='completed' then

    begin
      v_projection_id:=nullif(v_result.metadata->>'projectionId','')::uuid;
    exception when invalid_text_representation then
      v_projection_id:=null;
    end;

    if v_projection_id is not null
       and v_result.reported_by_farm_membership_id is not null
       and v_result.reported_by_organization_membership_id is not null
       and exists(
         select 1
         from atlas.worker_delivery_pilot_events e
         where e.projection_id=v_projection_id
           and e.delivery_membership_id=v_result.reported_by_farm_membership_id
           and e.event_kind='done_reported'
           and not exists(
             select 1
             from atlas.worker_delivery_pilot_events r
             where r.projection_id=e.projection_id
               and r.delivery_membership_id=e.delivery_membership_id
               and r.event_seq>e.event_seq
               and r.event_kind='completion_reopened'
           )
       ) then
      insert into atlas.worker_delivery_pilot_events(
        organization_id,organization_membership_id,delivery_membership_id,
        projection_id,session_id,actor_user_id,event_kind,effective_at,metadata
      ) values(
        v_work.organization_id,
        v_result.reported_by_organization_membership_id,
        v_result.reported_by_farm_membership_id,
        v_projection_id,
        null,
        v_uid,
        'completion_reopened',
        clock_timestamp(),
        jsonb_strip_nulls(jsonb_build_object(
          'source','organization_decide_company_work_result_self_api_v1',
          'executionResultId',v_result.id,
          'authorityOrganizationId',v_work.organization_id,
          'authorityGrantId',v_authority->>'grantId',
          'reason',nullif(btrim(coalesce(p_reason,'')),'')
        ))
      );
    end if;
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_work.id;

  return jsonb_build_object(
    'state','decided',
    'executionResultId',v_result.id,
    'workItemId',v_work.id,
    'organizationId',v_work.organization_id,
    'decision',v_acceptance.decision,
    'acceptanceId',v_acceptance.id,
    'companyWorkState',v_work.work_state,
    'authorityGrantId',v_authority->>'grantId',
    'authorityScopeKind',v_authority->>'scopeKind',
    'workerReportPreserved',true
  );
end;
$function$;

comment on function atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text) is
  'Grant-governed Company Work Result acceptance/rejection. The signed-in actor must hold explicit active Company Work adjudication authority for the exact Result scope.';

revoke all on function atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)
  from public,anon;
grant execute on function atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)
  to authenticated,service_role;


-- Retain the old RPC as a compatibility wrapper only. Ownership is checked as
-- the historical entry contract, but the delegated command still requires an
-- explicit adjudication grant.
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
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_result
  from atlas.work_execution_results r
  where r.id=p_execution_result_id;

  if v_result.id is null then
    raise exception 'Company Work result was not found.' using errcode='P0002';
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id
    and w.organization_id=v_result.organization_id;

  if v_work.id is null then
    raise exception 'Company Work item was not found.' using errcode='P0002';
  end if;

  if not atlas.is_effective_organization_owner_v1(v_work.organization_id) then
    raise exception 'Organization owner compatibility entry requires current owner governance.'
      using errcode='42501';
  end if;

  return atlas.organization_decide_company_work_result_self_api_v1(
    p_execution_result_id,p_decision,p_reason
  );
end;
$function$;

comment on function atlas.organization_owner_decide_company_work_result_api_v1(uuid,text,text) is
  'Compatibility wrapper for the former owner-only Result decision RPC. It retains the owner entry check but terminates at the explicit-grant-governed decision command; ownership alone no longer satisfies decision authority.';


create or replace function atlas.company_work_result_decision_requirement_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_plan jsonb;
  v_result atlas.work_execution_results%rowtype;
  v_work atlas.work_items%rowtype;
  v_policy atlas.work_result_contract_policies%rowtype;
  v_target jsonb;
  v_target_count integer := 0;
  v_authority_target_count integer := 0;
begin
  if p_execution_result_id is null then
    raise exception 'Company Work execution Result is required.'
      using errcode='22023';
  end if;

  select * into v_result
  from atlas.work_execution_results r
  where r.id=p_execution_result_id;

  if v_result.id is null then
    raise exception 'Company Work execution Result was not found.'
      using errcode='P0002';
  end if;

  select * into v_work
  from atlas.work_items w
  where w.id=v_result.work_item_id
    and w.organization_id=v_result.organization_id;

  if v_work.id is null then
    raise exception 'Company Work item for execution Result was not found.'
      using errcode='P0002';
  end if;

  select * into v_policy
  from atlas.work_result_contract_policies p
  where p.contract_key=v_result.result_contract_key
    and p.active;

  v_plan:=atlas.company_work_result_reconciliation_plan_v1(v_result.id);
  v_target_count:=jsonb_array_length(coalesce(v_plan->'targets','[]'::jsonb));

  if v_target_count=0 then
    return jsonb_build_object(
      'contractVersion','company_work_result_decision_requirement_v1',
      'state','settled',
      'source',v_plan->'source',
      'work',jsonb_build_object(
        'workItemId',v_work.id,
        'organizationId',v_work.organization_id,
        'title',v_work.title
      ),
      'reportedResult',jsonb_strip_nulls(jsonb_build_object(
        'resultKind',v_result.result_kind,
        'reportedAt',v_result.reported_at
      )),
      'decision',null,
      'authorityRequirement',null,
      'reconciliationPlan',v_plan,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'doesNotDecide',true,
        'doesNotGrantAuthority',true,
        'doesNotCreateWork',true,
        'doesNotCreateQueueState',true,
        'doesNotExposeResultPayload',true
      )
    );
  end if;

  select count(*)::integer
  into v_authority_target_count
  from jsonb_array_elements(coalesce(v_plan->'targets','[]'::jsonb)) x(value)
  where value->>'handlingMode'='authority_required'
    and value#>>'{resolver,key}'='company_work_result_adjudication';

  select value into v_target
  from jsonb_array_elements(coalesce(v_plan->'targets','[]'::jsonb)) x(value)
  where value->>'handlingMode'='authority_required'
    and value#>>'{resolver,key}'='company_work_result_adjudication'
  limit 1;

  if v_authority_target_count<>1 or v_target_count<>1 then
    return jsonb_build_object(
      'contractVersion','company_work_result_decision_requirement_v1',
      'state','not_decision_requirement',
      'source',v_plan->'source',
      'work',jsonb_build_object(
        'workItemId',v_work.id,
        'organizationId',v_work.organization_id,
        'title',v_work.title
      ),
      'reportedResult',jsonb_strip_nulls(jsonb_build_object(
        'resultKind',v_result.result_kind,
        'reportedAt',v_result.reported_at
      )),
      'decision',null,
      'authorityRequirement',null,
      'reconciliationPlan',v_plan,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'doesNotDecide',true,
        'doesNotGrantAuthority',true,
        'doesNotCreateWork',true,
        'doesNotCreateQueueState',true,
        'doesNotExposeResultPayload',true
      )
    );
  end if;

  if v_policy.contract_key is null
     or v_policy.acceptance_mode<>'manager_acceptance' then
    raise exception 'Authority-required Company Work Result does not have the released manager-acceptance contract.'
      using errcode='23514';
  end if;

  return jsonb_build_object(
    'contractVersion','company_work_result_decision_requirement_v1',
    'state','decision_required',
    'source',v_plan->'source',
    'work',jsonb_build_object(
      'workItemId',v_work.id,
      'organizationId',v_work.organization_id,
      'title',v_work.title
    ),
    'reportedResult',jsonb_strip_nulls(jsonb_build_object(
      'resultKind',v_result.result_kind,
      'reportedAt',v_result.reported_at
    )),
    'decision',jsonb_build_object(
      'kind','company_work_result_acceptance',
      'options',jsonb_build_array('accepted','rejected'),
      'command',jsonb_build_object(
        'key','organization_decide_company_work_result',
        'signature','atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)'
      )
    ),
    'authorityRequirement',jsonb_build_object(
      'dimension','institutional_adjudication_authority',
      'currentBasis','explicit_company_work_adjudication_grant',
      'authorityKind','result_acceptance',
      'exactAuthorityResolver','company_work_result_adjudication_authority_v1'
    ),
    'reconciliation',jsonb_build_object(
      'handlingMode',v_target->>'handlingMode',
      'resolver',v_target->'resolver',
      'reason',v_target->'reason',
      'blockers',coalesce(v_target->'blockers','[]'::jsonb)
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotDecide',true,
      'doesNotGrantAuthority',true,
      'doesNotCreateWork',true,
      'doesNotCreateQueueState',true,
      'doesNotExposeResultPayload',true,
      'explicitAdjudicationGrantRequired',true
    )
  );
end;
$function$;


create or replace function atlas.company_work_result_decision_requirement_self_api_v1(
  p_execution_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_requirement jsonb;
  v_organization_id uuid;
  v_membership_id uuid;
  v_authority jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_requirement:=atlas.company_work_result_decision_requirement_v1(
    p_execution_result_id
  );
  v_organization_id:=nullif(v_requirement#>>'{work,organizationId}','')::uuid;

  if v_organization_id is null then
    raise exception 'Company Work decision requirement has no Organization authority scope.'
      using errcode='23514';
  end if;

  v_membership_id:=atlas.current_effective_organization_membership_v1(
    v_organization_id
  );

  if v_membership_id is null then
    raise exception 'Present-effective Organization membership required.'
      using errcode='42501';
  end if;

  v_authority:=atlas.company_work_result_adjudication_authority_v1(
    p_execution_result_id,v_membership_id
  );

  if not coalesce((v_authority->>'authorized')::boolean,false) then
    raise exception 'Explicit Company Work Result-adjudication authority required.'
      using errcode='42501';
  end if;

  return v_requirement||jsonb_build_object(
    'actorAuthority',jsonb_build_object(
      'canDecide',v_requirement->>'state'='decision_required',
      'actorOrganizationMembershipId',v_membership_id,
      'basis','explicit_company_work_adjudication_grant',
      'grantId',v_authority->>'grantId',
      'grantBasisKind',v_authority->>'grantBasisKind',
      'scopeKind',v_authority->>'scopeKind',
      'scopeId',v_authority->>'scopeId',
      'matchesExactCurrentCommandAuthority',true
    )
  );
end;
$function$;


create or replace function atlas.company_work_decision_requirements_self_api_v1(
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_person_id uuid;
  v_items jsonb:='[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if coalesce(p_limit,0)<1 or p_limit>100 then
    raise exception 'Decision Requirement limit must be between 1 and 100.'
      using errcode='22023';
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'contractVersion','company_work_decision_requirements_self_v1',
      'items','[]'::jsonb,
      'count',0,
      'derivedProjection',true,
      'persistedQueue',false,
      'authorityBasis','explicit_company_work_adjudication_grant'
    );
  end if;

  select coalesce(
    jsonb_agg(q.requirement order by q.reported_at,q.execution_result_id),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      r.id execution_result_id,
      r.reported_at,
      atlas.company_work_result_decision_requirement_v1(r.id)
        || jsonb_build_object(
          'actorAuthority',jsonb_build_object(
            'canDecide',true,
            'actorOrganizationMembershipId',om.id,
            'basis','explicit_company_work_adjudication_grant',
            'grantId',authority.value->>'grantId',
            'grantBasisKind',authority.value->>'grantBasisKind',
            'scopeKind',authority.value->>'scopeKind',
            'scopeId',authority.value->>'scopeId',
            'matchesExactCurrentCommandAuthority',true
          )
        ) requirement
    from atlas.work_execution_results r
    join atlas.work_items w
      on w.id=r.work_item_id
     and w.organization_id=r.organization_id
    join atlas.work_result_contract_policies p
      on p.contract_key=r.result_contract_key
     and p.active
     and p.acceptance_mode='manager_acceptance'
    join lateral (
      select m.id
      from atlas.organization_memberships m
      where m.organization_id=w.organization_id
        and m.person_id=v_person_id
        and atlas.organization_membership_present_effective_at_v1(
          m.id,m.organization_id,now()
        )
      order by m.created_at,m.id
      limit 1
    ) om on true
    join lateral (
      select atlas.company_work_result_adjudication_authority_v1(
        r.id,om.id
      ) as value
    ) authority on coalesce((authority.value->>'authorized')::boolean,false)
    where not exists (
      select 1
      from atlas.work_result_acceptances a
      where a.execution_result_id=r.id
    )
      and (
        atlas.company_work_result_decision_requirement_v1(r.id)->>'state'
      )='decision_required'
    order by r.reported_at,r.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','company_work_decision_requirements_self_v1',
    'items',v_items,
    'count',jsonb_array_length(v_items),
    'derivedProjection',true,
    'persistedQueue',false,
    'authorityBasis','explicit_company_work_adjudication_grant',
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotDecide',true,
      'doesNotGrantAuthority',true,
      'doesNotCreateWork',true,
      'doesNotCreateQueueState',true,
      'doesNotExposeResultPayload',true
    )
  );
end;
$function$;


insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,
  evidence,anonymous_execute_expected
) values
(
  'atlas.company_work_result_adjudication_authority_v1(uuid,uuid)',
  'service_internal','verified','active',
  false,true,false,0,1,
  jsonb_build_object(
    'source','atlas_company_work_institutional_adjudication_authority_v1',
    'purpose','Resolve exact Company Work Result-adjudication authority from explicit active domain-local grants.',
    'truthBoundary','Read-only; owner/manager/Farm/Responsibility/Work Allocation relations are not inferred as decision authority.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.set_company_work_adjudication_authority_self_api_v1(uuid,text,uuid,boolean,text)',
  'app_endpoint','verified','active',
  true,true,true,0,1,
  jsonb_build_object(
    'source','atlas_company_work_institutional_adjudication_authority_v1',
    'purpose','Allow current Organization owner root governance to establish or revoke bounded Company Work Result-adjudication authority.',
    'truthBoundary','Grant administration only; does not decide a Result or establish Work responsibility.',
    'classificationRuleVersion',3
  ),
  false
),
(
  'atlas.organization_decide_company_work_result_self_api_v1(uuid,text,text)',
  'app_endpoint','verified','active',
  true,true,true,0,1,
  jsonb_build_object(
    'source','atlas_company_work_institutional_adjudication_authority_v1',
    'purpose','Accept or reject a manager-acceptance Company Work Result when the signed-in actor holds an exact explicit adjudication grant.',
    'truthBoundary','Decision authority comes only from company_work_adjudication_authority_grants; owner role alone is insufficient.',
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

update atlas.authenticated_rpc_registry
set evidence=jsonb_build_object(
      'source','atlas_company_work_institutional_adjudication_authority_v1',
      'purpose','Compatibility entry for the former owner-only Result decision RPC.',
      'truthBoundary','Owner entry check remains, but the command terminates at organization_decide_company_work_result_self_api_v1 and cannot decide without an explicit adjudication grant.',
      'classificationRuleVersion',3
    ),
    reviewed_at=now()
where signature='atlas.organization_owner_decide_company_work_result_api_v1(uuid, text, text)';

commit;
