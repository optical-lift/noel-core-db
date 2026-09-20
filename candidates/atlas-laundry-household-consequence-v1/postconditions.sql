-- Identity-free source/schema postconditions for Laundry Household Evidence -> Person Consequence v1.

do $$
declare
  v_policy_def text;
  v_definition_guard_def text;
  v_snapshot_def text;
  v_household_guard_def text;
  v_eval_def text;
begin
  select pg_get_functiondef(
    'atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(uuid,uuid)'::regprocedure
  ) into v_policy_def;

  select pg_get_functiondef(
    'atlas.guard_personal_laundry_consequence_definition_authority_v1()'::regprocedure
  ) into v_definition_guard_def;

  select pg_get_functiondef(
    'atlas.household_consequence_evidence_snapshot_v1(uuid,uuid)'::regprocedure
  ) into v_snapshot_def;

  select pg_get_functiondef(
    'atlas.guard_household_consequence_evaluation_authority_v1()'::regprocedure
  ) into v_household_guard_def;

  select pg_get_functiondef(
    'atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)'::regprocedure
  ) into v_eval_def;

  if v_policy_def is null
     or v_definition_guard_def is null
     or v_snapshot_def is null
     or v_household_guard_def is null
     or v_eval_def is null then
    raise exception 'Laundry Household consequence authority functions are missing.';
  end if;

  if position('accumulation_threshold' in v_policy_def)=0
     or position('ready_for_cycle' in v_policy_def)=0
     or position('laundry_cycle_needed' in v_policy_def)=0
     or position('unsupportedNeedGenerationIsNotGuessed' in v_policy_def)=0 then
    raise exception 'Laundry deterministic consequence policy is incomplete.';
  end if;

  if position('engine_packet->''policies'' is distinct from v_policy->''policies''' in v_definition_guard_def)=0 then
    raise exception 'Laundry consequence definition guard does not enforce deterministic packet policy.';
  end if;

  if position('scope_kind=''household''' in v_snapshot_def)=0
     or position('current same-subject Claim' in v_snapshot_def)=0 then
    raise exception 'Household consequence Evidence snapshot boundary is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_state_events'
      and t.tgname='person_consequence_evaluation_authority_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Person consequence evaluation guard trigger is missing after split.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='person_life_state_events'
      and t.tgname='household_consequence_evaluation_authority_guard_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Household consequence evaluation guard trigger is missing.';
  end if;

  if position('evidenceScopeKind' in v_household_guard_def)=0
     or position('policyDerivedNotCallerSupplied' in v_eval_def)=0
     or position('doesNotCreateClockPlacement' in v_eval_def)=0 then
    raise exception 'Laundry Household consequence evaluation authority boundary is incomplete.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.personal_laundry_consequence_policy_from_need_generation_claim_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute Laundry deterministic policy adapter.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.household_consequence_evidence_snapshot_v1(uuid,uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute Household consequence snapshot builder.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.ensure_personal_laundry_consequence_definition_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot ensure Laundry consequence definition.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.evaluate_personal_laundry_consequence_from_household_evidence_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot evaluate Laundry consequence from Household Evidence.';
  end if;

  if exists (
    select 1
    from atlas.authenticated_rpc_registry_drift_v1()
  ) then
    raise exception 'Authenticated RPC registry drift exists after Laundry Household consequence candidate.';
  end if;
end
$$;
