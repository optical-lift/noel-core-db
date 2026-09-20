-- Identity-free postconditions for Laundry Actual -> Consequence Resolution v1.

do $$
declare
  v_actual_def text;
  v_authority_def text;
  v_guard_def text;
  v_resolver_def text;
begin
  select pg_get_functiondef(
    'atlas.record_personal_laundry_actual_self_api_v1(jsonb)'::regprocedure
  ) into v_actual_def;

  select pg_get_functiondef(
    'atlas.personal_laundry_actual_resolution_authority_v1(uuid,uuid,uuid)'::regprocedure
  ) into v_authority_def;

  select pg_get_functiondef(
    'atlas.guard_personal_laundry_consequence_resolution_actual_v1()'::regprocedure
  ) into v_guard_def;

  select pg_get_functiondef(
    'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)'::regprocedure
  ) into v_resolver_def;

  if v_actual_def is null
     or v_authority_def is null
     or v_guard_def is null
     or v_resolver_def is null then
    raise exception 'Laundry actual-resolution authority functions are missing.';
  end if;

  if position('physical_process_actual' in v_actual_def)=0
     or position('process_actual' in v_actual_def)=0
     or position('actualIsNotTaskCompletion' in v_actual_def)=0 then
    raise exception 'Laundry actual writer boundary is incomplete.';
  end if;

  if position('entered_washing' in v_authority_def)=0
     or position('laundry_cycle_needed' in v_authority_def)=0
     or position('predates the consequence requirement' in v_authority_def)=0 then
    raise exception 'Laundry actual resolution law is incomplete.';
  end if;

  if position('resolutionActualClaimId' in v_guard_def)=0
     or position('canonical physical-actual envelope' in v_guard_def)=0 then
    raise exception 'Laundry resolution persistence guard is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_state_events'
      and t.tgname='personal_laundry_consequence_resolution_actual_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Laundry consequence-resolution actual guard trigger is missing.';
  end if;

  if position('record_person_life_state_api_v1' in v_resolver_def)=0
     or position('taskCompletionDidNotResolveRequirement' in v_resolver_def)=0 then
    raise exception 'Laundry resolver does not reuse governed Person Life resolution authority.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.record_personal_laundry_actual_self_api_v1(jsonb)'::regprocedure,
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated Laundry actual/resolution APIs are unavailable.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.record_personal_laundry_actual_self_api_v1(jsonb)'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.resolve_personal_laundry_consequence_from_actual_self_api_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not use Laundry actual/resolution APIs.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Laundry actual-resolution candidate.';
  end if;
end
$$;
