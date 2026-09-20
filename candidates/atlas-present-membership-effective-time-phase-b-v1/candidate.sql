-- Present Organization Membership Effective Time Phase B candidate.
-- Candidate source only. Depends on Organization Membership Calendar Context Phase A.
-- Do not promote or release before Phase A is source-merged, production-released, and verified.

begin;

do $precondition$
begin
  if to_regclass('atlas.organization_membership_calendar_contexts') is null
     or to_regprocedure('atlas.organization_membership_calendar_date_at_v1(uuid,timestamptz)') is null then
    raise exception 'Effective Time Phase B requires Organization Membership Calendar Context Phase A.'
      using errcode='55000';
  end if;
end;
$precondition$;

create or replace function atlas.organization_membership_present_effective_at_v1(
  p_membership_id uuid,
  p_organization_id uuid,
  p_at timestamptz
)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_member atlas.organization_memberships%rowtype;
  v_date date;
begin
  if p_membership_id is null
     or p_organization_id is null
     or p_at is null then
    return false;
  end if;

  select * into v_member
  from atlas.organization_memberships m
  where m.id=p_membership_id
    and m.organization_id=p_organization_id;

  if v_member.id is null or not v_member.active then
    return false;
  end if;

  if v_member.eligibility_begins_on is null
     and v_member.eligibility_ends_on is null then
    return true;
  end if;

  v_date:=atlas.organization_membership_calendar_date_at_v1(
    p_organization_id,p_at
  );

  if v_date is null then
    return false;
  end if;

  return atlas.organization_membership_eligible_on_date_v1(
    p_membership_id,p_organization_id,v_date
  );
end;
$function$;

revoke all on function atlas.organization_membership_present_effective_at_v1(
  uuid,uuid,timestamptz
) from public,anon,authenticated;
grant execute on function atlas.organization_membership_present_effective_at_v1(
  uuid,uuid,timestamptz
) to postgres,service_role;

comment on function atlas.organization_membership_present_effective_at_v1(uuid,uuid,timestamptz) is
'Canonical exact present-effective Organization Membership predicate. Unbounded active Memberships require no calendar context. Bounded Memberships require the Organization Membership Calendar Context and fail closed when it is unresolved. Explicit service-date eligibility remains separate.';

create or replace function atlas.current_effective_organization_membership_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select om.id
  from atlas.organization_memberships om
  where om.person_id=atlas.current_person_id_v1()
    and om.organization_id=p_organization_id
    and atlas.organization_membership_present_effective_at_v1(
      om.id,om.organization_id,now()
    )
  order by
    case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end,
    om.created_at,
    om.id
  limit 1
$function$;

comment on function atlas.current_effective_organization_membership_v1(uuid) is
'Canonical current Person to present-effective Organization Membership resolver. Administrative activity alone is insufficient.';

create or replace function atlas.current_organization_membership_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select atlas.current_effective_organization_membership_v1(p_organization_id)
$function$;

comment on function atlas.current_organization_membership_v1(uuid) is
'Compatibility alias for current present-effective Organization Membership. Administrative-only Membership inspection requires a separately named resolver.';

