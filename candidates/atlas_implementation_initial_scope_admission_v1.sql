begin;

-- Atlas Implementation Initial Scope Admission v1
--
-- Behavioral authority expansion; source-only until the compatible Workbench is
-- validated and deployed.
--
-- Two commands:
-- 1. admit an already-existing Organization + Ledger the verified setup sponsor
--    Principal already root-governs;
-- 2. establish one new Organization + Ledger under that sponsor Principal and
--    bind the case entitlement in the same transaction.
--
-- Neither command creates Organization Membership, employee seat, Position,
-- responsibility, Work, login, or implementation text authority.

create or replace function atlas.bind_initial_implementation_scope_internal_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_id uuid,
  p_ledger_id uuid,
  p_practitioner_participant_id uuid,
  p_setup_sponsor_participant_id uuid,
  p_setup_sponsor_principal_id uuid,
  p_establishment_basis jsonb,
  p_scope_origin text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_entitlement atlas.ledger_entitlements%rowtype;
  v_binding atlas.ledger_entitlement_bindings%rowtype;
begin
  if p_establishment_basis is null
     or jsonb_typeof(p_establishment_basis)<>'object'
     or nullif(btrim(coalesce(p_establishment_basis->>'kind','')),'') is null then
    raise exception 'Initial scope establishment basis with kind is required.'
      using errcode='22023';
  end if;

  if p_establishment_basis->>'kind' not in (
    'setup_sponsor_confirmation',
    'verified_purchase_scope',
    'adjudicated_existing_reality'
  ) then
    raise exception 'Unsupported Initial Scope establishment basis.'
      using errcode='22023';
  end if;

  if p_scope_origin not in ('existing_governed_scope','new_principal_scope') then
    raise exception 'Invalid initial scope origin.'
      using errcode='22023';
  end if;

  select le.*
  into v_entitlement
  from atlas.ledger_entitlements le
  where le.id=p_ledger_entitlement_id
    and le.implementation_case_id=p_implementation_case_id
    and le.price_class='baseline_first'
  for update;

  if v_entitlement.id is null then
    raise exception 'Ledger entitlement not found for this Implementation Case.'
      using errcode='23503';
  end if;

  select b.*
  into v_binding
  from atlas.ledger_entitlement_bindings b
  where b.implementation_case_id=p_implementation_case_id
    and b.organization_unit_id is null
    and b.ended_at is null
    and b.state in ('bound','activated')
  order by b.bound_at,b.id
  limit 1;

  if v_binding.id is not null then
    if v_binding.ledger_entitlement_id=p_ledger_entitlement_id
       and v_binding.organization_id=p_organization_id
       and v_binding.ledger_id=p_ledger_id then
      return jsonb_build_object(
        'ok',true,
        'alreadyBound',true,
        'implementationCaseId',p_implementation_case_id,
        'ledgerEntitlementId',p_ledger_entitlement_id,
        'bindingId',v_binding.id,
        'bindingState',v_binding.state,
        'organizationId',p_organization_id,
        'ledgerId',p_ledger_id,
        'scopeOrigin',p_scope_origin
      );
    end if;

    raise exception 'Implementation Case already has a different live institutional root scope.'
      using errcode='23505';
  end if;

  if v_entitlement.state not in ('available','reserved') then
    raise exception 'Ledger entitlement is not available for initial scope admission.'
      using errcode='23514';
  end if;

  if exists(
    select 1
    from atlas.ledger_entitlement_bindings b
    where b.ledger_id=p_ledger_id
      and b.organization_unit_id is null
      and b.ended_at is null
      and b.state in ('bound','activated')
  ) then
    raise exception 'Target Ledger already has a live root-scope entitlement binding.'
      using errcode='23505';
  end if;

  insert into atlas.ledger_entitlement_bindings(
    implementation_case_id,
    ledger_entitlement_id,
    organization_id,
    organization_unit_id,
    bound_by_participant_id,
    state,
    binding_basis,
    metadata,
    ledger_id
  ) values (
    p_implementation_case_id,
    p_ledger_entitlement_id,
    p_organization_id,
    null,
    p_practitioner_participant_id,
    'bound',
    p_establishment_basis || jsonb_build_object(
      'source','implementation_initial_scope_admission_v1',
      'scopeOrigin',p_scope_origin,
      'practitionerParticipantId',p_practitioner_participant_id,
      'setupSponsorParticipantId',p_setup_sponsor_participant_id,
      'setupSponsorPrincipalId',p_setup_sponsor_principal_id
    ),
    jsonb_build_object(
      'initialImplementationScope',true,
      'institutionalRealityPreexisting',p_scope_origin='existing_governed_scope'
    ),
    p_ledger_id
  )
  returning * into v_binding;

  update atlas.ledger_entitlements
  set state='bound',updated_at=now()
  where id=p_ledger_entitlement_id;

  update atlas.implementation_cases
  set metadata=metadata || jsonb_build_object(
      'initialScopeAdmittedAt',now(),
      'initialScopeBindingId',v_binding.id,
      'initialScopeOrigin',p_scope_origin
    ),
    updated_at=now()
  where id=p_implementation_case_id;

  return jsonb_build_object(
    'ok',true,
    'alreadyBound',false,
    'implementationCaseId',p_implementation_case_id,
    'ledgerEntitlementId',p_ledger_entitlement_id,
    'bindingId',v_binding.id,
    'bindingState',v_binding.state,
    'organizationId',p_organization_id,
    'ledgerId',p_ledger_id,
    'scopeOrigin',p_scope_origin
  );
