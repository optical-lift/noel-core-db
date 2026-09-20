-- Identity-free source/schema postconditions for Person Life Consequence -> Principal Clock Candidate v1.

do $$
declare
  v_candidate_view text;
  v_inventory_view text;
  v_arb text;
  v_api text;
begin
  select pg_get_viewdef(
    'atlas.principal_person_life_consequence_clock_candidates_v1'::regclass,
    true
  ) into v_candidate_view;

  select pg_get_viewdef(
    'atlas.principal_clock_candidates_v2'::regclass,
    true
  ) into v_inventory_view;

  select pg_get_functiondef(
    'atlas.principal_clock_arbitration_v2(uuid,date,timestamptz)'::regprocedure
  ) into v_arb;

  select pg_get_functiondef(
    'atlas.principal_clock_api_v2(date,timestamptz)'::regprocedure
  ) into v_api;

  if v_candidate_view is null
     or v_inventory_view is null
     or v_arb is null
     or v_api is null then
    raise exception 'Principal Clock V2 consequence candidate contracts are missing.';
  end if;

  if position('carrier_state = ''established''' in v_candidate_view)=0
     or position('execution_readiness = ''ready''' in v_candidate_view)=0
     or position('clock_characterization' in v_candidate_view)=0
     or position('person_life_consequence_clock_characterization_completeness_v1' in v_candidate_view)=0 then
    raise exception 'Person Life consequence Clock candidate admission is incomplete.';
  end if;

  if position('principal_clock_candidates_v1' in v_inventory_view)=0
     or position('principal_person_life_consequence_clock_candidates_v1' in v_inventory_view)=0 then
    raise exception 'Principal Clock V2 inventory does not preserve V1 plus the new admitted source.';
  end if;

  if position('principal_clock_candidates_v2' in v_arb)=0
     or position('principal_clock_candidates_v1' in v_arb)>0 then
    raise exception 'Principal Clock arbitration V2 is not isolated to the V2 candidate inventory.';
  end if;

  if position('principal_clock_arbitration_v2' in v_api)=0
     or position('personLifeConsequenceCandidatesRequireExplicitAdmission' in v_api)=0 then
    raise exception 'Principal Clock API V2 is not bound to V2 arbitration/admission truth.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.principal_clock_api_v2(date,timestamptz)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role cannot execute Principal Clock API V2.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.principal_clock_api_v2(date,timestamptz)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Anonymous role must not execute Principal Clock API V2.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.principal_clock_arbitration_v2(uuid,date,timestamptz)'::regprocedure,
       'EXECUTE'
     ) then
    raise exception 'Authenticated role must not directly execute internal Principal Clock arbitration V2.';
  end if;

  if exists(select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drift exists after Principal Clock V2 candidate.';
  end if;
end
$$;