create or replace function atlas.is_organization_member(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select p_organization_id is not null
     and atlas.current_effective_organization_membership_v1(
       p_organization_id
     ) is not null
$function$;

comment on function atlas.is_organization_member(uuid) is
'Current present-effective Organization Membership predicate for the authenticated canonical Person.';

create or replace function atlas.is_organization_owner(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select exists(
    select 1
    from atlas.organization_memberships om
    where om.id=atlas.current_effective_organization_membership_v1(
      p_organization_id
    )
      and om.organization_id=p_organization_id
      and om.role='owner'
  )
$function$;

comment on function atlas.is_organization_owner(uuid) is
'Current present-effective Organization owner Membership predicate. Owner role without present-effective Membership is not current governance authority.';

create or replace function atlas.is_effective_organization_owner_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select p_organization_id is not null and (
    atlas.is_organization_owner(p_organization_id)
    or exists (
      select 1
      from atlas.principal_ledger_authorities pla
      join atlas.ledger_organization_participations lop
        on lop.ledger_id=pla.ledger_id
       and lop.organization_id=p_organization_id
       and lop.status='active'
       and lop.participation_kind='governing'
       and lop.is_compatibility_primary
      join atlas.ledgers l
        on l.id=pla.ledger_id
       and l.status='active'
      where pla.principal_id=atlas.current_principal_id_v1()
        and pla.status='active'
        and pla.authority_kind='root_governing'
    )
  )
$function$;

comment on function atlas.is_effective_organization_owner_v1(uuid) is
'Current Organization governance authority: present-effective owner Membership OR independent Principal Ledger root-governing authority. Root governance does not become Membership.';

create or replace function atlas.communication_endpoint_membership_has_capability_v1(
  p_endpoint_id uuid,
  p_membership_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select exists(
    select 1
    from atlas.communication_endpoints ep
    join atlas.organization_memberships om
      on om.id=p_membership_id
     and om.organization_id=ep.organization_id
    join atlas.communication_endpoint_member_grants g
      on g.communication_endpoint_id=ep.id
     and g.membership_id=om.id
     and g.capability=lower(btrim(coalesce(p_capability,'')))
     and g.grant_state='active'
    where ep.id=p_endpoint_id
      and ep.endpoint_state='active'
      and ep.organization_id is not null
      and atlas.organization_membership_present_effective_at_v1(
        om.id,om.organization_id,now()
      )
      and g.grant_basis_kind in (
        'organization_owner_compatibility_cutover',
        'endpoint_creator_initial_grant',
        'explicit_owner_grant'
      )
      and (
        g.grant_basis_kind<>'organization_owner_compatibility_cutover'
        or om.role='owner'
      )
  )
$function$;

comment on function atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text) is
'Exact Endpoint capability resolver. Capability requires a present-effective Organization Membership. Bounded Memberships are lawful when current under their governed Membership Calendar Context; missing context fails closed.';

create or replace function atlas.guard_communication_endpoint_member_grant_v2()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_member atlas.organization_memberships%rowtype;
  v_granter atlas.organization_memberships%rowtype;
begin
  select * into v_endpoint
  from atlas.communication_endpoints
  where id=new.communication_endpoint_id;

  if v_endpoint.id is null or v_endpoint.organization_id is null then
    raise exception 'Organization Endpoint grant requires an Organization-owned Communication Endpoint.'
      using errcode='23514';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where id=new.membership_id;

  if v_member.id is null
     or v_member.organization_id is distinct from v_endpoint.organization_id then
    raise exception 'Endpoint grant target Membership must belong to the Endpoint Organization.'
      using errcode='23514';
  end if;

  if new.granted_by_membership_id is not null then
    select * into v_granter
    from atlas.organization_memberships
    where id=new.granted_by_membership_id;

    if v_granter.id is null
       or v_granter.organization_id is distinct from v_endpoint.organization_id then
      raise exception 'Endpoint grant actor Membership must belong to the Endpoint Organization.'
        using errcode='23514';
    end if;
  end if;

  if tg_op='UPDATE' then
    if new.grant_basis_kind is distinct from old.grant_basis_kind then
      raise exception 'Endpoint grant origin is immutable. Revoke the old grant and append a new grant instead.'
        using errcode='23514';
    end if;

    if old.grant_state='revoked' and new.grant_state='active' then
      raise exception 'Revoked Endpoint grants cannot be reactivated in place.'
        using errcode='23514';
    end if;
  end if;

  if tg_op='INSERT' and new.grant_state='active' then
    if not atlas.organization_membership_present_effective_at_v1(
      v_member.id,v_member.organization_id,now()
    ) then
      raise exception 'Endpoint authority requires a present-effective Organization Membership.'
        using errcode='23514';
    end if;

    if new.grant_basis_kind='organization_owner_compatibility_cutover' then
      if v_member.role<>'owner' then
        raise exception 'Owner compatibility grant requires an Organization owner Membership.'
          using errcode='23514';
      end if;
      if new.granted_by_membership_id is not null then
        raise exception 'Compatibility materialization is not an actor-authored grant.'
          using errcode='23514';
      end if;
    else
      if new.granted_by_membership_id is null then
        raise exception 'Explicit or Endpoint-creator grant requires a governing actor Membership.'
          using errcode='23514';
      end if;
      if v_granter.role<>'owner'
         or not atlas.organization_membership_present_effective_at_v1(
           v_granter.id,v_granter.organization_id,now()
         ) then
        raise exception 'Endpoint grant actor must be a present-effective Organization owner.'
          using errcode='23514';
      end if;
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_communication_endpoint_member_grant_v2()
from public,anon,authenticated,service_role;

create or replace function atlas.revoke_owner_compatibility_endpoint_grants_on_membership_change()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_date date;
  v_old_effective boolean;
  v_new_effective boolean;
begin
  if old.eligibility_begins_on is null
     and old.eligibility_ends_on is null then
    v_old_effective:=old.active;
  else
    v_date:=atlas.organization_membership_calendar_date_at_v1(
      old.organization_id,now()
    );
    v_old_effective:=old.active
      and v_date is not null
      and (old.eligibility_begins_on is null or old.eligibility_begins_on<=v_date)
      and (old.eligibility_ends_on is null or old.eligibility_ends_on>=v_date);
  end if;

  if new.eligibility_begins_on is null
     and new.eligibility_ends_on is null then
    v_new_effective:=new.active;
  else
    if v_date is null then
      v_date:=atlas.organization_membership_calendar_date_at_v1(
        new.organization_id,now()
      );
    end if;
    v_new_effective:=new.active
      and v_date is not null
      and (new.eligibility_begins_on is null or new.eligibility_begins_on<=v_date)
      and (new.eligibility_ends_on is null or new.eligibility_ends_on>=v_date);
  end if;

  if new.role<>'owner'
     or not v_new_effective
     or (not v_old_effective and v_new_effective) then
    update atlas.communication_endpoint_member_grants g
    set grant_state='revoked',
        revoked_at=coalesce(g.revoked_at,now()),
        metadata=coalesce(g.metadata,'{}'::jsonb)
          ||jsonb_build_object(
            'revocationReason',
              case
                when not v_new_effective then 'organization_owner_compatibility_continuity_ended'
                when not v_old_effective and v_new_effective then 'organization_owner_compatibility_temporal_gap'
                else 'organization_owner_compatibility_role_ended'
              end,
            'membershipRole',new.role,
            'membershipActive',new.active,
            'eligibilityBeginsOn',new.eligibility_begins_on,
            'eligibilityEndsOn',new.eligibility_ends_on
          ),
        updated_at=now()
    where g.membership_id=new.id
      and g.grant_state='active'
      and g.grant_basis_kind='organization_owner_compatibility_cutover';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.revoke_owner_compatibility_endpoint_grants_on_membership_change()
from public,anon,authenticated,service_role;

create or replace function atlas.set_communication_endpoint_member_capability_self_api_v1(
  p_communication_endpoint_id uuid,
  p_membership_id uuid,
  p_capability text,
  p_enabled boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_actor atlas.organization_memberships%rowtype;
  v_target atlas.organization_memberships%rowtype;
  v_existing atlas.communication_endpoint_member_grants%rowtype;
  v_cap text:=lower(btrim(coalesce(p_capability,'')));
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id;

  if v_endpoint.id is null or v_endpoint.organization_id is null then
    raise exception 'Organization Communication Endpoint not found.'
      using errcode='P0002';
  end if;

  select * into v_actor
  from atlas.organization_memberships
  where id=atlas.current_effective_organization_membership_v1(
    v_endpoint.organization_id
  );

  if v_actor.id is null or v_actor.role<>'owner' then
    raise exception 'Present-effective Organization owner governance authority required.'
      using errcode='42501';
  end if;

  if v_cap not in ('view','send','claim','handoff','close','admin') then
    raise exception 'Unsupported communication endpoint capability.'
      using errcode='22023';
  end if;

  select * into v_target
  from atlas.organization_memberships
  where id=p_membership_id
    and organization_id=v_endpoint.organization_id;

  if v_target.id is null
     or not atlas.organization_membership_present_effective_at_v1(
       v_target.id,v_target.organization_id,now()
     ) then
    raise exception 'Endpoint grant target must be a present-effective Membership in the Endpoint Organization.'
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.communication_endpoint_member_grants
  where communication_endpoint_id=v_endpoint.id
    and membership_id=v_target.id
    and capability=v_cap
    and grant_state='active'
  limit 1
  for update;

  if p_enabled then
    if v_existing.id is null then
      insert into atlas.communication_endpoint_member_grants(
        communication_endpoint_id,membership_id,capability,
        granted_by_membership_id,grant_basis_kind,metadata
      ) values(
        v_endpoint.id,v_target.id,v_cap,
        v_actor.id,'explicit_owner_grant',
        jsonb_build_object(
          'reason',nullif(btrim(coalesce(p_reason,'')),''),
          'source','set_communication_endpoint_member_capability_self_api_v1'
        )
      )
      returning * into v_existing;
    elsif v_existing.grant_basis_kind='organization_owner_compatibility_cutover' then
      update atlas.communication_endpoint_member_grants
      set grant_state='revoked',
          revoked_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)
            ||jsonb_build_object(
              'revocationReason','superseded_by_explicit_owner_grant',
              'revokedByMembershipId',v_actor.id,
              'reason',nullif(btrim(coalesce(p_reason,'')),'')
            ),
          updated_at=now()
      where id=v_existing.id;

      insert into atlas.communication_endpoint_member_grants(
        communication_endpoint_id,membership_id,capability,
        granted_by_membership_id,grant_basis_kind,metadata
      ) values(
        v_endpoint.id,v_target.id,v_cap,
        v_actor.id,'explicit_owner_grant',
        jsonb_build_object(
          'reason',nullif(btrim(coalesce(p_reason,'')),''),
          'source','set_communication_endpoint_member_capability_self_api_v1',
          'supersedesCompatibilityGrantId',v_existing.id
        )
      )
      returning * into v_existing;
    end if;
  else
    if v_existing.id is not null then
      update atlas.communication_endpoint_member_grants
      set grant_state='revoked',
          revoked_at=now(),
          metadata=coalesce(metadata,'{}'::jsonb)
            ||jsonb_build_object(
              'revocationReason',coalesce(
                nullif(btrim(coalesce(p_reason,'')),''),
                'explicit_owner_revocation'
              ),
              'revokedByMembershipId',v_actor.id
            ),
          updated_at=now()
      where id=v_existing.id
      returning * into v_existing;
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','communication_endpoint_member_capability_v1',
    'communicationEndpointId',v_endpoint.id,
    'membershipId',v_target.id,
    'capability',v_cap,
    'enabled',p_enabled,
    'grantId',v_existing.id,
    'grantBasisKind',v_existing.grant_basis_kind
  );
end;
$function$;

create or replace function atlas.upsert_communication_endpoint_self_api_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_endpoint_kind text,
  p_address text,
  p_display_name text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_member atlas.organization_memberships%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_kind text:=lower(btrim(coalesce(p_endpoint_kind,'')));
  v_address text:=btrim(coalesce(p_address,''));
  v_norm text;
  v_created boolean:=false;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_member
  from atlas.organization_memberships
  where id=atlas.current_effective_organization_membership_v1(
    p_organization_id
  );

  if v_member.id is null or v_member.role<>'owner' then
    raise exception 'Present-effective Organization owner authority required.'
      using errcode='42501';
  end if;

  if p_organization_unit_id is not null
     and not exists(
       select 1
       from atlas.organization_units u
       where u.organization_id=p_organization_id
         and u.id=p_organization_unit_id
     ) then
    raise exception 'Organization unit is outside organization.'
      using errcode='23514';
  end if;

  if v_kind not in (
    'email','phone','sms','voice','web_form','social','atlas_native','other'
  ) or v_address='' then
    raise exception 'Valid endpoint kind and address are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Endpoint metadata must be an object.'
      using errcode='22023';
  end if;

  v_norm:=atlas.normalize_communication_endpoint_address_v1(
    v_kind,v_address
  );

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.organization_id=p_organization_id
    and ep.organization_unit_id is not distinct from p_organization_unit_id
    and ep.endpoint_kind=v_kind
    and ep.address_normalized=v_norm
  for update;

  if v_endpoint.id is null then
    insert into atlas.communication_endpoints(
      organization_id,organization_unit_id,endpoint_kind,address,
      address_normalized,display_name,metadata
    ) values(
      p_organization_id,p_organization_unit_id,v_kind,v_address,
      v_norm,nullif(btrim(p_display_name),''),
      coalesce(p_metadata,'{}'::jsonb)
    )
    returning * into v_endpoint;

    v_created:=true;

    insert into atlas.communication_endpoint_member_grants(
      communication_endpoint_id,membership_id,capability,
      granted_by_membership_id,grant_basis_kind,metadata
    )
    select
      v_endpoint.id,
      v_member.id,
      caps.capability,
      v_member.id,
      'endpoint_creator_initial_grant',
      jsonb_build_object(
        'source','upsert_communication_endpoint_self_api_v1',
        'reason','endpoint_creator_initial_capabilities'
      )
    from (
      values ('view'::text),('send'),('claim'),('handoff'),('close'),('admin')
    ) as caps(capability);
  else
    update atlas.communication_endpoints
    set display_name=coalesce(
          nullif(btrim(p_display_name),''),display_name
        ),
        metadata=metadata||coalesce(p_metadata,'{}'::jsonb),
        endpoint_state='active',
        updated_at=now()
    where id=v_endpoint.id
    returning * into v_endpoint;
  end if;

  return jsonb_build_object(
    'contractVersion','communication_endpoint_v1',
    'communicationEndpointId',v_endpoint.id,
    'organizationId',v_endpoint.organization_id,
    'organizationUnitId',v_endpoint.organization_unit_id,
    'endpointKind',v_endpoint.endpoint_kind,
    'address',v_endpoint.address,
    'addressNormalized',v_endpoint.address_normalized,
    'endpointState',v_endpoint.endpoint_state,
    'created',v_created
  );
end;
$function$;

create or replace function atlas.organization_connected_source_authorized_self_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select auth.uid() is not null and (
    atlas.is_organization_owner(p_organization_id)
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id=p_organization_id
        and actor.human_user_id=auth.uid()
        and actor.actor_kind='setup_actor'
        and actor.active
    )
  )
