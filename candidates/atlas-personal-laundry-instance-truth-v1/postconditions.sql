-- Identity-free source/schema postconditions for Personal Laundry Instance Truth v1.

do $$
declare
  v_internal_def text;
  v_write_def text;
  v_read_def text;
begin
  select pg_get_functiondef(
    'atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb)'::regprocedure
  ) into v_internal_def;

  select pg_get_functiondef(
    'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'::regprocedure
  ) into v_write_def;

  select pg_get_functiondef(
    'atlas.personal_laundry_kernel_self_api_v2()'::regprocedure
  ) into v_read_def;

  if v_internal_def is null or v_write_def is null or v_read_def is null then
    raise exception 'Laundry V2 authority functions are missing.';
  end if;

  if position('record_current_household_claim_evidence_api_v1' in v_internal_def)=0 then
    raise exception 'Laundry fact adapter is not persisting through Household Claim/Evidence authority.';
  end if;

  if position('record_laundry_instance_fact_internal_v1' in v_write_def)=0 then
    raise exception 'Laundry V2 calibration is not routing facts through the Laundry fact adapter.';
  end if;

  if position('principal_upsert_household_rhythm_api_v1' in v_write_def)>0
     or position('household_rhythms' in v_write_def)>0
     or position('principal_upsert_household_rhythm_api_v1' in v_internal_def)>0
     or position('household_rhythms' in v_internal_def)>0 then
    raise exception 'Laundry V2 improperly carries Household Rhythm mutation authority.';
  end if;

  if position('At least one explicit Laundry fact is required; modelKey alone is not household truth.' in v_write_def)=0 then
    raise exception 'Laundry V2 does not preserve model-vs-household truth boundary.';
  end if;

  if position('responsibilityDoesNotSelectCarrier' in v_write_def)=0
     or position('needGenerationDoesNotCreateRecurrence' in v_write_def)=0
     or position('doesNotCreateClockPlacement' in v_write_def)=0 then
    raise exception 'Laundry V2 authority-boundary return contract is incomplete.';
  end if;

  if position('instanceFacts' in v_read_def)=0
     or position('acceptedInstanceFacts' in v_read_def)=0
     or position('legacyConfigurationIsNotV2FactAuthority' in v_read_def)=0
     or position('rhythmIsSeparateDownstreamAuthority' in v_read_def)=0 then
    raise exception 'Laundry V2 read projection does not preserve fact/Rhythm separation.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not execute Laundry V2 calibration.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Laundry V2 calibration.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.record_laundry_instance_fact_internal_v1(uuid,text,text,jsonb,uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute internal Laundry fact adapter.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.calibrate_personal_laundry_kernel_self_api_v2(jsonb)'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Laundry V2 writer RPC registry entry is missing or incorrect.';
  end if;

  if not exists (
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.personal_laundry_kernel_self_api_v2()'
      and review_status='active'
      and authenticated_execute_expected
      and security_definer_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Laundry V2 reader RPC registry entry is missing or incorrect.';
  end if;
end
$$;
