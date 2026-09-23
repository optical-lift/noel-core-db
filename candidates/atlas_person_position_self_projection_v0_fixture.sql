-- DML-only prerequisite fixture for Atlas Person Position Self Projection v0.
-- Builds three materially different Person shapes in the disposable schema clone.

do $fixture$
declare
  v_user_personal constant uuid := '91111111-1111-4111-8111-111111111111'::uuid;
  v_user_one_org constant uuid := '92222222-2222-4222-8222-222222222222'::uuid;
  v_user_multi_org constant uuid := '93333333-3333-4333-8333-333333333333'::uuid;
  v_user_no_person constant uuid := '94444444-4444-4444-8444-444444444444'::uuid;

  v_bootstrap jsonb;
  v_org_result jsonb;
  v_org_id uuid;
  v_membership_id uuid;
  v_identity_subject_id uuid;
  v_unit_id uuid;
  v_position_id uuid;
  v_responsibility_id uuid;
begin
  insert into auth.users(id,email,created_at,updated_at)
  values
    (v_user_personal,'person-position-personal@example.test',now(),now()),
    (v_user_one_org,'person-position-one-org@example.test',now(),now()),
    (v_user_multi_org,'person-position-multi-org@example.test',now(),now()),
    (v_user_no_person,'person-position-no-person@example.test',now(),now());

  insert into atlas.personal_atlas_purchases(
    provider,
    provider_checkout_session_id,
    provider_subscription_id,
    purchaser_email,
    offer_key,
    purchase_state,
    purchased_at,
    metadata
  ) values
    (
      'stripe',
      'cs_person_position_personal',
      'sub_person_position_personal',
      'person-position-personal@example.test',
      'personal_atlas',
      'active',
      now(),
      '{}'::jsonb
    ),
    (
      'stripe',
      'cs_person_position_one_org',
      'sub_person_position_one_org',
      'person-position-one-org@example.test',
      'personal_atlas',
      'active',
      now(),
      '{}'::jsonb
    ),
    (
      'stripe',
      'cs_person_position_multi_org',
      'sub_person_position_multi_org',
      'person-position-multi-org@example.test',
      'personal_atlas',
      'active',
      now(),
      '{}'::jsonb
    );

  -- Shape A: Personal / Household only.
  perform set_config('request.jwt.claim.sub',v_user_personal::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_personal::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Person Position Personal',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null
     or (v_bootstrap->>'householdId') is null then
    raise exception 'Personal-only Person Position fixture did not bootstrap Principal + Household.';
  end if;

  -- Shape B: Personal / Household + one institution + one durable responsibility.
  perform set_config('request.jwt.claim.sub',v_user_one_org::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_one_org::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Person Position One Org',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null
     or (v_bootstrap->>'householdId') is null then
    raise exception 'One-org Person Position fixture did not bootstrap Principal + Household.';
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Person Position One Organization',
    true,
    false
  );

  v_org_id := (v_org_result->'organization'->>'id')::uuid;
  v_membership_id := (v_org_result->'membership'->>'id')::uuid;

  if v_org_id is null or v_membership_id is null then
    raise exception 'One-org Person Position fixture did not establish Organization + owner membership.';
  end if;

  select m.identity_subject_id
  into v_identity_subject_id
  from atlas.organization_memberships m
  where m.id=v_membership_id
    and m.organization_id=v_org_id;

  if v_identity_subject_id is null then
    raise exception 'One-org Person Position membership lacks institutional identity subject.';
  end if;

  select u.id
  into v_unit_id
  from atlas.organization_units u
  where u.organization_id=v_org_id
    and u.status='active'
  order by u.created_at,u.id
  limit 1;

  if v_unit_id is null then
    insert into atlas.organization_units(
      organization_id,
      stable_key,
      name,
      unit_kind
    ) values (
      v_org_id,
      'person_position_primary',
      'Primary',
      'operating_business'
    )
    returning id into v_unit_id;
  end if;

  insert into atlas.organization_positions(
    organization_id,
    organization_unit_id,
    stable_key,
    display_title,
    position_kind,
    metadata
  ) values (
    v_org_id,
    v_unit_id,
    'position_holder',
    'Position Holder',
    'operations',
    '{}'::jsonb
  )
  returning id into v_position_id;

  insert into atlas.organization_position_appointments(
    organization_id,
    position_id,
    identity_subject_id,
    organization_membership_id,
    appointment_kind,
    status,
    metadata
  ) values (
    v_org_id,
    v_position_id,
    v_identity_subject_id,
    v_membership_id,
    'primary',
    'active',
    '{}'::jsonb
  );

  insert into atlas.organization_responsibilities(
    organization_id,
    stable_key,
    name,
    responsibility_kind,
    metadata
  ) values (
    v_org_id,
    'position_proof_responsibility',
    'Position proof responsibility',
    'stewardship',
    '{}'::jsonb
  )
  returning id into v_responsibility_id;

  insert into atlas.organization_position_responsibilities(
    position_id,
    responsibility_id,
    relationship_kind
  ) values (
    v_position_id,
    v_responsibility_id,
    'accountable'
  );

  insert into atlas.organization_responsibility_scopes(
    organization_id,
    responsibility_id,
    scope_kind,
    scope_id,
    relation_kind,
    metadata
  ) values (
    v_org_id,
    v_responsibility_id,
    'organization_unit',
    v_unit_id::text,
    'stewards',
    '{}'::jsonb
  );

  -- Shape C: Personal / Household + two independent institutional/Ledger contexts.
  perform set_config('request.jwt.claim.sub',v_user_multi_org::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_multi_org::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Person Position Multi Org',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null
     or (v_bootstrap->>'householdId') is null then
    raise exception 'Multi-org Person Position fixture did not bootstrap Principal + Household.';
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Person Position Organization Alpha',
    true,
    false
  );

  if (v_org_result->'organization'->>'id') is null
     or (v_org_result->'ledger'->>'id') is null then
    raise exception 'Multi-org Person Position fixture did not establish first Organization/Ledger.';
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Person Position Organization Beta',
    true,
    false
  );

  if (v_org_result->'organization'->>'id') is null
     or (v_org_result->'ledger'->>'id') is null then
    raise exception 'Multi-org Person Position fixture did not establish second Organization/Ledger.';
  end if;
end;
$fixture$;
