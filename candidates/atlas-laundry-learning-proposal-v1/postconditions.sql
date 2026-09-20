-- Identity-free postconditions for Laundry Learning Proposal v1.

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(
    'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::regprocedure
  ) into v_def;

  if v_def is null then
    raise exception 'Laundry learning proposal function is missing.';
  end if;

  if position('requiredDistinctDates' in v_def)=0
     or position('between 6 and 8' in v_def)=0
     or position('pattern_not_stable' in v_def)=0 then
    raise exception 'Laundry learning threshold/gap law is incomplete.';
  end if;

  if position('rhythm_pattern_proposal' in v_def)=0
     or position('derived_pattern_proposal' in v_def)=0
     or position('household_learning_engine' in v_def)=0 then
    raise exception 'Laundry learning proposal provenance/lifecycle boundary is incomplete.';
  end if;

  if position('derived_pattern_analysis' in v_def)=0
     or position('supportRole' in v_def)=0
     or position('physical_actual' in v_def)=0 then
    raise exception 'Laundry learning Evidence spine is incomplete.';
  end if;

  if position('doesNotCreateRhythm' in v_def)=0
     or position('proposalRequiresAdjudication' in v_def)=0 then
    raise exception 'Laundry learner does not preserve proposal-only authority.';
  end if;

  if position('insert into atlas.household_rhythms' in lower(v_def))>0
     or position('principal_upsert_household_rhythm_api_v1' in v_def)>0
     or position('insert into atlas.tasks' in lower(v_def))>0 then
    raise exception 'Laundry learner improperly materializes Rhythm/task state.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot run Laundry learning proposal analysis.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not run Laundry learning proposal analysis.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Laundry learning proposal candidate.';
  end if;
end
$$;
