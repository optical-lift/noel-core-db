begin;

do $validation$
declare
  v_case constant uuid := 'f4500000-0000-4000-8000-000000000111'::uuid;
  v_practitioner constant uuid := 'f4500000-0000-4000-8000-000000000001'::uuid;
  v_result jsonb;
  v_def text;
begin
  perform set_config('request.jwt.claim.sub',v_practitioner::text,true);

  -- Before mutation release, discovery remains useful but no action advertises
  -- itself as executable.
  v_result:=public.implementation_initial_scope_options_self_api_v1(
    v_case,null,25
  );

  if v_result->>'state'<>'ready'
     or v_result->>'contractVersion'<>'implementation_initial_scope_options_v2'
     or coalesce((v_result->>'existingAdmissionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'newAdmissionCommandAvailable')::boolean,true)
     or coalesce((v_result->>'canAdmitExistingScope')::boolean,true)
     or coalesce((v_result->>'canEstablishNewOrganization')::boolean,true)
     or jsonb_array_length(coalesce(v_result->'items','[]'::jsonb))<>1
     or jsonb_array_length(coalesce(v_result->'availableEntitlements','[]'::jsonb))<>1 then
    raise exception 'Dormant Initial Scope discovery did not fail closed while retaining readable options: %',v_result;
  end if;

  -- Simulate later authority release. Existence alone is not enough: the
  -- public membranes must also be executable by authenticated callers.
  create function public.admit_existing_implementation_scope_self_api_v1(
    p_implementation_case_id uuid,
    p_ledger_entitlement_id uuid,
    p_organization_id uuid,
    p_ledger_id uuid,
    p_establishment_basis jsonb
  )
  returns jsonb
  language sql
  as $$
    select jsonb_build_object('ok',true)
  $$;

  create function public.establish_new_implementation_scope_self_api_v1(
    p_implementation_case_id uuid,
    p_ledger_entitlement_id uuid,
    p_organization_name text,
    p_establishment_basis jsonb
  )
  returns jsonb
  language sql
  as $$
    select jsonb_build_object('ok',true)
  $$;

  revoke all on function public.admit_existing_implementation_scope_self_api_v1(
    uuid,uuid,uuid,uuid,jsonb
  ) from public,anon,authenticated,service_role;
  revoke all on function public.establish_new_implementation_scope_self_api_v1(
    uuid,uuid,text,jsonb
  ) from public,anon,authenticated,service_role;

  grant execute on function public.admit_existing_implementation_scope_self_api_v1(
    uuid,uuid,uuid,uuid,jsonb
  ) to authenticated;
  grant execute on function public.establish_new_implementation_scope_self_api_v1(
    uuid,uuid,text,jsonb
  ) to authenticated;

  v_result:=public.implementation_initial_scope_options_self_api_v1(
    v_case,null,25
  );

  if not coalesce((v_result->>'existingAdmissionCommandAvailable')::boolean,false)
     or not coalesce((v_result->>'newAdmissionCommandAvailable')::boolean,false)
     or not coalesce((v_result->>'canAdmitExistingScope')::boolean,false)
     or not coalesce((v_result->>'canEstablishNewOrganization')::boolean,false) then
    raise exception 'Initial Scope discovery did not self-activate after governed admission membranes became executable: %',v_result;
  end if;

  revoke execute on function public.establish_new_implementation_scope_self_api_v1(
    uuid,uuid,text,jsonb
  ) from authenticated;

  v_result:=public.implementation_initial_scope_options_self_api_v1(
    v_case,null,25
  );

  if not coalesce((v_result->>'existingAdmissionCommandAvailable')::boolean,false)
     or coalesce((v_result->>'newAdmissionCommandAvailable')::boolean,true)
     or not coalesce((v_result->>'canAdmitExistingScope')::boolean,false)
     or coalesce((v_result->>'canEstablishNewOrganization')::boolean,true) then
    raise exception 'Initial Scope capability signal ignored executable privilege boundary: %',v_result;
  end if;

  select lower(pg_get_functiondef(
    'atlas.implementation_initial_scope_options_self_api_v1(uuid,text,integer)'::regprocedure
  ))
  into v_def;

  if v_def not like '%to_regprocedure%'
     or v_def not like '%has_function_privilege%'
     or v_def not like '%admit_existing_implementation_scope_self_api_v1%'
     or v_def not like '%establish_new_implementation_scope_self_api_v1%' then
    raise exception 'Initial Scope discovery lost dynamic capability detection.';
  end if;

  if regexp_count(v_def,'implementation_initial_scope_options_v2')<>4
     or regexp_count(v_def,'''existingadmissioncommandavailable''')<>4
     or regexp_count(v_def,'''newadmissioncommandavailable''')<>4
     or regexp_count(v_def,'''canadmitexistingscope''')<>4
     or regexp_count(v_def,'''canestablishneworganization''')<>4 then
    raise exception 'Initial Scope discovery response states are not contract-v2 capability-complete.';
  end if;

  if v_def like '%implementation_initial_scope_options_v1%' then
    raise exception 'Initial Scope discovery retained an obsolete v1 response branch.';
  end if;

  if v_def like '%insert into%'
     or v_def like '%update atlas.%'
     or v_def like '%delete from%' then
    raise exception 'Initial Scope capability signal introduced mutation authority.';
  end if;
end;
$validation$;

rollback;
