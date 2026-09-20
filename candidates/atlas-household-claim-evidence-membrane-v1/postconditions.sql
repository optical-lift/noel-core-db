-- Identity-free source/schema postconditions for Household Claim/Evidence membrane v1.

do $$
declare
  v_write_def text;
  v_read_def text;
begin
  select pg_get_functiondef(
    'atlas.record_current_household_claim_evidence_api_v1(jsonb)'::regprocedure
  ) into v_write_def;

  select pg_get_functiondef(
    'atlas.current_household_claim_evidence_state_api_v1()'::regprocedure
  ) into v_read_def;

  if v_write_def is null or v_read_def is null then
    raise exception 'Household Claim/Evidence APIs are missing.';
  end if;

  if position('principal_current_household_id_v1' in v_write_def)=0
     or position('principal_current_household_id_v1' in v_read_def)=0 then
    raise exception 'Household custody is not derived from current Principal Household.';
  end if;

  if position('scope_kind=''household''' in v_write_def)=0
     or position('scope_kind=''household''' in v_read_def)=0 then
    raise exception 'Household scope is not fixed in the membrane.';
  end if;

  if position('Household Claim/Evidence subjects must use the household domain.' in v_write_def)=0 then
    raise exception 'Household subject-domain boundary is missing.';
  end if;

  if position('doesNotCreateClockPlacement' in v_write_def)=0
     or position('doesNotCreateRhythm' in v_write_def)=0
     or position('doesNotSelectCarrier' in v_write_def)=0 then
    raise exception 'Write truth-boundary contract is incomplete.';
  end if;

  if has_function_privilege('anon',
       'atlas.record_current_household_claim_evidence_api_v1(jsonb)'::regprocedure,
       'EXECUTE') then
    raise exception 'Anonymous role must not execute Household Claim/Evidence writer.';
  end if;

  if not has_function_privilege('authenticated',
       'atlas.record_current_household_claim_evidence_api_v1(jsonb)'::regprocedure,
       'EXECUTE') then
    raise exception 'Authenticated role cannot execute Household Claim/Evidence writer.';
  end if;

  if not exists (
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.record_current_household_claim_evidence_api_v1(jsonb)'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Household Claim/Evidence writer RPC registry entry is missing or incorrect.';
  end if;

  if not exists (
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.current_household_claim_evidence_state_api_v1()'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Household Claim/Evidence reader RPC registry entry is missing or incorrect.';
  end if;
end
$$;
