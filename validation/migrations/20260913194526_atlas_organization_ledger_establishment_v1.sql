-- Canonical behavioral postconditions for Atlas Organization + Ledger Establishment v1.
-- Runs only in the disposable production-schema clone after fixture + candidate migration.

do $proof$
declare
  v_uid constant uuid := '66666666-6666-4666-8666-666666666666'::uuid;
  v_principal_id constant uuid := '77777777-7777-4777-8777-777777777777'::uuid;
  v_no_principal_uid constant uuid := '88888888-8888-4888-8888-888888888888'::uuid;
  v_person_id uuid;
  v_no_principal_person_id uuid;
  v_result jsonb;
  v_org_id uuid;
  v_ledger_id uuid;
  v_membership_id uuid;
  v_failed boolean;
  v_def text;
  v_entitlements_before bigint;
  v_bindings_before bigint;
  v_implementation_purchases_before bigint;
  v_personal_purchases_before bigint;
  v_employee_seats_before bigint;
  v_entitlements_after bigint;
  v_bindings_after bigint;
  v_implementation_purchases_after bigint;
  v_personal_purchases_after bigint;
  v_employee_seats_after bigint;
begin
  select c.person_id
  into v_person_id
  from atlas.person_auth_credentials c
  where c.auth_user_id = v_uid
    and c.status = 'active'
  limit 1;

  select c.person_id
  into v_no_principal_person_id
  from atlas.person_auth_credentials c
  where c.auth_user_id = v_no_principal_uid
    and c.status = 'active'
  limit 1;

  if v_person_id is null or v_no_principal_person_id is null then
    raise exception 'Validation fixture did not establish canonical Person bindings.';
  end if;

  if not exists (
    select 1
    from atlas.principals p
    where p.id = v_principal_id
      and p.person_id = v_person_id
      and p.status = 'active'
  ) then
    raise exception 'Validation fixture Principal is not Person-backed.';
  end if;

  select count(*) into v_entitlements_before from atlas.ledger_entitlements;
  select count(*) into v_bindings_before from atlas.ledger_entitlement_bindings;
  select count(*) into v_implementation_purchases_before from atlas.implementation_purchases;
  select count(*) into v_personal_purchases_before from atlas.personal_atlas_purchases;
  select count(*) into v_employee_seats_before from atlas.organization_employee_seats;

  perform set_config('request.jwt.claim.sub',v_uid::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_uid::text,'role','authenticated')::text,
    true
  );

  if auth.uid() is distinct from v_uid then
    raise exception 'Authenticated validation identity could not be established.';
  end if;

  if atlas.current_person_id_v1() is distinct from v_person_id
     or atlas.current_principal_id_v1() is distinct from v_principal_id then
    raise exception 'Person-first validation resolution is unavailable.';
  end if;

  -- Canonical default: root authority + onboarding, but no Organization Membership.
  v_result := atlas.establish_organization_ledger_self_api_v1(
    'Ledger Establishment Default Fixture',
    false,
    true
  );
  v_org_id := (v_result->'organization'->>'id')::uuid;
  v_ledger_id := (v_result->'ledger'->>'id')::uuid;

  if v_org_id is null or v_ledger_id is null then
    raise exception 'Canonical establishment did not return Organization + Ledger.';
  end if;

  if (select count(*) from atlas.ledgers l where l.organization_id=v_org_id and l.status='active' and l.ledger_kind='organization_governing') <> 1 then
    raise exception 'Canonical establishment did not produce exactly one governing Ledger.';
  end if;

  if not exists (
    select 1
    from atlas.principal_ledger_authorities a
    where a.principal_id=v_principal_id
      and a.ledger_id=v_ledger_id
      and a.authority_kind='root_governing'
      and a.status='active'
  ) then
    raise exception 'Canonical establishment did not produce root Principal Ledger authority.';
  end if;

  if exists (
    select 1 from atlas.organization_memberships m
    where m.organization_id=v_org_id and m.active
  ) then
    raise exception 'Default canonical establishment unexpectedly created Organization Membership.';
  end if;

  if not exists (
    select 1 from atlas.organization_onboarding_actors a
    where a.organization_id=v_org_id and a.human_user_id=v_uid and a.active
  ) then
    raise exception 'Default canonical establishment did not create onboarding actor.';
  end if;

  if not exists (
    select 1 from atlas.reconstruction_sessions s
    where s.id=(v_result->'reconstruction'->>'id')::uuid
      and s.target_organization_id=v_org_id
      and s.human_user_id=v_uid
      and s.clean_room
      and not s.allow_existing_atlas_canon
  ) then
    raise exception 'Default canonical establishment did not create clean-room reconstruction.';
  end if;

  -- Owner-membership mode: authority remains explicit and membership carries both compatibility + Person identity.
  v_result := atlas.establish_organization_ledger_self_api_v1(
    'Owner Membership Establishment Fixture',
    true,
    true
  );
  v_org_id := (v_result->'organization'->>'id')::uuid;
  v_ledger_id := (v_result->'ledger'->>'id')::uuid;
  v_membership_id := (v_result->'membership'->>'id')::uuid;

  if v_membership_id is null then
    raise exception 'Owner-membership mode did not return membership.';
  end if;

  if not exists (
    select 1
    from atlas.organization_memberships m
    where m.id=v_membership_id
      and m.organization_id=v_org_id
      and m.user_id=v_uid
      and m.person_id=v_person_id
      and m.role='owner'
      and m.active
  ) then
    raise exception 'Owner membership did not preserve matching credential + Person identity.';
  end if;

  if not exists (
    select 1 from atlas.principal_ledger_authorities a
    where a.principal_id=v_principal_id and a.ledger_id=v_ledger_id
      and a.authority_kind='root_governing' and a.status='active'
  ) then
    raise exception 'Owner-membership mode lacks independent root Ledger authority.';
  end if;

  -- Legacy clean-room onboarding wrapper preserves no-membership semantics and gains Ledger authority.
  v_result := atlas.begin_organization_onboarding_self_api_v1('Legacy Begin Wrapper Fixture');
  v_org_id := (v_result->'organization'->>'id')::uuid;
  v_ledger_id := (v_result->'ledger'->>'id')::uuid;

  if coalesce((v_result->'setupActor'->>'membership_created')::boolean,true) then
    raise exception 'Legacy begin wrapper no-membership semantic changed.';
  end if;

  if exists (
    select 1 from atlas.organization_memberships m
    where m.organization_id=v_org_id and m.active
  ) then
    raise exception 'Legacy begin wrapper unexpectedly created membership.';
  end if;

  if not exists (
    select 1 from atlas.principal_ledger_authorities a
    where a.principal_id=v_principal_id and a.ledger_id=v_ledger_id
      and a.authority_kind='root_governing' and a.status='active'
  ) then
    raise exception 'Legacy begin wrapper did not establish root Ledger authority.';
  end if;

  -- Historical service-only wrapper preserves owner-membership + reconstruction behavior while delegating birth.
  v_result := atlas.establish_organization_self_api_v1('Legacy Owner Wrapper Fixture');
  v_org_id := (v_result->'organization'->>'id')::uuid;
  v_ledger_id := (v_result->'ledger'->>'id')::uuid;
  v_membership_id := (v_result->'membership'->>'id')::uuid;

  if v_membership_id is null or not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_membership_id
      and m.organization_id=v_org_id
      and m.user_id=v_uid
      and m.person_id=v_person_id
      and m.role='owner'
      and m.active
  ) then
    raise exception 'Legacy owner wrapper did not preserve owner membership semantics.';
  end if;

  if not exists (
    select 1 from atlas.principal_ledger_authorities a
    where a.principal_id=v_principal_id and a.ledger_id=v_ledger_id
      and a.authority_kind='root_governing' and a.status='active'
  ) then
    raise exception 'Legacy owner wrapper did not establish root Ledger authority.';
  end if;

  if (
    select count(*)
    from atlas.principal_ledger_authorities a
    where a.principal_id=v_principal_id
      and a.authority_kind='root_governing'
      and a.status='active'
  ) < 4 then
    raise exception 'Schema or transaction incorrectly restricts one Principal from governing multiple Ledgers.';
  end if;

  -- Signed-in Person without an active Principal fails closed.
  perform set_config('request.jwt.claim.sub',v_no_principal_uid::text,true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_no_principal_uid::text,'role','authenticated')::text,
    true
  );
  v_failed := false;
  begin
    perform atlas.establish_organization_ledger_self_api_v1('No Principal Must Fail',false,true);
  exception when sqlstate '42501' then
    v_failed := true;
    if position('Principal required.' in sqlerrm)=0 then
      raise exception 'No-Principal failure used unexpected error: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Signed-in Person without Principal unexpectedly established an Organization.';
  end if;

  -- Explicit Principal/Person contradiction fails before institutional creation.
  perform set_config('request.jwt.claim.sub',v_uid::text,true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_uid::text,'role','authenticated')::text,
    true
  );
  v_failed := false;
  begin
    perform atlas.establish_organization_ledger_for_principal_v1(
      v_principal_id,
      v_no_principal_person_id,
      v_uid,
      'Identity Contradiction Must Fail',
      false,
      false,
      'validation_contradiction'
    );
  exception when sqlstate '23514' then
    v_failed := true;
    if position('Principal / Person identity contradiction.' in sqlerrm)=0 then
      raise exception 'Identity contradiction used unexpected error: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Contradictory Principal/Person identity unexpectedly established an Organization.';
  end if;

  -- Canonical institutional establishment must be noncommercial.
  select count(*) into v_entitlements_after from atlas.ledger_entitlements;
  select count(*) into v_bindings_after from atlas.ledger_entitlement_bindings;
  select count(*) into v_implementation_purchases_after from atlas.implementation_purchases;
  select count(*) into v_personal_purchases_after from atlas.personal_atlas_purchases;
  select count(*) into v_employee_seats_after from atlas.organization_employee_seats;

  if v_entitlements_after <> v_entitlements_before
     or v_bindings_after <> v_bindings_before
     or v_implementation_purchases_after <> v_implementation_purchases_before
     or v_personal_purchases_after <> v_personal_purchases_before
     or v_employee_seats_after <> v_employee_seats_before then
    raise exception 'Institutional establishment mutated commercial entitlement/purchase/seat state.';
  end if;

  -- Function membrane and dependency proof.
  if to_regprocedure('atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)') is null
     or to_regprocedure('atlas.establish_organization_ledger_self_api_v1(text,boolean,boolean)') is null
     or to_regprocedure('atlas.begin_organization_onboarding_self_api_v1(text)') is null
     or to_regprocedure('atlas.establish_organization_self_api_v1(text)') is null then
    raise exception 'Organization Ledger establishment function membrane is incomplete.';
  end if;

  select pg_get_functiondef('atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)'::regprocedure)
  into v_def;
  if position('ledger_entitlements' in v_def)>0
     or position('ledger_entitlement_bindings' in v_def)>0
     or position('implementation_purchases' in v_def)>0
     or position('personal_atlas_purchases' in v_def)>0
     or position('stripe' in lower(v_def))>0 then
    raise exception 'Internal institutional establishment kernel depends on commercial state.';
  end if;

  select pg_get_functiondef('atlas.establish_organization_ledger_self_api_v1(text,boolean,boolean)'::regprocedure)
  into v_def;
  if position('atlas.current_person_id_v1()' in v_def)=0
     or position('atlas.current_principal_id_v1()' in v_def)=0
     or position('atlas.establish_organization_ledger_for_principal_v1' in v_def)=0
     or position('establish_implementation_organization_scope_self_api_v1' in v_def)>0 then
    raise exception 'Canonical self API does not resolve Person/Principal or is coupled to implementation establishment.';
  end if;

  select pg_get_functiondef('atlas.begin_organization_onboarding_self_api_v1(text)'::regprocedure)
  into v_def;
  if position('atlas.establish_organization_ledger_self_api_v1' in v_def)=0 then
    raise exception 'Legacy begin-onboarding wrapper still implements independent Organization birth.';
  end if;

  select pg_get_functiondef('atlas.establish_organization_self_api_v1(text)'::regprocedure)
  into v_def;
  if position('atlas.establish_organization_ledger_self_api_v1' in v_def)=0 then
    raise exception 'Legacy owner wrapper still implements independent Organization birth.';
  end if;

  if to_regprocedure('atlas.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text)') is null then
    raise exception 'Transitional commercial/practitioner establishment function was unexpectedly removed.';
  end if;

  if has_function_privilege('anon','atlas.establish_organization_ledger_self_api_v1(text,boolean,boolean)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.establish_organization_ledger_self_api_v1(text,boolean,boolean)','EXECUTE') then
    raise exception 'Canonical Organization Ledger self API grants are incorrect.';
  end if;

  if has_function_privilege('anon','atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.establish_organization_ledger_for_principal_v1(uuid,uuid,uuid,text,boolean,boolean,text)','EXECUTE') then
    raise exception 'Internal institutional establishment kernel became browser-callable.';
  end if;

  if not has_function_privilege('authenticated','atlas.begin_organization_onboarding_self_api_v1(text)','EXECUTE')
     or has_function_privilege('anon','atlas.begin_organization_onboarding_self_api_v1(text)','EXECUTE') then
    raise exception 'Legacy begin-onboarding wrapper grants changed incorrectly.';
  end if;

  if has_function_privilege('authenticated','atlas.establish_organization_self_api_v1(text)','EXECUTE')
     or not has_function_privilege('service_role','atlas.establish_organization_self_api_v1(text)','EXECUTE') then
    raise exception 'Legacy service-only owner wrapper grants changed incorrectly.';
  end if;
end;
$proof$;