$function$;

comment on function atlas.organization_connected_source_authorized_self_v1(uuid) is
'Organization Connected Source management authority: present-effective owner Membership OR active setup_actor. Setup authority remains independent of Membership.';

create or replace function atlas.connected_sources_self_api_v1()
returns table(
  source_id uuid,
  custody_kind text,
  custodian_organization_id uuid,
  custodian_organization_unit_id uuid,
  provider_key text,
  provider_account_key text,
  display_label text,
  account_hint text,
  authorization_state text,
  granted_scopes text[],
  capabilities jsonb,
  last_sync_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select
    source.id,
    case when source.custodian_user_id is not null
      then 'human' else 'organization' end,
    source.custodian_organization_id,
    source.custodian_organization_unit_id,
    source.provider_key,
    source.provider_account_key,
    source.display_label,
    source.account_hint,
    source.authorization_state,
    source.granted_scopes,
    source.capabilities,
    source.last_sync_at,
    source.created_at,
    source.updated_at
  from atlas.connected_sources source
  where auth.uid() is not null and (
    source.custodian_user_id=auth.uid()
    or exists(
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id=source.custodian_organization_id
        and membership.user_id=auth.uid()
        and atlas.organization_membership_present_effective_at_v1(
          membership.id,membership.organization_id,now()
        )
    )
    or exists(
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id=source.custodian_organization_id
        and actor.human_user_id=auth.uid()
        and actor.active
    )
  )
  order by source.created_at,source.id
$function$;

comment on function atlas.connected_sources_self_api_v1() is
'Connected Source read projection. Human custodians retain self access. Organization source visibility requires present-effective Membership or active setup_actor; read visibility remains distinct from management authority.';

create or replace function atlas.organization_employee_appointments_by_auth_user_v1(
  p_auth_user_id uuid,
  p_organization_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  with employee as (
    select
      c.id as credential_id,
      s.id as employee_seat_id,
      s.organization_id,
      s.organization_membership_id,
      s.identity_subject_id
    from atlas.organization_member_credentials c
    join atlas.organization_employee_seats s
      on s.id=c.employee_seat_id
    join atlas.organization_memberships m
      on m.id=s.organization_membership_id
     and m.organization_id=s.organization_id
     and m.identity_subject_id=s.identity_subject_id
    where c.auth_user_id=p_auth_user_id
      and c.status='active'
      and s.status='active'
      and s.billing_state in ('active','waived')
      and atlas.organization_membership_present_effective_at_v1(
        m.id,m.organization_id,now()
      )
      and (
        p_organization_id is null
        or s.organization_id=p_organization_id
      )
  ), appts as (
    select
      e.*,
      a.id as appointment_id,
      a.appointment_kind,
      p.id as position_id,
      p.stable_key as position_key,
      p.display_title,
      p.position_kind,
      p.organization_unit_id,
      u.stable_key as organization_unit_key,
      u.name as organization_unit_name,
      u.unit_kind as organization_unit_kind
    from employee e
    join atlas.organization_position_appointments a
      on a.organization_id=e.organization_id
     and a.organization_membership_id=e.organization_membership_id
     and a.identity_subject_id=e.identity_subject_id
     and a.status='active'
     and a.begins_at<=now()
     and (a.ends_at is null or a.ends_at>now())
    join atlas.organization_positions p
      on p.id=a.position_id
     and p.organization_id=e.organization_id
     and p.status='active'
    join atlas.organization_units u
      on u.id=p.organization_unit_id
     and u.organization_id=e.organization_id
     and u.status='active'
  )
  select jsonb_build_object(
    'ok',true,
    'contractVersion','organization_employee_appointments_by_auth_user_v1',
    'items',coalesce(
      jsonb_agg(
        jsonb_build_object(
          'credentialId',credential_id,
          'employeeSeatId',employee_seat_id,
          'organizationId',organization_id,
          'organizationMembershipId',organization_membership_id,
          'identitySubjectId',identity_subject_id,
          'appointmentId',appointment_id,
          'appointmentKind',appointment_kind,
          'positionId',position_id,
          'positionKey',position_key,
          'displayTitle',display_title,
          'positionKind',position_kind,
          'organizationUnitId',organization_unit_id,
          'organizationUnitKey',organization_unit_key,
          'organizationUnitName',organization_unit_name,
          'organizationUnitKind',organization_unit_kind
        )
        order by appointment_kind,position_key
      ),
      '[]'::jsonb
    )
  )
  from appts
$function$;

create or replace function atlas.can_schedule_company_work_v1(
  p_work_item_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select exists(
    select 1
    from atlas.work_items wi
    where wi.id=p_work_item_id
      and (
        atlas.is_organization_owner(wi.organization_id)
        or (
          exists(
            select 1
            from atlas.organization_memberships om
            where om.organization_id=wi.organization_id
              and om.user_id=auth.uid()
              and atlas.organization_membership_present_effective_at_v1(
                om.id,om.organization_id,now()
              )
          )
          and exists(
            select 1
            from atlas.work_execution_adapters a
            join atlas.planned_work_occurrences pwo
              on pwo.id=a.planned_occurrence_id
            join atlas.farms f
              on f.id=pwo.farm_id
            join atlas.farm_memberships fm
              on fm.farm_id=f.id
            where a.work_item_id=wi.id
              and a.organization_id=wi.organization_id
              and a.state='active'
              and f.organization_id=wi.organization_id
              and fm.user_id=auth.uid()
              and fm.active
              and fm.role in ('owner','manager')
          )
        )
      )
  )
$function$;

comment on function atlas.can_schedule_company_work_v1(uuid) is
'Present Company Work scheduling authorization. Organization owner authority and the farm-manager compatibility path both require present-effective Organization Membership; Farm Membership does not resurrect a future or expired institutional relationship.';

create or replace function atlas.can_adjudicate_company_work_v1(
  p_work_item_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select exists(
    select 1
    from atlas.work_items wi
    where wi.id=p_work_item_id
      and (
        atlas.is_organization_owner(wi.organization_id)
        or exists(
          select 1
          from atlas.organization_memberships om
          join atlas.farm_memberships fm
            on fm.user_id=om.user_id
           and fm.active
           and fm.role in ('owner','manager')
          join atlas.farms f
            on f.id=fm.farm_id
           and f.organization_id=wi.organization_id
          where om.organization_id=wi.organization_id
            and om.user_id=auth.uid()
            and atlas.organization_membership_present_effective_at_v1(
              om.id,om.organization_id,now()
            )
            and (
              (
                wi.organization_unit_id is not null
                and f.organization_unit_id=wi.organization_unit_id
              )
              or exists(
                select 1
                from atlas.work_execution_adapters a
                join atlas.tasks t
                  on t.id=a.task_id
                where a.work_item_id=wi.id
                  and a.organization_id=wi.organization_id
                  and t.farm_id=f.id
              )
              or exists(
                select 1
                from atlas.work_execution_adapters a
                join atlas.planned_work_occurrences pwo
                  on pwo.id=a.planned_occurrence_id
                where a.work_item_id=wi.id
                  and a.organization_id=wi.organization_id
                  and pwo.farm_id=f.id
              )
              or exists(
                select 1
                from atlas.worker_week_projection_sources src
                join atlas.worker_week_projection projection
                  on projection.id=src.projection_id
                where src.work_item_id=wi.id
                  and projection.farm_id=f.id
              )
            )
        )
      )
  )
$function$;

comment on function atlas.can_adjudicate_company_work_v1(uuid) is
'Present Company Work adjudication authorization. The farm-owner/manager compatibility path requires present-effective Organization Membership in addition to Farm Membership.';

create or replace function atlas.company_work_planning_actor_membership_v1(
  p_work_item_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select om.id
  from atlas.work_items wi
  join atlas.organization_memberships om
    on om.organization_id=wi.organization_id
   and om.user_id=auth.uid()
  where wi.id=p_work_item_id
    and atlas.organization_membership_present_effective_at_v1(
      om.id,om.organization_id,now()
    )
    and atlas.can_schedule_company_work_v1(wi.id)
  order by
    case when om.role='owner' then 0 else 1 end,
    om.created_at,
    om.id
  limit 1
$function$;

create or replace function atlas.current_session_context_physical_compatibility_internal_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_claims jsonb:=auth.jwt();
  v_session_id uuid;
  v_email text;
  v_user_metadata jsonb:='{}'::jsonb;
  v_profile jsonb;
  v_memberships jsonb:='[]'::jsonb;
  v_organization_memberships jsonb:='[]'::jsonb;
begin
  if v_uid is null then
    return null;
  end if;

  begin
    v_session_id:=nullif(v_claims->>'session_id','')::uuid;
  exception when others then
    return null;
  end;

  if v_session_id is null then
    return null;
  end if;

  if not exists(
    select 1
    from auth.sessions session
    where session.id=v_session_id
      and session.user_id=v_uid
      and (session.not_after is null or session.not_after>now())
  ) then
    return null;
  end if;

  select
    user_row.email,
    coalesce(user_row.raw_user_meta_data,'{}'::jsonb)
  into v_email,v_user_metadata
  from auth.users user_row
  where user_row.id=v_uid
    and user_row.deleted_at is null
    and (
      user_row.banned_until is null
      or user_row.banned_until<=now()
    );

  if not found then
    return null;
  end if;

  select jsonb_build_object(
    'user_id',profile.user_id,
    'display_name',profile.display_name,
    'default_farm_id',profile.default_farm_id,
    'default_organization_id',profile.default_organization_id,
    'onboarding_state',profile.onboarding_state,
    'onboarding_started_at',profile.onboarding_started_at,
    'onboarding_completed_at',profile.onboarding_completed_at,
    'active',profile.active
  )
  into v_profile
  from atlas.user_profiles profile
  where profile.user_id=v_uid;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',membership.id,
        'farm_id',membership.farm_id,
        'role',membership.role,
        'worker_key',membership.worker_key,
        'active',membership.active,
        'permissions',coalesce(membership.permissions,'{}'::jsonb),
        'farm',jsonb_build_object(
          'id',farm.id,
          'stable_key',farm.stable_key,
          'name',farm.name,
          'status',farm.status
        )
      )
      order by membership.id
    ),
    '[]'::jsonb
  )
  into v_memberships
  from atlas.farm_memberships membership
  join atlas.farms farm
    on farm.id=membership.farm_id
  where membership.user_id=v_uid
    and membership.active=true;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',membership.id,
        'organization_id',membership.organization_id,
        'role',membership.role,
        'active',membership.active,
        'permissions',coalesce(membership.permissions,'{}'::jsonb),
        'organization',jsonb_build_object(
          'id',organization.id,
          'stable_key',organization.stable_key,
          'name',organization.name,
          'status',organization.status
        )
      )
      order by membership.id
    ),
    '[]'::jsonb
  )
  into v_organization_memberships
  from atlas.organization_memberships membership
  join atlas.organizations organization
    on organization.id=membership.organization_id
  where membership.user_id=v_uid
    and atlas.organization_membership_present_effective_at_v1(
      membership.id,membership.organization_id,now()
    );

  return jsonb_build_object(
    'user',jsonb_build_object(
      'id',v_uid,
      'email',v_email,
      'user_metadata',v_user_metadata
    ),
    'profile',v_profile,
    'memberships',v_memberships,
    'organizationMemberships',v_organization_memberships
  );
