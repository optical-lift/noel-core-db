-- Atlas Organization + Ledger Establishment v1.
-- Establishes a noncommercial Person/Principal-rooted institutional birth transaction
-- around the already-live Organization -> governing Ledger invariant.

BEGIN;

create or replace function atlas.establish_organization_ledger_for_principal_v1(
  p_principal_id uuid,
  p_person_id uuid,
  p_human_user_id uuid,
  p_name text,
  p_create_owner_membership boolean,
  p_begin_onboarding boolean,
  p_establishment_basis text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_credential_person_id uuid;
  v_name text := btrim(coalesce(p_name,''));
  v_basis text := btrim(coalesce(p_establishment_basis,''));
  v_organization_id uuid := gen_random_uuid();
  v_stable_base text;
  v_stable_key text;
  v_ledger_id uuid;
  v_ledger_stable_key text;
  v_ledger_kind text;
  v_ledger_status text;
  v_authority_id uuid;
  v_membership_id uuid;
  v_reconstruction_session_id uuid;
  v_onboarding_state text;
begin
  if p_principal_id is null or p_person_id is null then
    raise exception 'Principal and Person are required.' using errcode='22023';
  end if;

  if length(v_name) < 2 or length(v_name) > 160 then
    raise exception 'Organization name must be between 2 and 160 characters.' using errcode='22023';
  end if;

  if v_basis = '' then
    raise exception 'Establishment basis required.' using errcode='22023';
  end if;

  select p.*
  into v_principal
  from atlas.principals p
  where p.id = p_principal_id
    and p.status = 'active'
  for key share;

  if v_principal.id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if v_principal.person_id is null or v_principal.person_id <> p_person_id then
    raise exception 'Principal / Person identity contradiction.' using errcode='23514';
  end if;

  if p_human_user_id is not null then
    if not exists (
      select 1
      from auth.users u
      where u.id = p_human_user_id
        and u.deleted_at is null
        and (u.banned_until is null or u.banned_until <= now())
    ) then
      raise exception 'Authenticated human is unavailable.' using errcode='42501';
    end if;

    v_credential_person_id := atlas.ensure_person_for_auth_user_v1(p_human_user_id, null);
    if v_credential_person_id is null or v_credential_person_id <> p_person_id then
      raise exception 'Credential / Person identity contradiction.' using errcode='23514';
    end if;
  end if;

  if (p_create_owner_membership or p_begin_onboarding) and p_human_user_id is null then
    raise exception 'Credential evidence required for membership or onboarding.' using errcode='22023';
  end if;

  v_stable_base := btrim(regexp_replace(lower(v_name), '[^a-z0-9]+', '_', 'g'), '_');
  if v_stable_base = '' then
    v_stable_base := 'organization';
  end if;

  v_stable_key := v_stable_base;
  if exists (
    select 1
    from atlas.organizations o
    where o.stable_key = v_stable_key
  ) then
    v_stable_key := v_stable_base || '_' || substr(replace(v_organization_id::text,'-',''),1,8);
  end if;

  v_onboarding_state := case when p_begin_onboarding then 'connecting_sources' else 'new' end;

  insert into atlas.organizations (
    id,
    stable_key,
    name,
    status,
    metadata,
    onboarding_state,
    onboarding_started_at
  ) values (
    v_organization_id,
    v_stable_key,
    v_name,
    'active',
    jsonb_strip_nulls(jsonb_build_object(
      'establishment_mode','principal_institution_establishment',
      'established_by_principal_id',p_principal_id,
      'established_by_person_id',p_person_id,
      'establishment_basis',v_basis,
      'membership_claimed',p_create_owner_membership
    )),
    v_onboarding_state,
    case when p_begin_onboarding then now() else null end
  );

  v_ledger_id := atlas.primary_ledger_for_organization_v1(v_organization_id);
  if v_ledger_id is null then
    raise exception 'Organization governing Ledger was not established.' using errcode='23514';
  end if;

  select l.stable_key, l.ledger_kind, l.status
  into v_ledger_stable_key, v_ledger_kind, v_ledger_status
  from atlas.ledgers l
  where l.id = v_ledger_id
    and l.organization_id = v_organization_id;

  if v_ledger_stable_key is null then
    raise exception 'Organization governing Ledger identity is unavailable.' using errcode='23514';
  end if;

  insert into atlas.principal_ledger_authorities (
    principal_id,
    ledger_id,
    authority_kind,
    status,
    basis,
    metadata
  ) values (
    p_principal_id,
    v_ledger_id,
    'root_governing',
    'active',
    v_basis,
    jsonb_strip_nulls(jsonb_build_object(
      'source','establish_organization_ledger_for_principal_v1',
      'organizationId',v_organization_id,
      'personId',p_person_id,
      'credentialUserId',p_human_user_id
    ))
  )
  returning id into v_authority_id;

  if p_create_owner_membership then
    insert into atlas.organization_memberships (
      organization_id,
      user_id,
      person_id,
      role,
      active,
      permissions
    ) values (
      v_organization_id,
      p_human_user_id,
      p_person_id,
      'owner',
      true,
      '{}'::jsonb
    )
    returning id into v_membership_id;
  end if;

  if p_begin_onboarding then
    insert into atlas.organization_onboarding_actors (
      organization_id,
      human_user_id,
      actor_kind,
      active,
      metadata
    ) values (
      v_organization_id,
      p_human_user_id,
      'setup_actor',
      true,
      jsonb_build_object(
        'source','establish_organization_ledger_for_principal_v1',
        'principalId',p_principal_id,
        'personId',p_person_id
      )
    );

    insert into atlas.reconstruction_sessions (
      human_user_id,
      target_organization_id,
      status,
      clean_room,
      allow_existing_atlas_canon,
      purpose,
      metadata
    ) values (
      p_human_user_id,
      v_organization_id,
      'collecting',
      true,
      false,
      'organization_onboarding',
      jsonb_build_object(
        'organization_stable_key',v_stable_key,
        'principalId',p_principal_id,
        'personId',p_person_id,
        'source','establish_organization_ledger_for_principal_v1'
      )
    )
    returning id into v_reconstruction_session_id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'organization',jsonb_build_object(
      'id',v_organization_id,
      'stable_key',v_stable_key,
      'name',v_name,
      'status','active',
      'onboarding_state',v_onboarding_state
    ),
    'ledger',jsonb_build_object(
      'id',v_ledger_id,
      'stable_key',v_ledger_stable_key,
      'kind',v_ledger_kind,
      'status',v_ledger_status
    ),
    'authority',jsonb_build_object(
      'id',v_authority_id,
      'principal_id',p_principal_id,
      'kind','root_governing',
      'status','active',
      'basis',v_basis
    ),
    'membership',case when v_membership_id is null then null else jsonb_build_object(
      'id',v_membership_id,
      'role','owner',
      'active',true,
      'person_id',p_person_id,
      'user_id',p_human_user_id
    ) end,
    'reconstruction',case when v_reconstruction_session_id is null then null else jsonb_build_object(
      'id',v_reconstruction_session_id,
      'clean_room',true,
      'allow_existing_atlas_canon',false,
      'target_organization_id',v_organization_id
    ) end,
    'membershipCreated',v_membership_id is not null,
    'onboardingBegun',p_begin_onboarding,
    'principalId',p_principal_id,
    'personId',p_person_id
  ));
