-- Canonical behavioral postconditions for Atlas Commercial Ledger Binding v1.
-- Runs only in the disposable production-schema clone after fixture + candidate migration.

do $proof$
declare
  v_practitioner_uid constant uuid := '33333333-3333-4333-8333-333333333331'::uuid;
  v_case_one constant uuid := '44444444-4444-4444-8444-444444444411'::uuid;
  v_case_two constant uuid := '55555555-5555-4555-8555-555555555511'::uuid;
  v_case_three constant uuid := '66666666-6666-4666-8666-666666666611'::uuid;
  v_case_four constant uuid := '77777777-7777-4777-8777-777777777711'::uuid;
  v_entitlement_one constant uuid := '44444444-4444-4444-8444-444444444441'::uuid;
  v_entitlement_two constant uuid := '55555555-5555-4555-8555-555555555541'::uuid;
  v_entitlement_three constant uuid := '66666666-6666-4666-8666-666666666641'::uuid;
  v_entitlement_four constant uuid := '77777777-7777-4777-8777-777777777741'::uuid;
  v_institution_one constant uuid := '44444444-4444-4444-8444-444444444431'::uuid;
  v_ledger_scope_one constant uuid := '44444444-4444-4444-8444-444444444432'::uuid;
  v_institution_three constant uuid := '66666666-6666-4666-8666-666666666631'::uuid;
  v_ledger_scope_three constant uuid := '66666666-6666-4666-8666-666666666632'::uuid;
  v_institution_four constant uuid := '77777777-7777-4777-8777-777777777731'::uuid;
  v_ledger_scope_four constant uuid := '77777777-7777-4777-8777-777777777732'::uuid;
  v_org_a uuid;
  v_org_b uuid;
  v_org_c uuid;
  v_ledger_a uuid;
  v_ledger_b uuid;
  v_ledger_c uuid;
  v_result jsonb;
  v_retry jsonb;
  v_binding_id uuid;
  v_failed boolean;
  v_def text;
  v_orgs_before bigint;
  v_ledgers_before bigint;
  v_principals_before bigint;
  v_authorities_before bigint;
  v_memberships_before bigint;
  v_orgs_after bigint;
  v_ledgers_after bigint;
  v_principals_after bigint;
  v_authorities_after bigint;
  v_memberships_after bigint;
  v_bindings_before bigint;
  v_bindings_after bigint;