end;
$function$;

revoke all on function atlas.bind_initial_implementation_scope_internal_v1(
  uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text
) from public,anon,authenticated,service_role;


create or replace function atlas.admit_existing_implementation_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_id uuid,
  p_ledger_id uuid,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_practitioner_participant_id uuid;
  v_setup_sponsor_participant_id uuid;
  v_setup_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_result jsonb;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select cp.id
  into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  join atlas.implementation_cases c
    on c.id=cp.implementation_case_id
   and c.state not in ('closed','cancelled')
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active
    and cp.ended_at is null
    and cp.human_user_id=v_uid
  order by cp.started_at,cp.id
  limit 1;

  if v_practitioner_participant_id is null then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  select cp.id,cp.human_user_id
  into v_setup_sponsor_participant_id,v_setup_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='setup_sponsor'
    and cp.active
    and cp.ended_at is null
    and cp.verified_at is not null
  order by cp.started_at,cp.id
  limit 1;

  if v_setup_sponsor_participant_id is null then
    raise exception 'Verified setup sponsor required before institutional scope admission.'
      using errcode='23514';
  end if;

  select pac.person_id
  into v_sponsor_person_id
  from atlas.person_auth_credentials pac
  join atlas.people p
    on p.id=pac.person_id
   and p.status='active'
  where pac.auth_user_id=v_setup_sponsor_user_id
    and pac.status='active'
  order by pac.bound_at,pac.id
  limit 1;

  select p.id
  into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id=v_sponsor_person_id
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_sponsor_principal_id is null then
    raise exception 'Verified setup sponsor must resolve to an active Principal.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.organizations o
    join atlas.ledger_organization_participations lop
      on lop.organization_id=o.id
     and lop.ledger_id=p_ledger_id
     and lop.status='active'
     and lop.ended_at is null
     and lop.participation_kind='governing'
     and lop.is_compatibility_primary
    join atlas.ledgers l
      on l.id=lop.ledger_id
     and l.status='active'
    where o.id=p_organization_id
      and o.status='active'
  ) then
    raise exception 'Target Organization and Ledger are not an active governing institutional scope.'
      using errcode='23514';
  end if;

  if not atlas.principal_has_ledger_authority_v1(
    v_sponsor_principal_id,p_ledger_id
  ) then
    raise exception 'Verified setup sponsor Principal does not govern the target Ledger.'
      using errcode='42501';
  end if;

  v_result:=atlas.bind_initial_implementation_scope_internal_v1(
    p_implementation_case_id,
    p_ledger_entitlement_id,
    p_organization_id,
    p_ledger_id,
    v_practitioner_participant_id,
    v_setup_sponsor_participant_id,
    v_sponsor_principal_id,
    p_establishment_basis,
    'existing_governed_scope'
  );

  return v_result || jsonb_build_object(
    'organizationCreated',false,
    'membershipCreated',false,
    'principalCreated',false
  );
