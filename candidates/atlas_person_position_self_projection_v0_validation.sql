-- Behavioral postconditions for Atlas Person Position Self Projection v0.
-- Runs in the disposable production-schema clone after the DML-only fixture and candidate migration.

do $validation$
declare
  v_user_personal constant uuid := '91111111-1111-4111-8111-111111111111'::uuid;
  v_user_one_org constant uuid := '92222222-2222-4222-8222-222222222222'::uuid;
  v_user_multi_org constant uuid := '93333333-3333-4333-8333-333333333333'::uuid;
  v_user_no_person constant uuid := '94444444-4444-4444-8444-444444444444'::uuid;

  v_bootstrap jsonb;
  v_org_result jsonb;
  v_result jsonb;
  v_personal_person_id uuid;
  v_one_org_person_id uuid;
  v_multi_org_person_id uuid;
  v_org_id uuid;
  v_membership_id uuid;
  v_ipr_id uuid;
  v_unit_id uuid;
  v_position_id uuid;
  v_responsibility_id uuid;
  v_def text;
  v_count integer;
begin
  if to_regprocedure('atlas.person_position_self_api_v1()') is null then
    raise exception 'Person Position self projection candidate is missing.';
  end if;

  if to_regprocedure('atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)') is null then
    raise exception 'IPR-rooted current durable responsibility read v2 is missing.';
  end if;

  if has_function_privilege('anon','atlas.person_position_self_api_v1()','EXECUTE') then
    raise exception 'Anonymous role may execute the Person Position self projection.';
  end if;

  if not has_function_privilege('authenticated','atlas.person_position_self_api_v1()','EXECUTE') then
    raise exception 'Authenticated role cannot execute the Person Position self projection.';
  end if;

  if has_function_privilege('anon','atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.effective_person_organization_responsibilities_current_v2(uuid,uuid)','EXECUTE') then
    raise exception 'Internal durable-responsibility v2 read leaked directly to browser roles.';
  end if;

  select pg_get_functiondef('atlas.person_position_self_api_v1()'::regprocedure)
  into v_def;

  if position('insert into' in lower(v_def))>0
     or position('delete from' in lower(v_def))>0
     or position('update atlas.' in lower(v_def))>0 then
    raise exception 'Person Position candidate contains a durable mutation path.';
  end if;

  if position('from atlas.company_work_ledger_v1' in lower(v_def))>0
     or position('from atlas.commercial_financial_position_v1' in lower(v_def))>0
     or position('from atlas.organization_spend_position_v1' in lower(v_def))>0 then
    raise exception 'Person Position candidate bypasses bounded Work/Financial read membranes.';
  end if;

  if position('effective_person_organization_responsibilities_current_v2' in v_def)=0 then
    raise exception 'Person Position does not consume the IPR-rooted current durable-responsibility authority.';
  end if;

  -- Negative identity proof: a credential by itself does not become a Person.
  perform set_config('request.jwt.claim.sub',v_user_no_person::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_no_person::text,'role','authenticated')::text,
    true
  );

  v_result := atlas.person_position_self_api_v1();

  if v_result->>'state' <> 'person_required'
     or v_result->'identity' is not null then
    raise exception 'Credential without canonical Person was promoted into Person Position: %',v_result;
  end if;

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

  v_personal_person_id := atlas.current_person_id_v1();

  if v_personal_person_id is null
     or (v_bootstrap->>'principalId') is null
     or (v_bootstrap->>'householdId') is null then
    raise exception 'Personal-only Position proof did not establish Person + Principal + Household: %',v_bootstrap;
  end if;

  v_result := atlas.person_position_self_api_v1();

  if v_result->>'state' <> 'ready'
     or (v_result->'identity'->>'personId')::uuid <> v_personal_person_id then
    raise exception 'Personal-only Position did not resolve canonical Person: %',v_result;
  end if;

  if v_result->'principalRoot' is null
     or jsonb_array_length(coalesce(v_result->'householdContexts','[]'::jsonb)) <> 1 then
    raise exception 'Personal-only Position did not preserve Principal / Household root: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'institutionalMemberships','[]'::jsonb)) <> 0
     or jsonb_array_length(coalesce(v_result->'durableInstitutionalResponsibilities','[]'::jsonb)) <> 0
     or jsonb_array_length(coalesce(v_result->'ledgerContexts'->'items','[]'::jsonb)) <> 0 then
    raise exception 'Personal-only Position invented institutional reality: %',v_result;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements_text(v_result->'unsupportedFacets') f(value)
    where f.value='personal_calendar'
  ) or not exists (
    select 1
    from jsonb_array_elements_text(v_result->'unsupportedFacets') f(value)
    where f.value='personal_finance'
  ) or not exists (
    select 1
    from jsonb_array_elements_text(v_result->'unsupportedFacets') f(value)
    where f.value='private_to_institutional_availability'
  ) then
    raise exception 'Personal-only Position hid required unsupported facets: %',v_result;
  end if;

  -- Shape B: Personal / Household + one institution + IPR-rooted Position responsibility.
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
  v_one_org_person_id := atlas.current_person_id_v1();

  if v_one_org_person_id is null
     or (v_bootstrap->>'principalId') is null
     or (v_bootstrap->>'householdId') is null then
    raise exception 'One-org Position proof did not establish Person + Principal + Household: %',v_bootstrap;
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Person Position One Organization',
    true,
    false
  );

  v_org_id := (v_org_result->'organization'->>'id')::uuid;
  v_membership_id := (v_org_result->'membership'->>'id')::uuid;

  if v_org_id is null or v_membership_id is null then
    raise exception 'One-org Position proof did not establish Organization + compatibility membership: %',v_org_result;
  end if;

  select m.institutional_person_record_id
  into v_ipr_id
  from atlas.organization_memberships m
  where m.id=v_membership_id
    and m.organization_id=v_org_id
    and m.person_id=v_one_org_person_id;

  if v_ipr_id is null then
    raise exception 'Organization Membership was not bridged to Institutional Person Record.';
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

  -- Current architecture: Position Appointment is rooted in Institutional Person Record.
  -- Membership and Identity Subject are deliberately absent on this appointment.
  insert into atlas.organization_position_appointments(
    organization_id,
    position_id,
    identity_subject_id,
    organization_membership_id,
    institutional_person_record_id,
    appointment_kind,
    status,
    metadata
  ) values (
    v_org_id,
    v_position_id,
    null,
    null,
    v_ipr_id,
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

  select count(*)::integer
  into v_count
  from atlas.effective_person_organization_responsibilities_current_v2(
    v_one_org_person_id,
    v_org_id
  ) r
  where r.responsibility_id=v_responsibility_id
    and r.institutional_person_record_id=v_ipr_id
    and r.organization_membership_id is null
    and r.identity_subject_id is null
    and r.resolution_state='established_current';

  if v_count <> 1 then
    raise exception 'IPR-rooted responsibility v2 did not resolve the membership-free/identity-subject-free Position Appointment.';
  end if;

  v_result := atlas.person_position_self_api_v1();

  if v_result->>'state' <> 'ready'
     or (v_result->'identity'->>'personId')::uuid <> v_one_org_person_id then
    raise exception 'One-org Position did not resolve canonical Person: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'institutionalMemberships','[]'::jsonb)) <> 1 then
    raise exception 'One-org Position did not preserve the separate compatibility membership: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'durableInstitutionalResponsibilities','[]'::jsonb)) <> 1 then
    raise exception 'One-org Position did not expose exactly one current durable responsibility: %',v_result;
  end if;

  if (v_result->'durableInstitutionalResponsibilities'->0->>'institutionalPersonRecordId')::uuid <> v_ipr_id
     or v_result->'durableInstitutionalResponsibilities'->0->>'resolutionState' <> 'established_current'
     or v_result->'durableInstitutionalResponsibilities'->0->>'authorityBasis' <> 'atlas.effective_person_organization_responsibilities_current_v2' then
    raise exception 'Person Position did not preserve the IPR-rooted durable-responsibility authority: %',v_result;
  end if;

  if v_result->'durableInstitutionalResponsibilities'->0 ? 'organizationMembershipId'
     or v_result->'durableInstitutionalResponsibilities'->0 ? 'institutionalIdentitySubjectId' then
    raise exception 'Person Position manufactured membership/Identity Subject evidence for an IPR-only Position Appointment: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'ledgerContexts'->'items','[]'::jsonb)) <> 1 then
    raise exception 'One-org Position did not preserve its one root-governing Ledger: %',v_result;
  end if;

  -- A membership alone still does not create employee access/exposure.
  if jsonb_array_length(coalesce(v_result->'institutionalAccess'->'items','[]'::jsonb)) <> 0 then
    raise exception 'Organization membership silently became employee/access authority: %',v_result;
  end if;

  if v_result->'institutionalMemberships'->0->>'knowledgeExposureState' <> 'domain_specific_not_aggregated_v0'
     or coalesce((v_result->'truthBoundary'->>'membershipDoesNotImplyKnowledge')::boolean,false) is not true
     or coalesce((v_result->'truthBoundary'->>'responsibilityDoesNotImplyWork')::boolean,false) is not true then
    raise exception 'One-org Position collapsed membership/responsibility into knowledge or Work: %',v_result;
  end if;

  if v_result->'workPosition'->>'state' <> 'not_aggregated_v0' then
    raise exception 'Person Position unexpectedly aggregated Company Work content: %',v_result;
  end if;

  -- Shape C: one Person / Principal with two Organization + Ledger contexts.
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
  v_multi_org_person_id := atlas.current_person_id_v1();

  if v_multi_org_person_id is null
     or (v_bootstrap->>'principalId') is null
     or (v_bootstrap->>'householdId') is null then
    raise exception 'Multi-org Position proof did not establish Person + Principal + Household: %',v_bootstrap;
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Person Position Organization Alpha',
    true,
    false
  );

  if (v_org_result->'organization'->>'id') is null
     or (v_org_result->'ledger'->>'id') is null then
    raise exception 'Multi-org Position proof did not establish first Organization/Ledger.';
  end if;

  v_org_result := atlas.establish_organization_ledger_self_api_v1(
    'Person Position Organization Beta',
    true,
    false
  );

  if (v_org_result->'organization'->>'id') is null
     or (v_org_result->'ledger'->>'id') is null then
    raise exception 'Multi-org Position proof did not establish second Organization/Ledger.';
  end if;

  if v_personal_person_id=v_one_org_person_id
     or v_personal_person_id=v_multi_org_person_id
     or v_one_org_person_id=v_multi_org_person_id then
    raise exception 'Materially different proof humans collapsed to one Person identity.';
  end if;

  v_result := atlas.person_position_self_api_v1();

  if v_result->>'state' <> 'ready'
     or (v_result->'identity'->>'personId')::uuid <> v_multi_org_person_id then
    raise exception 'Multi-org Position did not preserve the one canonical Person root: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'institutionalMemberships','[]'::jsonb)) <> 2 then
    raise exception 'Multi-org Position did not expose both current institutional contexts: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'ledgerContexts'->'items','[]'::jsonb)) <> 2 then
    raise exception 'Multi-org Position did not expose both root-governing Ledger contexts: %',v_result;
  end if;

  select count(*)::integer
  into v_count
  from atlas.principals p
  where p.person_id=v_multi_org_person_id
    and p.status='active';

  if v_count <> 1 then
    raise exception 'Multi-org proof created % active Principal roots for one Person.',v_count;
  end if;

  if coalesce((v_result->'truthBoundary'->>'personPositionIsProjectionNotTruthDomain')::boolean,false) is not true
     or coalesce((v_result->'truthBoundary'->>'positionDoesNotDecideAttention')::boolean,false) is not true
     or coalesce((v_result->'truthBoundary'->>'positionDoesNotPlaceClock')::boolean,false) is not true then
    raise exception 'Person Position truth boundary is incomplete: %',v_result;
  end if;

  if v_result->'financialInstitutionalPosition'->>'personalFinanceState' <> 'unsupported_v0' then
    raise exception 'Person Position silently reconstructed Personal Money: %',v_result;
  end if;
end;
$validation$;
