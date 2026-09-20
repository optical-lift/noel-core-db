-- Identity-free postconditions for Principal Consequence Clock Characterization v1.

do $$
declare
  v_write_def text;
  v_admission_def text;
begin
  select pg_get_functiondef(
    'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)'::regprocedure
  ) into v_write_def;

  select pg_get_functiondef(
    'atlas.person_life_consequence_clock_admission_state_v1(uuid,uuid)'::regprocedure
  ) into v_admission_def;

  if v_write_def is null or v_admission_def is null then
    raise exception 'Principal consequence Clock characterization functions are missing.';
  end if;

  if position('record_person_claim_evidence_api_v1' in v_write_def)=0 then
    raise exception 'Clock characterization is not persisted through universal person Claim/Evidence.';
  end if;

  if position('missingRelevanceStartDoesNotMeanOpenNow' in v_write_def)=0
     or position('deadlineAloneDoesNotEstablishCurrentRelevance' in v_write_def)=0
     or position('doesNotCreateClockCandidate' in v_write_def)=0 then
    raise exception 'Clock characterization truth boundary is incomplete.';
  end if;

  if position('principal_carrier_required' in v_admission_def)=0
     or position('execution_readiness_required' in v_admission_def)=0
     or position('clock_characterization_incomplete' in v_admission_def)=0 then
    raise exception 'Clock admission blocker contract is incomplete.';
  end if;

  if position('principal_clock_candidates_v1' in v_write_def)>0
     or position('principal_clock_candidates_v1' in v_admission_def)>0 then
    raise exception 'Characterization candidate improperly mutates or depends on live Clock candidate inventory.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot record owned consequence Clock characterization.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.person_life_consequence_clock_admission_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot read owned consequence Clock admission state.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.record_person_life_consequence_clock_characterization_self_api_v1(uuid,jsonb)'::regprocedure,
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.person_life_consequence_clock_admission_self_api_v1(uuid)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not access consequence Clock characterization APIs.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Clock characterization candidate.';
  end if;
end
$$;