end;
$function$;

revoke all on function atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)
  from public, anon, authenticated;
grant execute on function atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)
  to service_role;

create or replace function atlas.establish_organization_ledger_self_api_v1(
  p_name text,
  p_create_owner_membership boolean default false,
  p_begin_onboarding boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_person_id uuid;
  v_principal_id uuid;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_person_id := atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Person required.' using errcode='42501';
  end if;

  v_principal_id := atlas.current_principal_id_v1();
  if v_principal_id is null then
    raise exception 'Principal required.' using errcode='42501';
  end if;

  return atlas.establish_organization_ledger_for_principal_v1(
    v_principal_id,
    v_person_id,
    v_uid,
    p_name,
    coalesce(p_create_owner_membership,false),
    coalesce(p_begin_onboarding,true),
    'principal_self_institution_establishment'
  );
end;
$function$;

revoke all on function atlas.establish_organization_ledger_self_api_v1(text,boolean,boolean)
  from public, anon;
grant execute on function atlas.establish_organization_ledger_self_api_v1(text,boolean,boolean)
  to authenticated;

-- Compatibility wrapper: authenticated clean-room Organization onboarding.
-- Signature and no-membership semantics remain stable; institutional authority is now canonical.
create or replace function atlas.begin_organization_onboarding_self_api_v1(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_result := atlas.establish_organization_ledger_self_api_v1(p_name,false,true);

  return jsonb_build_object(
    'organization',v_result->'organization',
    'ledger',v_result->'ledger',
    'authority',v_result->'authority',
    'setupActor',jsonb_build_object(
      'human_user_id',v_uid,
      'kind','setup_actor',
      'active',true,
      'membership_created',false
    ),
    'reconstruction',v_result->'reconstruction'
  );
end;
$function$;

revoke all on function atlas.begin_organization_onboarding_self_api_v1(text)
  from public, anon;
grant execute on function atlas.begin_organization_onboarding_self_api_v1(text)
  to authenticated, service_role;

-- Compatibility wrapper: historical service-only establishment surface.
-- It now delegates institutional birth and preserves owner-membership + reconstruction semantics.
create or replace function atlas.establish_organization_self_api_v1(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode='42501';
  end if;

  v_result := atlas.establish_organization_ledger_self_api_v1(p_name,true,true);

  return jsonb_build_object(
    'organization',v_result->'organization',
    'ledger',v_result->'ledger',
    'authority',v_result->'authority',
    'membership',v_result->'membership',
    'reconstruction',v_result->'reconstruction'
  );
end;
$function$;

revoke all on function atlas.establish_organization_self_api_v1(text)
  from public, anon, authenticated;
grant execute on function atlas.establish_organization_self_api_v1(text)
  to service_role;

COMMIT;