end;
$function$;

revoke all on function atlas.admit_existing_implementation_scope_self_api_v1(
  uuid,uuid,uuid,uuid,jsonb
) from public,anon,authenticated,service_role;


create or replace function atlas.establish_new_implementation_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_name text,
  p_establishment_basis jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid:=auth.uid();
  v_name text:=btrim(coalesce(p_organization_name,''));
  v_practitioner_participant_id uuid;
  v_setup_sponsor_participant_id uuid;
  v_setup_sponsor_user_id uuid;
  v_sponsor_person_id uuid;
  v_sponsor_principal_id uuid;
  v_birth jsonb;
  v_organization_id uuid;
  v_ledger_id uuid;
  v_result jsonb;
  v_basis_kind text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if length(v_name)<2 or length(v_name)>160 then
    raise exception 'Organization name must be between 2 and 160 characters.'
      using errcode='22023';
  end if;

  v_basis_kind:=btrim(coalesce(p_establishment_basis->>'kind',''));
  if p_establishment_basis is null
     or jsonb_typeof(p_establishment_basis)<>'object'
     or v_basis_kind='' then
    raise exception 'Initial scope establishment basis with kind is required.'
      using errcode='22023';
  end if;

  if v_basis_kind not in (
    'setup_sponsor_confirmation',
    'verified_purchase_scope',
    'adjudicated_existing_reality'
  ) then
    raise exception 'Unsupported Initial Scope establishment basis.'
      using errcode='22023';
  end if;

  select cp.id
  into v_practitioner_participant_id
  from atlas.implementation_case_participants cp
  join atlas.implementation_cases c
    on c.id=cp.implementation_case_id
   and c.state not in ('closed','cancelled')
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='practitioner'
    and cp.active
    and cp.ended_at is null
    and cp.human_user_id=v_uid
  order by cp.started_at,cp.id
  limit 1;

  if v_practitioner_participant_id is null then
    raise exception 'Assigned practitioner authority required.'
      using errcode='42501';
  end if;

  select cp.id,cp.human_user_id
  into v_setup_sponsor_participant_id,v_setup_sponsor_user_id
  from atlas.implementation_case_participants cp
  where cp.implementation_case_id=p_implementation_case_id
    and cp.relationship_kind='setup_sponsor'
    and cp.active
    and cp.ended_at is null
    and cp.verified_at is not null
  order by cp.started_at,cp.id
  limit 1;

  if v_setup_sponsor_participant_id is null then
    raise exception 'Verified setup sponsor required before new institutional scope establishment.'
      using errcode='23514';
  end if;

  select pac.person_id
  into v_sponsor_person_id
  from atlas.person_auth_credentials pac
  join atlas.people p
    on p.id=pac.person_id
   and p.status='active'
  where pac.auth_user_id=v_setup_sponsor_user_id
    and pac.status='active'
  order by pac.bound_at,pac.id
  limit 1;

  select p.id
  into v_sponsor_principal_id
  from atlas.principals p
  where p.person_id=v_sponsor_person_id
    and p.status='active'
  order by p.created_at,p.id
  limit 1;

  if v_sponsor_person_id is null or v_sponsor_principal_id is null then
    raise exception 'Verified setup sponsor must resolve to canonical Person + active Principal.'
      using errcode='23514';
  end if;

  -- Lock and validate the entitlement BEFORE institutional birth so any later
  -- failure remains one transaction and creates no orphan Organization.
  perform 1
  from atlas.ledger_entitlements le
  where le.id=p_ledger_entitlement_id
    and le.implementation_case_id=p_implementation_case_id
    and le.price_class='baseline_first'
    and le.state in ('available','reserved')
  for update;

  if not found then
    raise exception 'Available Ledger entitlement required for new initial scope.'
      using errcode='23514';
  end if;

  if exists(
    select 1
    from atlas.ledger_entitlement_bindings b
    where b.implementation_case_id=p_implementation_case_id
      and b.organization_unit_id is null
      and b.ended_at is null
      and b.state in ('bound','activated')
  ) then
    raise exception 'Implementation Case already has a live institutional root scope.'
      using errcode='23505';
  end if;

  v_birth:=atlas.establish_organization_ledger_for_principal_v1(
    v_sponsor_principal_id,
    v_sponsor_person_id,
    v_setup_sponsor_user_id,
    v_name,
    false,
    false,
    'implementation_initial_scope_admission:' || v_basis_kind
  );

  v_organization_id:=(v_birth->'organization'->>'id')::uuid;
  v_ledger_id:=(v_birth->'ledger'->>'id')::uuid;

  if v_organization_id is null or v_ledger_id is null then
    raise exception 'Canonical Organization + Ledger birth did not return institutional scope.'
      using errcode='23514';
  end if;

  v_result:=atlas.bind_initial_implementation_scope_internal_v1(
    p_implementation_case_id,
    p_ledger_entitlement_id,
    v_organization_id,
    v_ledger_id,
    v_practitioner_participant_id,
    v_setup_sponsor_participant_id,
    v_sponsor_principal_id,
    p_establishment_basis,
    'new_principal_scope'
  );

  return v_result || jsonb_build_object(
    'organizationCreated',true,
    'organizationName',v_name,
    'membershipCreated',false,
    'principalCreated',false,
    'institutionalBirth',v_birth
  );
