begin;

do $validation$
declare
  v_bound_case constant uuid := 'f4200000-0000-4000-8000-000000000111'::uuid;
  v_unbound_case constant uuid := 'f4200000-0000-4000-8000-000000000112'::uuid;
  v_practitioner constant uuid := 'f4200000-0000-4000-8000-000000000001'::uuid;
  v_unrelated_user constant uuid := 'f4200000-0000-4000-8000-000000000003'::uuid;
  v_bound_org constant uuid := 'f4200000-0000-4000-8000-000000000201'::uuid;
  v_outside_org constant uuid := 'f4200000-0000-4000-8000-000000000202'::uuid;
  v_bound_person constant uuid := 'f4200000-0000-4000-8000-000000000211'::uuid;
  v_outside_person constant uuid := 'f4200000-0000-4000-8000-000000000212'::uuid;
  v_bound_position constant uuid := 'f4200000-0000-4000-8000-000000000241'::uuid;
  v_outside_position constant uuid := 'f4200000-0000-4000-8000-000000000242'::uuid;
  v_bound_responsibility constant uuid := 'f4200000-0000-4000-8000-000000000251'::uuid;
  v_outside_responsibility constant uuid := 'f4200000-0000-4000-8000-000000000252'::uuid;
  v_result jsonb;
  v_items jsonb;
  v_item jsonb;
  v_def text;
  v_failed boolean;
