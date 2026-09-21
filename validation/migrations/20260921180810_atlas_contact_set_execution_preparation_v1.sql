begin;

do $validation$
declare
  v_search jsonb;
  v_prepared jsonb;
  v_entity_count_before integer;
  v_entity_count_after integer;
  v_candidate_count integer;
  v_complete_count integer;
  v_gap_count integer;
  v_relationship_count integer;
  v_role_count integer;
begin
  if to_regclass('atlas.contact_set_execution_runs') is null then
    raise exception 'contact_set_execution_runs table is missing';
  end if;
  if to_regprocedure('atlas.shared_directory_target_search_service_v1(uuid,jsonb,jsonb,text[],integer)') is null then
    raise exception 'typed target search service is missing';
  end if;
  if to_regprocedure('atlas.prepare_contact_set_execution_service_v1(uuid)') is null then
    raise exception 'contact-set execution preparation service is missing';
  end if;

  select count(*)::integer into v_entity_count_before
  from local_intel.entities
  where id in (
    'f3000000-0000-4000-8000-000000000121'::uuid,
    'f3000000-0000-4000-8000-000000000122'::uuid,
    'f3000000-0000-4000-8000-000000000131'::uuid,
    'f3000000-0000-4000-8000-000000000132'::uuid
  );

  v_search:=atlas.shared_directory_target_search_service_v1(
    'f3000000-0000-4000-8000-000000000101'::uuid,
    '{
      "description":"bank people",
      "organizationKinds":["bank"],
      "namedOrganizations":[],
      "personFunctions":["decision_adjacent"],
      "titles":[],
      "include":[],
      "exclude":[],
      "similaritySeedEntityIds":[]
    }'::jsonb,
    '{"mode":"explicit","placeLabels":["Marshfield","Springfield"],"basis":"literal request"}'::jsonb,
    array['email','name','title','organization']::text[],
    50
  );

  v_candidate_count:=coalesce((v_search->>'candidateCount')::integer,-1);
  v_complete_count:=coalesce((v_search->>'completeCandidateCount')::integer,-1);

  if v_candidate_count<>2 then
    raise exception 'Expected two known bank people; got %: %',v_candidate_count,v_search;
  end if;
  if v_complete_count<>1 then
    raise exception 'Expected one fully covered known person; got %: %',v_complete_count,v_search;
  end if;

  if not exists(
    select 1 from jsonb_array_elements(v_search->'researchTargets') x
    where x->>'gapKind'='entity_field_gap'
      and (x->>'entityId')::uuid='f3000000-0000-4000-8000-000000000132'::uuid
      and x->'missingFields' ? 'email'
  ) then
    raise exception 'Known person missing email did not produce entity_field_gap';
  end if;

  if not exists(
    select 1 from jsonb_array_elements(v_search->'researchTargets') x
    where x->>'gapKind'='organization_person_gap'
      and (x->>'organizationEntityId')::uuid='f3000000-0000-4000-8000-000000000122'::uuid
  ) then
    raise exception 'Known qualifying bank with no person did not produce organization_person_gap';
  end if;

  v_prepared:=atlas.prepare_contact_set_execution_service_v1(
    'f3000000-0000-4000-8000-000000000161'::uuid
  );

  if v_prepared->>'executionState'<>'needs_acquisition' then
    raise exception 'Preparation should require acquisition: %',v_prepared;
  end if;

  v_gap_count:=coalesce((v_prepared#>>'{gaps,gapCount}')::integer,-1);
  if v_gap_count<>3 then
    raise exception 'Expected field + person + population gaps; got %: %',v_gap_count,v_prepared;
  end if;

  if coalesce((v_prepared#>>'{gaps,populationGap}')::boolean,false) is not true then
    raise exception 'Requested count shortfall was not preserved as population gap';
  end if;

  select count(*)::integer into v_relationship_count
  from atlas.external_relationships r
  join atlas.identity_subject_external_identifiers i
    on i.organization_id=r.organization_id
   and i.subject_id=r.subject_id
   and i.provider_key='local_intel'
   and i.identifier_type='entity_id'
   and i.is_current
  where r.organization_id='f3000000-0000-4000-8000-000000000101'::uuid
    and i.identifier_normalized in (
      'f3000000-0000-4000-8000-000000000131',
      'f3000000-0000-4000-8000-000000000132'
    );

  if v_relationship_count<>2 then
    raise exception 'Both known canonical people should be attached to requesting Ledger; found %',v_relationship_count;
  end if;

  select count(*)::integer into v_role_count
  from atlas.external_relationship_roles rr
  join atlas.external_relationships r on r.id=rr.external_relationship_id
  where r.organization_id='f3000000-0000-4000-8000-000000000101'::uuid
    and rr.role_key='contact'
    and rr.role_state='active';

  if v_role_count<>2 then
    raise exception 'Expected two private contact roles; found %',v_role_count;
  end if;

  select count(*)::integer into v_entity_count_after
  from local_intel.entities
  where id in (
    'f3000000-0000-4000-8000-000000000121'::uuid,
    'f3000000-0000-4000-8000-000000000122'::uuid,
    'f3000000-0000-4000-8000-000000000131'::uuid,
    'f3000000-0000-4000-8000-000000000132'::uuid
  );

  if v_entity_count_after<>v_entity_count_before then
    raise exception 'Execution preparation changed Shared Intelligence entity count';
  end if;

  if not exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='contact_set_execution_runs' and c.relrowsecurity
  ) then
    raise exception 'Execution run table RLS is not enabled';
  end if;

  if exists(
    select 1 from information_schema.role_table_grants
    where table_schema='atlas'
      and table_name='contact_set_execution_runs'
      and grantee in ('anon','authenticated','service_role')
  ) then
    raise exception 'Execution run table leaked direct application-role grants';
  end if;

  if has_function_privilege('authenticated','atlas.prepare_contact_set_execution_service_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated role unexpectedly has direct preparation service access';
  end if;
  if not has_function_privilege('service_role','atlas.prepare_contact_set_execution_service_v1(uuid)','EXECUTE') then
    raise exception 'Service role lacks preparation service execution';
  end if;
  if not has_function_privilege('authenticated','atlas.contact_set_execution_run_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated role lacks execution run self read';
  end if;
end;
$validation$;

rollback;
