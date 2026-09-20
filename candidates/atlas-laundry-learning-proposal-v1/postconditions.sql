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
end
$$;

-- Candidate-scoped authenticated RPC custody proof.
do $$
declare
  v_bad_signature text;
begin
  with expected(signature) as (
    values
      ('atlas.propose_personal_laundry_weekly_pattern_self_api_v1()'::text)
  )
  select e.signature
  into v_bad_signature
  from expected e
  left join atlas.authenticated_rpc_registry r
    on r.signature=e.signature
  left join pg_proc p
    on p.oid=to_regprocedure(e.signature)::oid
  where r.signature is null
     or p.oid is null
     or r.review_status<>'active'
     or not r.authenticated_execute_expected
     or not r.security_definer_expected
     or not r.service_execute_expected
     or r.anonymous_execute_expected
     or not has_function_privilege('authenticated',p.oid,'EXECUTE')
     or not has_function_privilege('service_role',p.oid,'EXECUTE')
     or has_function_privilege('anon',p.oid,'EXECUTE')
     or p.prosecdef is distinct from true
  limit 1;

  if v_bad_signature is not null then
    raise exception 'Candidate authenticated RPC custody mismatch: %',v_bad_signature;
  end if;
end
$$;

