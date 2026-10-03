create or replace function atlas.reality_entity_for_legacy_organization_internal_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=''
as $function$
  select lb.new_id
  from compatibility.legacy_bindings lb
  join reality.entities e
    on e.id=lb.new_id
   and e.identity_state='canonical'
  where lb.legacy_schema='atlas'
    and lb.legacy_table='organizations'
    and lb.legacy_key=p_organization_id::text
    and lb.disposition='maps_to'
    and lb.new_schema='reality'
    and lb.new_table='entities'
  order by lb.created_at,lb.id
  limit 1;
$function$;

revoke all on function atlas.reality_entity_for_legacy_organization_internal_v1(uuid)
  from public,anon,authenticated;

create or replace function atlas.communication_endpoint_legacy_carrier_capability_self_v1(
  p_communication_endpoint_id uuid,
  p_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_membership_id uuid;
  v_capability text:=lower(btrim(coalesce(p_capability,'')));
begin
  if auth.uid() is null or p_communication_endpoint_id is null or v_capability='' then
    return false;
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.id=p_communication_endpoint_id
    and ep.endpoint_state='active'
    and ep.organization_id is not null;

  if v_endpoint.id is null then return false; end if;

  select m.id into v_membership_id
  from atlas.organization_memberships m
  where m.organization_id=v_endpoint.organization_id
    and m.user_id=auth.uid()
    and m.active
    and atlas.organization_membership_present_effective_at_v1(
      m.id,m.organization_id,now()
    )
  order by m.created_at,m.id
  limit 1;

  if v_membership_id is null then return false; end if;

  return exists(
    select 1
    from atlas.communication_endpoint_member_grants g
    where g.communication_endpoint_id=v_endpoint.id
      and g.membership_id=v_membership_id
      and g.capability=v_capability
      and g.grant_state='active'
  );
end
$function$;

revoke all on function atlas.communication_endpoint_legacy_carrier_capability_self_v1(uuid,text)
  from public,anon,authenticated;

create or replace function atlas.institutional_correspondence_endpoint_responsibility_self_v1(
  p_communication_endpoint_id uuid,
  p_operation_key text
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_entity_id uuid;
begin
  if auth.uid() is null then return null; end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then return null; end if;

  select * into v_endpoint
  from atlas.communication_endpoints ep
  where ep.id=p_communication_endpoint_id
    and ep.endpoint_state='active'
    and ep.organization_id is not null;

  if v_endpoint.id is null then return null; end if;

  v_entity_id:=atlas.reality_entity_for_legacy_organization_internal_v1(
    v_endpoint.organization_id
  );
  if v_entity_id is null then return null; end if;

  return reality.resolve_responsibility_relation_v1(
    v_person_id,
    'institutional_correspondence_administration',
    p_operation_key,
    'entity',
    v_entity_id,
    null,
    jsonb_build_object(
      'communicationEndpointIds',
      jsonb_build_array(v_endpoint.id::text)
    )
  );
end
$function$;

revoke all on function atlas.institutional_correspondence_endpoint_responsibility_self_v1(uuid,text)
  from public,anon,authenticated;

create or replace function atlas.correspondence_identity_manage_authorized_self_v1(
  p_correspondence_identity_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_identity atlas.correspondence_identities%rowtype;
  v_person_id uuid;
  v_compat_principal_id uuid;
begin
  if auth.uid() is null or p_correspondence_identity_id is null then return false; end if;

  select * into v_identity
  from atlas.correspondence_identities
  where id=p_correspondence_identity_id
    and identity_state='active';

  if v_identity.id is null then return false; end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then return false; end if;

  if v_identity.principal_id is not null then
    v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
    return v_compat_principal_id is not null
       and v_compat_principal_id=v_identity.principal_id;
  end if;

  return exists(
    select 1
    from atlas.correspondence_identity_endpoint_bindings b
    join atlas.communication_endpoints ep
      on ep.id=b.communication_endpoint_id
     and ep.endpoint_state='active'
     and ep.organization_id=v_identity.organization_id
     and (
       v_identity.organization_unit_id is null
       or ep.organization_unit_id=v_identity.organization_unit_id
     )
    where b.correspondence_identity_id=v_identity.id
      and b.binding_state='active'
      and atlas.institutional_correspondence_endpoint_responsibility_self_v1(
        ep.id,'correspondence_identity.admin'
      ) is not null
      and atlas.communication_endpoint_legacy_carrier_capability_self_v1(ep.id,'admin')
  );
end
$function$;

create or replace function atlas.correspondence_identity_read_authorized_self_v1(
  p_correspondence_identity_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_identity atlas.correspondence_identities%rowtype;
  v_person_id uuid;
  v_compat_principal_id uuid;
begin
  if auth.uid() is null or p_correspondence_identity_id is null then return false; end if;

  select * into v_identity
  from atlas.correspondence_identities
  where id=p_correspondence_identity_id
    and identity_state='active';

  if v_identity.id is null then return false; end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then return false; end if;

  if v_identity.principal_id is not null then
    v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
    return v_compat_principal_id is not null
       and v_compat_principal_id=v_identity.principal_id;
  end if;

  return exists(
    select 1
    from atlas.correspondence_identity_endpoint_bindings b
    join atlas.communication_endpoints ep
      on ep.id=b.communication_endpoint_id
     and ep.endpoint_state='active'
     and ep.organization_id=v_identity.organization_id
     and (
       v_identity.organization_unit_id is null
       or ep.organization_unit_id=v_identity.organization_unit_id
     )
    where b.correspondence_identity_id=v_identity.id
      and b.binding_state='active'
      and atlas.institutional_correspondence_endpoint_responsibility_self_v1(
        ep.id,'correspondence_identity.read'
      ) is not null
      and atlas.communication_endpoint_legacy_carrier_capability_self_v1(ep.id,'view')
  );
end
$function$;

create or replace function atlas.create_correspondence_identity_for_endpoint_self_api_v1(
  p_communication_endpoint_id uuid,
  p_display_name text,
  p_icon_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_endpoint atlas.communication_endpoints%rowtype;
  v_identity atlas.correspondence_identities%rowtype;
  v_icon text:=nullif(lower(btrim(coalesce(p_icon_key,''))),'');
  v_name text:=btrim(coalesce(p_display_name,''));
  v_person_id uuid;
  v_compat_principal_id uuid;
  v_relation_id uuid;
  v_authority_metadata jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_communication_endpoint_id is null then raise exception 'Communication endpoint is required.' using errcode='22023'; end if;
  if v_name='' then raise exception 'Correspondence identity name is required.' using errcode='22023'; end if;

  if v_icon is not null and v_icon<>all(array[
    'briefcase','building','home','flower','leaf','heart','book','megaphone',
    'community','star','person','spark'
  ]) then
    raise exception 'Unsupported correspondence icon.' using errcode='22023';
  end if;

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and endpoint_state='active';

  if v_endpoint.id is null then raise exception 'Communication endpoint not found.' using errcode='23503'; end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  if v_endpoint.principal_id is not null then
    v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
    if v_compat_principal_id is null or v_compat_principal_id<>v_endpoint.principal_id then
      raise exception 'Personal correspondence identity administration required.' using errcode='42501';
    end if;

    v_authority_metadata:=jsonb_build_object(
      'authorityMode','personal_atlas',
      'personEntityId',v_person_id,
      'legacyPrincipalStorageOnly',true
    );
  else
    v_relation_id:=atlas.institutional_correspondence_endpoint_responsibility_self_v1(
      v_endpoint.id,'correspondence_identity.admin'
    );

    if v_relation_id is null then
      raise exception 'Institutional correspondence administration responsibility required.' using errcode='42501';
    end if;

    if not atlas.communication_endpoint_legacy_carrier_capability_self_v1(v_endpoint.id,'admin') then
      raise exception 'Legacy endpoint administration carrier unavailable.' using errcode='42501';
    end if;

    v_authority_metadata:=jsonb_build_object(
      'authorityMode','reality_responsibility_relation',
      'responsibilityRelationId',v_relation_id,
      'personEntityId',v_person_id,
      'institutionEntityId',
        atlas.reality_entity_for_legacy_organization_internal_v1(v_endpoint.organization_id),
      'legacyEndpointCarrierConstraint',true
    );
  end if;

  if exists(
    select 1
    from atlas.correspondence_identity_endpoint_bindings b
    where b.communication_endpoint_id=v_endpoint.id
      and b.binding_state='active'
  ) then
    raise exception 'Communication endpoint already has a correspondence identity.'
      using errcode='23505';
  end if;

  insert into atlas.correspondence_identities(
    principal_id,organization_id,organization_unit_id,display_name,
    mark_kind,icon_key,created_by_user_id,metadata
  ) values(
    v_endpoint.principal_id,v_endpoint.organization_id,v_endpoint.organization_unit_id,
    v_name,case when v_icon is null then 'monogram' else 'icon' end,
    v_icon,auth.uid(),
    jsonb_build_object('source','atlas_correspondence_identity_v2')||v_authority_metadata
  )
  returning * into v_identity;

  insert into atlas.correspondence_identity_endpoint_bindings(
    correspondence_identity_id,communication_endpoint_id,created_by_user_id,metadata
  ) values(
    v_identity.id,v_endpoint.id,auth.uid(),
    jsonb_build_object('source','create_with_endpoint_v2')||v_authority_metadata
  );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','correspondence_identity_authoring_v2',
    'correspondenceIdentityId',v_identity.id,
    'displayName',v_identity.display_name,
    'markKind',v_identity.mark_kind,
    'iconKey',v_identity.icon_key,
    'communicationEndpointId',v_endpoint.id,
    'authority',v_authority_metadata
  );
end
$function$;

create or replace function atlas.bind_correspondence_identity_endpoint_self_api_v1(
  p_correspondence_identity_id uuid,
  p_communication_endpoint_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_identity atlas.correspondence_identities%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_existing atlas.correspondence_identity_endpoint_bindings%rowtype;
  v_person_id uuid;
  v_compat_principal_id uuid;
  v_relation_id uuid;
  v_authority_metadata jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  if not atlas.correspondence_identity_manage_authorized_self_v1(p_correspondence_identity_id) then
    raise exception 'Correspondence identity administration required.' using errcode='42501';
  end if;

  select * into v_identity
  from atlas.correspondence_identities
  where id=p_correspondence_identity_id
    and identity_state='active';

  select * into v_endpoint
  from atlas.communication_endpoints
  where id=p_communication_endpoint_id
    and endpoint_state='active';

  if v_identity.id is null or v_endpoint.id is null then
    raise exception 'Correspondence identity or endpoint not found.' using errcode='23503';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then raise exception 'Canonical Reality Person required.' using errcode='42501'; end if;

  if v_identity.principal_id is not null then
    if v_endpoint.principal_id is distinct from v_identity.principal_id then
      raise exception 'Endpoint custody does not match correspondence identity.' using errcode='23514';
    end if;

    v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
    if v_compat_principal_id is null or v_compat_principal_id<>v_endpoint.principal_id then
      raise exception 'Personal correspondence identity administration required.' using errcode='42501';
    end if;

    v_authority_metadata:=jsonb_build_object(
      'authorityMode','personal_atlas',
      'personEntityId',v_person_id,
      'legacyPrincipalStorageOnly',true
    );
  else
    if v_endpoint.organization_id is distinct from v_identity.organization_id
       or (
         v_identity.organization_unit_id is not null
         and v_endpoint.organization_unit_id is distinct from v_identity.organization_unit_id
       ) then
      raise exception 'Endpoint custody does not match correspondence identity.' using errcode='23514';
    end if;

    v_relation_id:=atlas.institutional_correspondence_endpoint_responsibility_self_v1(
      v_endpoint.id,'correspondence_identity.admin'
    );

    if v_relation_id is null then
      raise exception 'Institutional correspondence administration responsibility required.' using errcode='42501';
    end if;

    if not atlas.communication_endpoint_legacy_carrier_capability_self_v1(v_endpoint.id,'admin') then
      raise exception 'Legacy endpoint administration carrier unavailable.' using errcode='42501';
    end if;

    v_authority_metadata:=jsonb_build_object(
      'authorityMode','reality_responsibility_relation',
      'responsibilityRelationId',v_relation_id,
      'personEntityId',v_person_id,
      'institutionEntityId',
        atlas.reality_entity_for_legacy_organization_internal_v1(v_endpoint.organization_id),
      'legacyEndpointCarrierConstraint',true
    );
  end if;

  select * into v_existing
  from atlas.correspondence_identity_endpoint_bindings b
  where b.communication_endpoint_id=v_endpoint.id
    and b.binding_state='active'
  limit 1;

  if v_existing.id is not null then
    if v_existing.correspondence_identity_id=v_identity.id then
      return jsonb_build_object(
        'ok',true,
        'alreadyBound',true,
        'correspondenceIdentityId',v_identity.id,
        'communicationEndpointId',v_endpoint.id,
        'authority',v_authority_metadata
      );
    end if;
    raise exception 'Communication endpoint already has a different correspondence identity.'
      using errcode='23505';
  end if;

  insert into atlas.correspondence_identity_endpoint_bindings(
    correspondence_identity_id,communication_endpoint_id,created_by_user_id,metadata
  ) values(
    v_identity.id,v_endpoint.id,auth.uid(),
    jsonb_build_object('source','bind_endpoint_v2')||v_authority_metadata
  );

  return jsonb_build_object(
    'ok',true,
    'alreadyBound',false,
    'correspondenceIdentityId',v_identity.id,
    'communicationEndpointId',v_endpoint.id,
    'authority',v_authority_metadata
  );
end
$function$;

with lex as (
  select id from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical'
),
elm as (
  select id from reality.entities
  where stable_key='elm-farm'
    and identity_state='canonical'
)
insert into reality.responsibility_relations(
  carrier_person_entity_id,responsibility_key,title,relation_state,
  jurisdiction_kind,jurisdiction_entity_id,permitted_operations,scope,
  establishment_kind,establishment_basis
)
select
  lex.id,
  'institutional_correspondence_administration',
  'Administer Elm Farm correspondence identity',
  'active',
  'entity',
  elm.id,
  array['correspondence_identity.admin','correspondence_identity.read']::text[],
  jsonb_build_object(
    'communicationEndpointIds',
    jsonb_build_array('7617a7b1-8713-4520-923f-51a15c6b2d7f')
  ),
  'legacy_adjudicated_migration',
  jsonb_build_object(
    'basis','Existing Elm correspondence administration was explicitly adjudicated into a bounded Reality responsibility.',
    'legacyOrganizationId','fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    'legacyCommunicationEndpointId','7617a7b1-8713-4520-923f-51a15c6b2d7f',
    'legacyCorrespondenceIdentityId','336c34c7-fdba-4767-b539-24d698605ed0',
    'doesNotPreserve',jsonb_build_array(
      'organization owner role','Organization Membership as authority','Principal as identity'
    ),
    'legacyEndpointGrantIsCarrierConstraintOnly',true
  )
from lex,elm
on conflict do nothing;

update atlas.authenticated_rpc_registry
set evidence=evidence||jsonb_build_object(
      'authoritySource','reality.responsibility_relations',
      'responsibilityKey','institutional_correspondence_administration',
      'personalEndpointAuthority','Reality Person + Personal Atlas',
      'legacyEndpointGrantRole','compatibility carrier constraint only',
      'organizationMembershipIsAuthority',false,
      'ownerRoleIsAuthority',false
    ),
    reviewed_at=now()
where signature like 'atlas.%correspondence_identity%';

comment on function atlas.communication_endpoint_legacy_carrier_capability_self_v1(uuid,text) is
  'Internal compatibility carrier check for an existing explicit endpoint grant. It does not establish authority and intentionally ignores generic Organization role.';
comment on function atlas.institutional_correspondence_endpoint_responsibility_self_v1(uuid,text) is
  'Resolve exact institutional correspondence authority through Reality responsibility for the signed-in Person and endpoint-scoped institution jurisdiction.';
comment on function atlas.correspondence_identity_manage_authorized_self_v1(uuid) is
  'Correspondence identity administration is Personal Atlas authority for personal endpoints or explicit Reality responsibility for institutional endpoints. Legacy endpoint grants are carrier constraints only.';
comment on function atlas.correspondence_identity_read_authorized_self_v1(uuid) is
  'Correspondence identity read authority is Personal Atlas authority for personal endpoints or explicit Reality responsibility for institutional endpoints.';

do $validation$
begin
  if pg_get_functiondef(
       'atlas.correspondence_identity_manage_authorized_self_v1(uuid)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.correspondence_identity_manage_authorized_self_v1(uuid)'::regprocedure
     ) ilike '%role=''owner''%' then
    raise exception 'Correspondence manage helper retained legacy authority semantics.';
  end if;

  if pg_get_functiondef(
       'atlas.correspondence_identity_read_authorized_self_v1(uuid)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.create_correspondence_identity_for_endpoint_self_api_v1(uuid,text,text)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.bind_correspondence_identity_endpoint_self_api_v1(uuid,uuid)'::regprocedure
     ) ilike '%organization_memberships%' then
    raise exception 'Correspondence API retained Organization Membership as authority.';
  end if;
end
$validation$;
