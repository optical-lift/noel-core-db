-- Behavioral postconditions for Atlas Person Position Self Projection v0.
-- Intended for the disposable production-schema clone after fixture + candidate SQL.

do $validation$
declare
  v_user_personal constant uuid := '91111111-1111-4111-8111-111111111111'::uuid;
  v_user_one_org constant uuid := '92222222-2222-4222-8222-222222222222'::uuid;
  v_user_multi_org constant uuid := '93333333-3333-4333-8333-333333333333'::uuid;
  v_user_no_person constant uuid := '94444444-4444-4444-8444-444444444444'::uuid;

  v_result jsonb;
  v_personal_person_id uuid;
  v_one_org_person_id uuid;
  v_multi_org_person_id uuid;
  v_def text;
  v_count integer;
begin
  if to_regprocedure('atlas.person_position_self_api_v1()') is null then
    raise exception 'Person Position self projection candidate is missing.';
  end if;

  if has_function_privilege('anon','atlas.person_position_self_api_v1()','EXECUTE') then
    raise exception 'Anonymous role may execute the Person Position self projection.';
  end if;

  if not has_function_privilege('authenticated','atlas.person_position_self_api_v1()','EXECUTE') then
    raise exception 'Authenticated role cannot execute the Person Position self projection.';
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

  select c.person_id
  into v_personal_person_id
  from atlas.person_auth_credentials c
  where c.auth_user_id=v_user_personal
    and c.status='active';

  select c.person_id
  into v_one_org_person_id
  from atlas.person_auth_credentials c
  where c.auth_user_id=v_user_one_org
    and c.status='active';

  select c.person_id
  into v_multi_org_person_id
  from atlas.person_auth_credentials c
  where c.auth_user_id=v_user_multi_org
    and c.status='active';

  if v_personal_person_id is null
     or v_one_org_person_id is null
     or v_multi_org_person_id is null then
    raise exception 'Person Position fixture did not establish all canonical Person roots.';
  end if;

  if v_personal_person_id=v_one_org_person_id
     or v_personal_person_id=v_multi_org_person_id
     or v_one_org_person_id=v_multi_org_person_id then
    raise exception 'Materially different proof humans collapsed to one Person identity.';
  end if;

  -- Negative identity proof: credential presence alone does not manufacture Person Position.
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

  -- Shape B: Personal / Household + one institution + one durable responsibility.
  perform set_config('request.jwt.claim.sub',v_user_one_org::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_user_one_org::text,'role','authenticated')::text,
    true
  );

  v_result := atlas.person_position_self_api_v1();

  if v_result->>'state' <> 'ready'
     or (v_result->'identity'->>'personId')::uuid <> v_one_org_person_id then
    raise exception 'One-org Position did not resolve canonical Person: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'institutionalMemberships','[]'::jsonb)) <> 1 then
    raise exception 'One-org Position did not expose exactly one current membership: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'durableInstitutionalResponsibilities','[]'::jsonb)) <> 1 then
    raise exception 'One-org Position did not expose exactly one current durable responsibility: %',v_result;
  end if;

  if v_result->'durableInstitutionalResponsibilities'->0->>'resolutionState' <> 'established_current' then
    raise exception 'Durable responsibility was not preserved as established_current: %',v_result;
  end if;

  if jsonb_array_length(coalesce(v_result->'ledgerContexts'->'items','[]'::jsonb)) <> 1 then
    raise exception 'One-org Position did not preserve its one root-governing Ledger: %',v_result;
  end if;

  -- Establishing an Organization membership did not establish an employee access seat.
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