end;
$function$;

create or replace function atlas.organization_access_physical_compatibility_internal_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_person_id uuid;
  v_items jsonb;
begin
  if v_uid is null then
    return jsonb_build_object(
      'ok',true,'authenticated',false,'items','[]'::jsonb
    );
  end if;

  v_person_id:=atlas.current_person_id_v1();

  if v_person_id is null then
    return jsonb_build_object(
      'ok',true,
      'authenticated',true,
      'contractVersion','organization_access_self_v1',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'organizationId',o.id,
        'organizationName',o.name,
        'organizationMembershipId',m.id,
        'identitySubjectId',m.identity_subject_id,
        'employeeSeatId',s.id,
        'accessClass',s.seat_class,
        'seatStatus',s.status,
        'billingState',s.billing_state,
        'membershipRole',m.role
      )
      order by o.name,o.id
    ),
    '[]'::jsonb
  )
  into v_items
  from atlas.organization_member_credentials c
  join atlas.organization_memberships m
    on m.id=c.organization_membership_id
   and m.organization_id=c.organization_id
  join atlas.organization_employee_seats s
    on s.id=c.employee_seat_id
   and s.organization_membership_id=m.id
   and s.organization_id=m.organization_id
  join atlas.organizations o
    on o.id=m.organization_id
  where c.credential_kind='auth_user'
    and c.auth_user_id=v_uid
    and c.status='active'
    and (c.expires_at is null or c.expires_at>now())
    and m.person_id=v_person_id
    and atlas.organization_membership_present_effective_at_v1(
      m.id,m.organization_id,now()
    )
    and s.status='active'
    and o.status='active';

  return jsonb_build_object(
    'ok',true,
    'authenticated',true,
    'contractVersion','organization_access_self_v1',
    'items',v_items
  );
