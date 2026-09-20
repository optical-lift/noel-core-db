begin;

do $precondition$
begin
  if exists(select 1 from atlas.communication_endpoint_member_grants) then
    raise exception 'Endpoint knowledge-jurisdiction cutover expected zero historical grant rows. Audit existing grants instead of inventing grant origin.'
      using errcode='55000';
  end if;
end;
$precondition$;

alter table atlas.communication_endpoint_member_grants
  add column grant_basis_kind text not null;

alter table atlas.communication_endpoint_member_grants
  add constraint communication_endpoint_member_grants_basis_kind_check
  check (
    grant_basis_kind in (
      'organization_owner_compatibility_cutover',
      'endpoint_creator_initial_grant',
      'explicit_owner_grant'
    )
  );

comment on column atlas.communication_endpoint_member_grants.grant_basis_kind is
'Durable origin/lifecycle basis for one exact Communication Endpoint capability. Organization ownership is governance authority, not implicit Endpoint knowledge.';

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
    if not v_member.active then
      raise exception 'Endpoint authority requires an active Organization Membership.'
        using errcode='23514';
    end if;

    if v_member.eligibility_begins_on is not null
       or v_member.eligibility_ends_on is not null then
      raise exception 'Bounded Organization Membership cannot receive Endpoint authority until institutional calendar context is governed.'
        using errcode='0A000';
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
      if not v_granter.active or v_granter.role<>'owner' then
        raise exception 'Endpoint grant actor must be an active Organization owner.'
          using errcode='23514';
      end if;
      if v_granter.eligibility_begins_on is not null
         or v_granter.eligibility_ends_on is not null then
        raise exception 'Bounded Organization owner cannot govern Endpoint grants until institutional calendar context is governed.'
          using errcode='0A000';
      end if;
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_communication_endpoint_member_grant_v2()
from public,anon,authenticated,service_role;

drop trigger if exists communication_endpoint_member_grant_guard_v2
  on atlas.communication_endpoint_member_grants;

create trigger communication_endpoint_member_grant_guard_v2
before insert or update
on atlas.communication_endpoint_member_grants
for each row
execute function atlas.guard_communication_endpoint_member_grant_v2();

create or replace function atlas.revoke_owner_compatibility_endpoint_grants_on_membership_change_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.active is false
     or new.role<>'owner'
     or new.eligibility_begins_on is not null
     or new.eligibility_ends_on is not null then
    update atlas.communication_endpoint_member_grants g
    set grant_state='revoked',
        revoked_at=coalesce(g.revoked_at,now()),
        metadata=coalesce(g.metadata,'{}'::jsonb)
          ||jsonb_build_object(
            'revocationReason','organization_owner_compatibility_continuity_ended',
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

revoke all on function atlas.revoke_owner_compatibility_endpoint_grants_on_membership_change_v1()
from public,anon,authenticated,service_role;

drop trigger if exists organization_membership_owner_endpoint_compatibility_revoke_v1
  on atlas.organization_memberships;

create trigger organization_membership_owner_endpoint_compatibility_revoke_v1
after update of active,role,eligibility_begins_on,eligibility_ends_on
on atlas.organization_memberships
for each row
execute function atlas.revoke_owner_compatibility_endpoint_grants_on_membership_change_v1();

insert into atlas.communication_endpoint_member_grants(
  communication_endpoint_id,
  membership_id,
  capability,
  grant_state,
  granted_by_membership_id,
  grant_basis_kind,
  metadata
)
select
  ep.id,
  om.id,
  caps.capability,
  'active',
  null,
  'organization_owner_compatibility_cutover',
  jsonb_build_object(
    'source','atlas_organization_endpoint_knowledge_jurisdiction_v1',
    'migrationVersion','20260920131249',
    'compatibilityTruth','Materializes pre-cutover Organization-owner Endpoint authority without retaining owner as a permanent capability wildcard.'
  )
from atlas.communication_endpoints ep
join atlas.organization_memberships om
  on om.organization_id=ep.organization_id
 and om.active
 and om.role='owner'
 and om.eligibility_begins_on is null
 and om.eligibility_ends_on is null
cross join (
  values ('view'::text),('send'),('claim'),('handoff'),('close'),('admin')
) as caps(capability)
where ep.organization_id is not null
  and ep.endpoint_state='active';

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
     and om.active
    join atlas.communication_endpoint_member_grants g
      on g.communication_endpoint_id=ep.id
     and g.membership_id=om.id
     and g.capability=lower(btrim(coalesce(p_capability,'')))
     and g.grant_state='active'
    where ep.id=p_endpoint_id
      and ep.endpoint_state='active'
      and ep.organization_id is not null
      and om.eligibility_begins_on is null
      and om.eligibility_ends_on is null
      and g.grant_basis_kind in (
        'organization_owner_compatibility_cutover',
        'endpoint_creator_initial_grant',
        'explicit_owner_grant'
      )
      and (
        g.grant_basis_kind<>'organization_owner_compatibility_cutover'
        or om.role='owner'
      )
  );
