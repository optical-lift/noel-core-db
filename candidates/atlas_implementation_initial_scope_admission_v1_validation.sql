begin;

do $validation$
declare
  v_practitioner constant uuid := 'f4600000-0000-4000-8000-000000000001'::uuid;
  v_existing_case constant uuid := 'f4600000-0000-4000-8000-000000000111'::uuid;
  v_new_case constant uuid := 'f4600000-0000-4000-8000-000000000112'::uuid;
  v_existing_entitlement constant uuid := 'f4600000-0000-4000-8000-000000000341'::uuid;
  v_new_entitlement constant uuid := 'f4600000-0000-4000-8000-000000000342'::uuid;
  v_existing_org constant uuid := 'f4600000-0000-4000-8000-000000000301'::uuid;
  v_existing_ledger constant uuid := 'f4600000-0000-4000-8000-000000000311'::uuid;
  v_unauthorized_org constant uuid := 'f4600000-0000-4000-8000-000000000302'::uuid;
  v_unauthorized_ledger constant uuid := 'f4600000-0000-4000-8000-000000000312'::uuid;
  v_result jsonb;
  v_binding_id uuid;
  v_new_org uuid;
  v_new_ledger uuid;
  v_org_count bigint;
  v_membership_count bigint;
  v_def text;
  v_failed boolean;