begin
  if to_regprocedure(
    'atlas.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)'
  ) is null then
    raise exception 'Internal Reality identity resolver is missing.';
  end if;

  if to_regprocedure(
    'public.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)'
  ) is null then
    raise exception 'Public Reality identity resolver membrane is missing.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  -- 1. The assigned practitioner sees the Organization bound to this case.
  v_result:=public.implementation_reality_identity_options_self_api_v1(
    v_bound_case,'organization','Resolver Bound',12
  );

  if v_result->>'scopeState'<>'bound'
     or (v_result->>'scopeOrganizationCount')::integer<>1 then
    raise exception 'Bound Implementation Case did not resolve a bounded identity scope: %',v_result;
  end if;

  v_items:=coalesce(v_result->'items','[]'::jsonb);

  if jsonb_array_length(v_items)<>1
     or (v_items->0->>'canonicalId')::uuid<>v_bound_org
     or v_items->0->>'kind'<>'organization' then
    raise exception 'Bound Organization resolution is incorrect: %',v_result;
  end if;

  if v_items @> jsonb_build_array(jsonb_build_object('canonicalId',v_outside_org)) then
    raise exception 'Unbound Organization leaked into case-scoped resolver.';
  end if;

  -- 2. Person lookup is case-scoped. The same query must not expose a Person
  -- from an Organization that is not bound to the case.
  v_result:=public.implementation_reality_identity_options_self_api_v1(
    v_bound_case,'person','Anna Resolver',12
  );
  v_items:=coalesce(v_result->'items','[]'::jsonb);

  if jsonb_array_length(v_items)<>1
     or (v_items->0->>'canonicalId')::uuid<>v_bound_person
     or v_items->0->>'kind'<>'person' then
    raise exception 'Bound Person resolution is incorrect or cross-Organization: %',v_result;
  end if;

  if v_items @> jsonb_build_array(jsonb_build_object('canonicalId',v_outside_person)) then
    raise exception 'Unbound Person leaked into case-scoped resolver.';
  end if;

  if v_items->0->>'matchBasis'<>'organization_membership_compatibility' then
    raise exception 'Current production Person resolver did not declare its compatibility basis: %',v_result;
  end if;

  -- 3. Position and Responsibility lookup are bounded by the same case scope.
  v_result:=public.implementation_reality_identity_options_self_api_v1(
    v_bound_case,'organization_position','Farm Steward',12
  );
  v_items:=coalesce(v_result->'items','[]'::jsonb);
  if jsonb_array_length(v_items)<>1
     or (v_items->0->>'canonicalId')::uuid<>v_bound_position
     or v_items @> jsonb_build_array(jsonb_build_object('canonicalId',v_outside_position)) then
    raise exception 'Position resolver crossed the Implementation Case boundary: %',v_result;
  end if;

  v_result:=public.implementation_reality_identity_options_self_api_v1(
    v_bound_case,'organization_responsibility','Production stewardship',12
  );
  v_items:=coalesce(v_result->'items','[]'::jsonb);
  if jsonb_array_length(v_items)<>1
     or (v_items->0->>'canonicalId')::uuid<>v_bound_responsibility
     or v_items @> jsonb_build_array(jsonb_build_object('canonicalId',v_outside_responsibility)) then
    raise exception 'Responsibility resolver crossed the Implementation Case boundary: %',v_result;
  end if;

  -- 4. An assigned but unbound case is explicitly unresolved. It does not fall
  -- back to global Organization search.
  v_result:=public.implementation_reality_identity_options_self_api_v1(
    v_unbound_case,'organization','Resolver',12
  );

  if v_result->>'scopeState'<>'unbound'
     or (v_result->>'scopeOrganizationCount')::integer<>0
     or jsonb_array_length(coalesce(v_result->'items','[]'::jsonb))<>0 then
    raise exception 'Unbound case did not fail closed to an empty resolver scope: %',v_result;
  end if;

  -- 5. Searching for an unbound Organization by its exact label returns no
  -- options even though that Organization exists canonically.
  v_result:=public.implementation_reality_identity_options_self_api_v1(
    v_bound_case,'organization','Resolver Outside Organization',12
  );
  if jsonb_array_length(coalesce(v_result->'items','[]'::jsonb))<>0 then
    raise exception 'Exact label search leaked an Organization outside the case scope: %',v_result;
  end if;

  -- 6. Unsupported semantic kinds fail closed.
  v_failed:=false;
  begin
    perform public.implementation_reality_identity_options_self_api_v1(
      v_bound_case,'customer','Resolver',12
    );
  exception when sqlstate '22023' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Unsupported identity kind was admitted by Reality resolver.';
  end if;

  -- 7. A signed-in but unauthorized/unassigned user cannot inspect the case.
  perform set_config('request.jwt.claim.sub',v_unrelated_user::text,true);
  v_failed:=false;
  begin
    perform public.implementation_reality_identity_options_self_api_v1(
      v_bound_case,'organization','Resolver',12
    );
  exception when sqlstate '42501' then
    v_failed:=true;
  end;
  if not v_failed then
    raise exception 'Unassigned user inspected Implementation Reality identity scope.';
  end if;

  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  -- 8. Browser access exists only through the public authenticated membrane.
  if has_function_privilege(
       'anon',
       'public.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role can execute Reality identity resolver.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'public.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Reality identity resolver membrane.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated role bypasses public Reality identity membrane.';
  end if;

  -- 9. Resolver remains read-only and structurally case-scoped.
  select lower(pg_get_functiondef(
    'atlas.implementation_reality_identity_options_self_api_v1(uuid,text,text,integer)'::regprocedure
  )) into v_def;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Reality identity resolver contains mutation authority.';
  end if;

  if v_def not like '%implementation_practitioner_assigned_to_case_self_v1%'
     or v_def not like '%ledger_entitlement_bindings%'
     or v_def not like '%implementation_case_id=p_implementation_case_id%' then
    raise exception 'Reality identity resolver no longer proves practitioner + case-bound scope.';
  end if;

  if v_def like '%atlas.institutional_person_records%'
     or v_def like '%join atlas.institutional_person_records%' then
    raise exception 'Current production Reality resolver references unreleased Institutional Person Record storage.';
  end if;

  if v_def not like '%organization_membership_compatibility%'
     or v_def not like '%join atlas.organization_memberships%' then
    raise exception 'Current production Reality Person resolver lost its explicit compatibility custody path.';
  end if;
end;
$validation$;

rollback;