$function$;

comment on function atlas.communication_endpoint_membership_has_capability_v1(uuid,uuid,text) is
'Exact Endpoint capability resolver. Organization ownership is not a capability wildcard. Bounded Membership authority fails closed until institutional calendar context is governed.';

create or replace function atlas.communication_endpoint_authorized_self_v1(
  p_endpoint_id uuid,
  p_capability text
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select exists(
    select 1
    from atlas.communication_endpoints ep
    join atlas.organization_memberships om
      on om.organization_id=ep.organization_id
     and om.user_id=auth.uid()
    where ep.id=p_endpoint_id
      and atlas.communication_endpoint_membership_has_capability_v1(
        ep.id,om.id,p_capability
      )
  );
$function$;

comment on function atlas.communication_endpoint_authorized_self_v1(uuid,text) is
'Authenticated exact Endpoint capability check. Root Organization governance alone does not imply Endpoint knowledge or action authority.';

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
    raise exception 'Organization Communication Endpoint not found.' using errcode='P0002';
  end if;

  select * into v_actor
  from atlas.organization_memberships
  where organization_id=v_endpoint.organization_id
    and user_id=auth.uid()
    and active
    and role='owner'
  order by created_at,id
  limit 1;

  if v_actor.id is null then
    raise exception 'Organization owner governance authority required.' using errcode='42501';
  end if;

  if v_actor.eligibility_begins_on is not null
     or v_actor.eligibility_ends_on is not null then
    raise exception 'Bounded Organization owner cannot govern Endpoint grants until institutional calendar context is governed.'
      using errcode='0A000';
  end if;

  if v_cap not in ('view','send','claim','handoff','close','admin') then
    raise exception 'Unsupported communication endpoint capability.' using errcode='22023';
  end if;

  select * into v_target
  from atlas.organization_memberships
  where id=p_membership_id
    and organization_id=v_endpoint.organization_id
    and active;

  if v_target.id is null then
    raise exception 'Endpoint grant target must be an active Membership in the Endpoint Organization.'
      using errcode='23514';
  end if;

  if v_target.eligibility_begins_on is not null
     or v_target.eligibility_ends_on is not null then
    raise exception 'Bounded Organization Membership cannot receive Endpoint authority until institutional calendar context is governed.'
      using errcode='0A000';
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
              'revocationReason',coalesce(nullif(btrim(coalesce(p_reason,'')),''),'explicit_owner_revocation'),
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

comment on function atlas.set_communication_endpoint_member_capability_self_api_v1(uuid,uuid,text,boolean,text) is
'Root Organization governance command for exact Endpoint capability grants. Governing authority does not require the actor to hold the governed Endpoint capability.';

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
  where organization_id=p_organization_id
    and user_id=auth.uid()
    and active
    and role='owner'
  order by created_at,id
  limit 1;

  if v_member.id is null then
    raise exception 'Organization owner authority required.' using errcode='42501';
  end if;

  if v_member.eligibility_begins_on is not null
     or v_member.eligibility_ends_on is not null then
    raise exception 'Bounded Organization owner cannot govern Endpoint configuration until institutional calendar context is governed.'
      using errcode='0A000';
  end if;

  if p_organization_unit_id is not null
     and not exists(
       select 1
       from atlas.organization_units u
       where u.organization_id=p_organization_id
         and u.id=p_organization_unit_id
     ) then
    raise exception 'Organization unit is outside organization.' using errcode='23514';
  end if;

  if v_kind not in ('email','phone','sms','voice','web_form','social','atlas_native','other')
     or v_address='' then
    raise exception 'Valid endpoint kind and address are required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Endpoint metadata must be an object.' using errcode='22023';
  end if;

  v_norm:=atlas.normalize_communication_endpoint_address_v1(v_kind,v_address);

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
    set display_name=coalesce(nullif(btrim(p_display_name),''),display_name),
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

comment on function atlas.upsert_communication_endpoint_self_api_v1(uuid,uuid,text,text,text,jsonb) is
'Organization Endpoint configuration command. New Endpoint creation atomically grants the creating owner exact initial capabilities; updating an existing Endpoint never auto-grants authority.';

commit;