end;
$function$;

revoke all on function atlas.establish_new_implementation_scope_self_api_v1(
  uuid,uuid,text,jsonb
) from public,anon,authenticated,service_role;


create or replace function public.admit_existing_implementation_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_id uuid,
  p_ledger_id uuid,
  p_establishment_basis jsonb
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.admit_existing_implementation_scope_self_api_v1(
    p_implementation_case_id,
    p_ledger_entitlement_id,
    p_organization_id,
    p_ledger_id,
    p_establishment_basis
  );
$function$;

create or replace function public.establish_new_implementation_scope_self_api_v1(
  p_implementation_case_id uuid,
  p_ledger_entitlement_id uuid,
  p_organization_name text,
  p_establishment_basis jsonb
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $function$
  select atlas.establish_new_implementation_scope_self_api_v1(
    p_implementation_case_id,
    p_ledger_entitlement_id,
    p_organization_name,
    p_establishment_basis
  );
$function$;

revoke all on function public.admit_existing_implementation_scope_self_api_v1(
  uuid,uuid,uuid,uuid,jsonb
) from public,anon,service_role;
revoke all on function public.establish_new_implementation_scope_self_api_v1(
  uuid,uuid,text,jsonb
) from public,anon,service_role;

grant execute on function public.admit_existing_implementation_scope_self_api_v1(
  uuid,uuid,uuid,uuid,jsonb
) to authenticated;
grant execute on function public.establish_new_implementation_scope_self_api_v1(
  uuid,uuid,text,jsonb
) to authenticated;

comment on function public.admit_existing_implementation_scope_self_api_v1(
  uuid,uuid,uuid,uuid,jsonb
) is
  'Initial Implementation scope admission for an already-canonical Organization + Ledger that the verified setup sponsor Principal root-governs.';

comment on function public.establish_new_implementation_scope_self_api_v1(
  uuid,uuid,text,jsonb
) is
  'Initial Implementation scope establishment for a genuinely new Organization. Delegates canonical Organization + Ledger birth to the verified setup sponsor Principal without creating Membership or separate onboarding access.';

commit;