end;
$function$;

do $verification$
begin
  if has_function_privilege(
       'authenticated',
       'atlas.organization_membership_present_effective_at_v1(uuid,uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Exact Membership Effective-Time predicate must remain internal.';
  end if;

  if pg_get_functiondef(
       'atlas.current_effective_organization_membership_v1(uuid)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%'
     or pg_get_functiondef(
       'atlas.is_organization_member(uuid)'::regprocedure
     ) not ilike '%current_effective_organization_membership_v1%'
     or pg_get_functiondef(
       'atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%'
     or pg_get_functiondef(
       'atlas.can_schedule_company_work_v1(uuid)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%'
     or pg_get_functiondef(
       'atlas.can_adjudicate_company_work_v1(uuid)'::regprocedure
     ) not ilike '%organization_membership_present_effective_at_v1%' then
    raise exception 'Effective-Time root seams did not bind to canonical present Membership law.';
  end if;

  if pg_get_functiondef(
       'atlas.is_effective_organization_owner_v1(uuid)'::regprocedure
     ) not ilike '%principal_ledger_authorities%'
     or pg_get_functiondef(
       'atlas.is_effective_organization_owner_v1(uuid)'::regprocedure
     ) not ilike '%is_organization_owner%' then
    raise exception 'Organization owner cutover collapsed independent Principal Ledger root governance.';
  end if;
end;
$verification$;

commit;