begin
  select o.id,l.id into v_org_a,v_ledger_a
  from atlas.organizations o
  join atlas.ledgers l on l.organization_id=o.id and l.status='active'
  where o.stable_key='commercial_binding_target_a';

  select o.id,l.id into v_org_b,v_ledger_b
  from atlas.organizations o
  join atlas.ledgers l on l.organization_id=o.id and l.status='active'
  where o.stable_key='commercial_binding_target_b';

  select o.id,l.id into v_org_c,v_ledger_c
  from atlas.organizations o
  join atlas.ledgers l on l.organization_id=o.id and l.status='active'
  where o.stable_key='commercial_binding_target_c';

  if v_org_a is null or v_org_b is null or v_org_c is null
     or v_ledger_a is null or v_ledger_b is null or v_ledger_c is null then
    raise exception 'Validation fixture did not establish all pre-existing institutional targets.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner_uid::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_practitioner_uid::text,'role','authenticated')::text,
    true
  );

  if auth.uid() is distinct from v_practitioner_uid
     or not atlas.implementation_practitioner_authorized_self_v1() then
    raise exception 'Validation practitioner identity is unavailable.';
  end if;

  select count(*) into v_orgs_before from atlas.organizations;
  select count(*) into v_ledgers_before from atlas.ledgers;
  select count(*) into v_principals_before from atlas.principals;
  select count(*) into v_authorities_before from atlas.principal_ledger_authorities;
  select count(*) into v_memberships_before from atlas.organization_memberships;
  select count(*) into v_bindings_before from atlas.ledger_entitlement_bindings;

  -- Old commercial creator must fail closed when no prior binding exists.
  v_failed := false;
  begin
    perform atlas.establish_implementation_organization_scope_self_api_v1(
      v_case_one,
      v_institution_one,
      v_ledger_scope_one,
      v_entitlement_one,
      'Must Not Create'
    );
  exception when sqlstate '0A000' then
    v_failed := true;
    if position('Institutional scope must already exist.' in sqlerrm)=0 then
      raise exception 'Legacy creator failed with unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Legacy commercial creator unexpectedly created institutional scope.';
  end if;

  if (select count(*) from atlas.organizations) <> v_orgs_before then
    raise exception 'Legacy commercial creator changed Organization count.';
  end if;

  -- Practitioner must be assigned to the implementation case.
  v_failed := false;
  begin
    perform atlas.bind_implementation_ledger_entitlement_self_api_v1(
      v_case_four,
      v_institution_four,
      v_ledger_scope_four,
      v_entitlement_four,
      v_org_a,
      v_ledger_a
    );
  exception when sqlstate '42501' then
    v_failed := true;
    if position('not assigned' in sqlerrm)=0 then
      raise exception 'Unassigned-practitioner failure used unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Unassigned practitioner unexpectedly bound entitlement.';
  end if;

  -- Assigned practitioner still cannot proceed without verified sponsor evidence.
  v_failed := false;
  begin
    perform atlas.bind_implementation_ledger_entitlement_self_api_v1(
      v_case_three,
      v_institution_three,
      v_ledger_scope_three,
      v_entitlement_three,
      v_org_a,
      v_ledger_a
    );
  exception when sqlstate '23514' then
    v_failed := true;
    if position('verified setup sponsor' in lower(sqlerrm))=0 then
      raise exception 'Missing-sponsor failure used unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Case without verified sponsor unexpectedly bound entitlement.';
  end if;

  -- Sponsor Principal One does not govern Target B.
  v_failed := false;
  begin
    perform atlas.bind_implementation_ledger_entitlement_self_api_v1(
      v_case_one,
      v_institution_one,
      v_ledger_scope_one,
      v_entitlement_one,
      v_org_b,
      v_ledger_b
    );
  exception when sqlstate '42501' then
    v_failed := true;
    if position('does not govern the target Ledger.' in sqlerrm)=0 then
      raise exception 'Unauthorized-Ledger failure used unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Sponsor without root authority unexpectedly bound Target B.';
  end if;

  -- Ledger and Organization must be the same canonical institutional scope.
  v_failed := false;
  begin
    perform atlas.bind_implementation_ledger_entitlement_self_api_v1(
      v_case_one,
      v_institution_one,
      v_ledger_scope_one,
      v_entitlement_one,
      v_org_a,
      v_ledger_c
    );
  exception when sqlstate '23514' then
    v_failed := true;
    if position('active governing Ledger' in sqlerrm)=0 then
      raise exception 'Organization/Ledger mismatch used unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Mismatched Organization/Ledger unexpectedly bound entitlement.';
  end if;

  -- Entitlement must belong to the same implementation case.
  v_failed := false;
  begin
    perform atlas.bind_implementation_ledger_entitlement_self_api_v1(
      v_case_one,
      v_institution_one,
      v_ledger_scope_one,
      v_entitlement_two,
      v_org_a,
      v_ledger_a
    );
  exception when sqlstate '23503' then
    v_failed := true;
    if position('not found for this implementation case' in sqlerrm)=0 then
      raise exception 'Cross-case entitlement failure used unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Entitlement from another implementation case unexpectedly bound.';
  end if;

  -- Happy path: bind commerce to already-existing sponsor-governed Target A.
  v_result := atlas.bind_implementation_ledger_entitlement_self_api_v1(
    v_case_one,
    v_institution_one,
    v_ledger_scope_one,
    v_entitlement_one,
    v_org_a,
    v_ledger_a
  );

  v_binding_id := (v_result->>'bindingId')::uuid;
  if v_binding_id is null
     or coalesce((v_result->>'alreadyBound')::boolean,true)
     or coalesce((v_result->>'organizationCreated')::boolean,true)
     or coalesce((v_result->>'principalCreated')::boolean,true)
     or coalesce((v_result->>'membershipCreated')::boolean,true) then
    raise exception 'Happy-path commercial binding returned incorrect identity semantics: %',v_result;
  end if;

  if not exists (
    select 1
    from atlas.ledger_entitlement_bindings b
    where b.id=v_binding_id
      and b.implementation_case_id=v_case_one
      and b.ledger_entitlement_id=v_entitlement_one
      and b.organization_id=v_org_a
      and b.ledger_id=v_ledger_a
      and b.organization_unit_id is null
      and b.ended_at is null
      and b.state='bound'
  ) then
    raise exception 'Happy-path binding row does not preserve explicit Organization + Ledger scope.';
  end if;

  if not exists (
    select 1 from atlas.ledger_entitlements le
    where le.id=v_entitlement_one and le.state='bound'
  ) then
    raise exception 'Entitlement was not marked bound.';
  end if;

  if not exists (
    select 1 from atlas.implementation_cases c
    where c.id=v_case_one
      and c.metadata->>'organizationId'=v_org_a::text
      and c.metadata->>'ledgerId'=v_ledger_a::text
      and c.metadata->>'baselineLedgerBindingId'=v_binding_id::text
  ) then
    raise exception 'Implementation case did not retain commercial binding evidence.';
  end if;

  select count(*) into v_orgs_after from atlas.organizations;
  select count(*) into v_ledgers_after from atlas.ledgers;
  select count(*) into v_principals_after from atlas.principals;
  select count(*) into v_authorities_after from atlas.principal_ledger_authorities;
  select count(*) into v_memberships_after from atlas.organization_memberships;
  select count(*) into v_bindings_after from atlas.ledger_entitlement_bindings;

  if v_orgs_after<>v_orgs_before
     or v_ledgers_after<>v_ledgers_before
     or v_principals_after<>v_principals_before
     or v_authorities_after<>v_authorities_before
     or v_memberships_after<>v_memberships_before then
    raise exception 'Commercial binding mutated institutional identity or authority counts.';
  end if;

  if v_bindings_after<>v_bindings_before+1 then
    raise exception 'Commercial binding did not create exactly one entitlement binding.';
  end if;

  -- Same target retry is idempotent and returns the same binding.
  v_retry := atlas.bind_implementation_ledger_entitlement_self_api_v1(
    v_case_one,
    v_institution_one,
    v_ledger_scope_one,
    v_entitlement_one,
    v_org_a,
    v_ledger_a
  );

  if not coalesce((v_retry->>'alreadyBound')::boolean,false)
     or (v_retry->>'bindingId')::uuid is distinct from v_binding_id
     or (select count(*) from atlas.ledger_entitlement_bindings)<>v_bindings_after then
    raise exception 'Same-target retry was not idempotent: %',v_retry;
  end if;

  -- A different target that the same sponsor Principal also governs must still conflict.
  v_failed := false;
  begin
    perform atlas.bind_implementation_ledger_entitlement_self_api_v1(
      v_case_one,
      v_institution_one,
      v_ledger_scope_one,
      v_entitlement_one,
      v_org_c,
      v_ledger_c
    );
  exception when sqlstate '23505' then
    v_failed := true;
    if position('already bound to a different institutional scope' in sqlerrm)=0 then
      raise exception 'Conflicting retry used unexpected message: %',sqlerrm;
    end if;
  end;
  if not v_failed then
    raise exception 'Entitlement was silently rebound to a different governed Ledger.';
  end if;

  -- Legacy endpoint may report the existing binding, but still may not create identity.
  v_retry := atlas.establish_implementation_organization_scope_self_api_v1(
    v_case_one,
    v_institution_one,
    v_ledger_scope_one,
    v_entitlement_one,
    'Ignored Compatibility Name'
  );
  if not coalesce((v_retry->>'alreadyBound')::boolean,false)
     or (v_retry->>'bindingId')::uuid is distinct from v_binding_id
     or (v_retry->>'organizationId')::uuid is distinct from v_org_a
     or (v_retry->>'ledgerId')::uuid is distinct from v_ledger_a then
    raise exception 'Legacy compatibility endpoint did not report the canonical existing binding: %',v_retry;
  end if;

  if (select count(*) from atlas.organizations)<>v_orgs_before
     or (select count(*) from atlas.ledgers)<>v_ledgers_before
     or (select count(*) from atlas.principals)<>v_principals_before
     or (select count(*) from atlas.principal_ledger_authorities)<>v_authorities_before
     or (select count(*) from atlas.organization_memberships)<>v_memberships_before then
    raise exception 'Legacy compatibility endpoint mutated institutional reality.';
  end if;

  -- Function membrane and implementation dependency proof.
  if to_regprocedure('atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)') is null then
    raise exception 'Canonical commercial Ledger binding API is missing.';
  end if;

  select pg_get_functiondef('atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)'::regprocedure)
  into v_def;
  if position('principal_has_ledger_authority_v1' in v_def)=0
     or position('person_auth_credentials' in v_def)=0
     or position('insert into atlas.ledger_entitlement_bindings' in lower(v_def))=0
     or position('insert into atlas.organizations' in lower(v_def))>0
     or position('insert into atlas.ledgers' in lower(v_def))>0
     or position('insert into atlas.principals' in lower(v_def))>0
     or position('insert into atlas.principal_ledger_authorities' in lower(v_def))>0
     or position('insert into atlas.organization_memberships' in lower(v_def))>0 then
    raise exception 'Canonical commercial binding API violates the identity/commercial boundary.';
  end if;

  select pg_get_functiondef('atlas.establish_implementation_organization_scope_self_api_v1(uuid,uuid,uuid,uuid,text)'::regprocedure)
  into v_def;
  if position('insert into atlas.organizations' in lower(v_def))>0
     or position('insert into atlas.ledgers' in lower(v_def))>0
     or position('Institutional scope must already exist.' in v_def)=0 then
    raise exception 'Historical commercial creator can still manufacture institutional scope.';
  end if;

  if has_function_privilege('anon','atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','atlas.bind_implementation_ledger_entitlement_self_api_v1(uuid,uuid,uuid,uuid,uuid,uuid)','EXECUTE') then
    raise exception 'Canonical commercial binding API grants are incorrect.';
  end if;
end;
$proof$;