begin
  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  select count(*) into v_org_count from atlas.organizations;
  select count(*) into v_membership_count from atlas.organization_memberships;

  -- Existing scope: a Principal-external Organization is rejected.
  v_failed:=false;
  begin
    perform public.admit_existing_implementation_scope_self_api_v1(
      v_existing_case,
      v_existing_entitlement,
      v_unauthorized_org,
      v_unauthorized_ledger,
      '{"kind":"adjudicated_existing_reality","reference":"fixture:unauthorized"}'::jsonb
    );
  exception when sqlstate '42501' then
    v_failed:=true;
  end;

  if not v_failed then
    raise exception 'Existing-scope admission crossed setup-sponsor Principal authority.';
  end if;

  if exists(
    select 1 from atlas.ledger_entitlement_bindings
    where implementation_case_id=v_existing_case and ended_at is null
  ) then
    raise exception 'Rejected existing-scope admission still created a binding.';
  end if;

  -- Existing scope: canonical sponsor-governed scope binds without creating identity.
  v_result:=public.admit_existing_implementation_scope_self_api_v1(
    v_existing_case,
    v_existing_entitlement,
    v_existing_org,
    v_existing_ledger,
    '{"kind":"adjudicated_existing_reality","reference":"fixture:existing"}'::jsonb
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or coalesce((v_result->>'alreadyBound')::boolean,true)
     or coalesce((v_result->>'organizationCreated')::boolean,true)
     or coalesce((v_result->>'membershipCreated')::boolean,true) then
    raise exception 'Valid existing initial scope did not bind cleanly: %',v_result;
  end if;

  v_binding_id:=(v_result->>'bindingId')::uuid;

  if not exists(
    select 1
    from atlas.ledger_entitlement_bindings b
    where b.id=v_binding_id
      and b.implementation_case_id=v_existing_case
      and b.ledger_entitlement_id=v_existing_entitlement
      and b.organization_id=v_existing_org
      and b.ledger_id=v_existing_ledger
      and b.state='bound'
      and b.organization_unit_id is null
      and b.binding_basis->>'scopeOrigin'='existing_governed_scope'
  ) then
    raise exception 'Existing scope canonical binding receipt is incorrect.';
  end if;

  if (select count(*) from atlas.organizations)<>v_org_count
     or (select count(*) from atlas.organization_memberships)<>v_membership_count then
    raise exception 'Existing scope admission manufactured Organization or Membership.';
  end if;

  v_result:=public.admit_existing_implementation_scope_self_api_v1(
    v_existing_case,
    v_existing_entitlement,
    v_existing_org,
    v_existing_ledger,
    '{"kind":"adjudicated_existing_reality","reference":"fixture:retry"}'::jsonb
  );

  if not coalesce((v_result->>'alreadyBound')::boolean,false)
     or (v_result->>'bindingId')::uuid<>v_binding_id then
    raise exception 'Existing initial scope admission is not idempotent: %',v_result;
  end if;

  -- New scope: Organization + Ledger + sponsor authority + participation are born
  -- canonically and entitlement binding happens in the same transaction.
  v_result:=public.establish_new_implementation_scope_self_api_v1(
    v_new_case,
    v_new_entitlement,
    'New Canonical Organization',
    '{"kind":"setup_sponsor_confirmation","reference":"fixture:new"}'::jsonb
  );

  if not coalesce((v_result->>'ok')::boolean,false)
     or not coalesce((v_result->>'organizationCreated')::boolean,false)
     or coalesce((v_result->>'membershipCreated')::boolean,true)
     or coalesce((v_result->>'principalCreated')::boolean,true) then
    raise exception 'New initial scope did not establish expected institutional birth: %',v_result;
  end if;

  v_new_org:=(v_result->>'organizationId')::uuid;
  v_new_ledger:=(v_result->>'ledgerId')::uuid;

  if not exists(
    select 1
    from atlas.organizations o
    join atlas.ledger_organization_participations lop
      on lop.organization_id=o.id
     and lop.ledger_id=v_new_ledger
     and lop.status='active'
     and lop.participation_kind='governing'
     and lop.is_compatibility_primary
    join atlas.principal_ledger_authorities a
      on a.ledger_id=v_new_ledger
     and a.principal_id='f4600000-0000-4000-8000-000000000221'::uuid
     and a.status='active'
     and a.authority_kind='root_governing'
    where o.id=v_new_org
      and o.name='New Canonical Organization'
      and o.status='active'
  ) then
    raise exception 'New scope did not establish Organization, governing participation, and sponsor Principal authority.';
  end if;

  if not exists(
    select 1
    from atlas.ledger_entitlement_bindings b
    where b.implementation_case_id=v_new_case
      and b.ledger_entitlement_id=v_new_entitlement
      and b.organization_id=v_new_org
      and b.ledger_id=v_new_ledger
      and b.state='bound'
      and b.binding_basis->>'scopeOrigin'='new_principal_scope'
  ) then
    raise exception 'New institutional scope was not bound atomically to its case entitlement.';
  end if;

  if exists(
    select 1
    from atlas.organization_memberships m
    where m.organization_id=v_new_org
  ) then
    raise exception 'New initial scope establishment manufactured Organization Membership.';
  end if;

  if exists(
    select 1
    from atlas.institutional_person_records ipr
    where ipr.organization_id=v_new_org
  ) then
    raise exception 'New initial scope establishment manufactured Institutional Person identity.';
  end if;

  if exists(
    select 1
    from atlas.organization_onboarding_actors a
    where a.organization_id=v_new_org
  ) then
    raise exception 'New Initial Scope unexpectedly started separate Organization onboarding actor state.';
  end if;

  if exists(
    select 1
    from atlas.reconstruction_sessions s
    where s.target_organization_id=v_new_org
  ) then
    raise exception 'New Initial Scope unexpectedly started a separate reconstruction session.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.admit_existing_implementation_scope_self_api_v1(uuid,uuid,uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.admit_existing_implementation_scope_self_api_v1(uuid,uuid,uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.establish_new_implementation_scope_self_api_v1(uuid,uuid,text,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'atlas.establish_new_implementation_scope_self_api_v1(uuid,uuid,text,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'atlas.bind_initial_implementation_scope_internal_v1(uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'Initial Scope admission leaked direct internal mutation authority.';
  end if;

  if has_function_privilege(
       'anon',
       'public.admit_existing_implementation_scope_self_api_v1(uuid,uuid,uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.establish_new_implementation_scope_self_api_v1(uuid,uuid,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role can mutate Initial Scope.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.admit_existing_implementation_scope_self_api_v1(uuid,uuid,uuid,uuid,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.establish_new_implementation_scope_self_api_v1(uuid,uuid,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated practitioner Initial Scope membranes are unavailable.';
  end if;

  select regexp_replace(
    lower(pg_get_functiondef(
      'atlas.bind_initial_implementation_scope_internal_v1(uuid,uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)'::regprocedure
    )),
    '[[:space:]]+','','g'
  ) into v_def;

  if v_def not like '%price_class=''baseline_first''%' then
    raise exception 'Initial Scope binding helper no longer requires the baseline-first entitlement.';
  end if;

  select lower(pg_get_functiondef(
    'atlas.admit_existing_implementation_scope_self_api_v1(uuid,uuid,uuid,uuid,jsonb)'::regprocedure
  )) into v_def;

  if v_def not like '%relationship_kind=''setup_sponsor''%'
     or v_def not like '%principal_has_ledger_authority_v1%'
     or v_def not like '%ledger_organization_participations%'
     or v_def like '%implementation_establishment_items%' then
    raise exception 'Existing Initial Scope command lost sponsor/Principal authority or regressed to legacy text authority.';
  end if;

  select regexp_replace(
    lower(pg_get_functiondef(
      'atlas.establish_new_implementation_scope_self_api_v1(uuid,uuid,text,jsonb)'::regprocedure
    )),
    '[[:space:]]+','','g'
  ) into v_def;

  if v_def not like '%price_class=''baseline_first''%' then
    raise exception 'New Initial Scope command no longer restricts institutional birth to the baseline-first entitlement.';
  end if;


  if v_def not like '%establish_organization_ledger_for_principal_v1%'
     or v_def not like '%false,false%'
     or v_def like '%organization_memberships%'
     or v_def like '%implementation_establishment_items%' then
    raise exception 'New Initial Scope command widened beyond canonical no-membership institutional birth.';
  end if;

  if v_def not like '%setup_sponsor_confirmation%'
     or v_def not like '%verified_purchase_scope%'
     or v_def not like '%adjudicated_existing_reality%' then
    raise exception 'New Initial Scope command lost its governed establishment-basis vocabulary.';
  end if;
end;
$validation$;

rollback;
