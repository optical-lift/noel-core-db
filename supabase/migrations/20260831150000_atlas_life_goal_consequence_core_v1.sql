-- Atlas Life Goal + State Consequence Core v1
--
-- Extracts the reusable state reducers from farm-bound persistence. These
-- functions operate only on source-custodied JSON packets/evidence. They do not
-- read or write goals, tasks, farms, Clock placements, or consequence instances.
--
-- Existing farm engines remain unchanged. A later compatibility adapter may
-- delegate their domain-provider results into these pure reducers.

begin;

create or replace function atlas.evaluate_life_goal_state_v1(
  p_goal_packet jsonb,
  p_requirement_results jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_requirement jsonb;
  v_result jsonb;
  v_evaluated jsonb := '[]'::jsonb;
  v_ambiguities jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_key text;
  v_phase text;
  v_state text;
  v_required boolean;
  v_subject_ref text;
  v_total integer := 0;
  v_satisfied integer := 0;
  v_partial integer := 0;
  v_waiting integer := 0;
  v_unmet integer := 0;
  v_unknown integer := 0;
  v_gate_total integer := 0;
  v_gate_satisfied integer := 0;
  v_gate_unknown integer := 0;
  v_progress_signal integer := 0;
  v_realize_total integer := 0;
  v_realize_satisfied integer := 0;
  v_realize_unknown integer := 0;
  v_goal_state text;
begin
  if p_goal_packet is null
     or jsonb_typeof(p_goal_packet) <> 'object'
     or p_goal_packet->>'contractVersion' <> 'life_goal_packet_v1' then
    raise exception 'life_goal_packet_v1 is required.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_goal_packet->'requirements','[]'::jsonb)) <> 'array' then
    raise exception 'goal packet requirements must be an array.' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_requirement_results,'[]'::jsonb)) <> 'array' then
    raise exception 'requirement results must be an array.' using errcode='22023';
  end if;

  v_subject_ref := concat_ws(':',
    p_goal_packet->'subject'->>'domain',
    p_goal_packet->'subject'->>'kind',
    p_goal_packet->'subject'->>'id'
  );

  for v_requirement in
    select value from jsonb_array_elements(coalesce(p_goal_packet->'requirements','[]'::jsonb))
  loop
    v_index := v_index + 1;
    v_key := nullif(btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key','')),'');
    if v_key is null then
      v_key := v_subject_ref || ':goal_requirement:' || v_index::text;
    end if;

    v_phase := coalesce(nullif(btrim(v_requirement->>'phase'),''),'gate');
    if v_phase not in ('gate','progress','realize') then
      raise exception 'Unsupported goal requirement phase: %', v_phase using errcode='22023';
    end if;

    if v_requirement ? 'required' then
      if jsonb_typeof(v_requirement->'required') <> 'boolean' then
        raise exception 'goal requirement required must be boolean when supplied.' using errcode='22023';
      end if;
      v_required := (v_requirement->>'required')::boolean;
    else
      v_required := true;
    end if;

    v_result := null;
    select value into v_result
    from jsonb_array_elements(coalesce(p_requirement_results,'[]'::jsonb))
    where value->>'requirementKey' = v_key
    limit 1;

    v_state := coalesce(nullif(v_result->>'state',''),'unknown');
    if v_state not in ('satisfied','partial','waiting','unmet','unknown') then
      v_ambiguities := v_ambiguities || jsonb_build_array(jsonb_build_object(
        'key','unsupported_requirement_result_state',
        'requirementKey',v_key,
        'receivedState',v_state
      ));
      v_state := 'unknown';
    end if;

    v_evaluated := v_evaluated || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'requirementKey',v_key,
      'label',coalesce(v_requirement->>'label',v_key),
      'phase',v_phase,
      'required',v_required,
      'state',v_state,
      'detail',v_result->'detail',
      'source',v_result->'source',
      'sourceRequirement',v_requirement,
      'sourceResult',v_result
    )));

    if not v_required then
      continue;
    end if;

    v_total := v_total + 1;
    if v_state='satisfied' then v_satisfied:=v_satisfied+1; end if;
    if v_state='partial' then v_partial:=v_partial+1; end if;
    if v_state='waiting' then v_waiting:=v_waiting+1; end if;
    if v_state='unmet' then v_unmet:=v_unmet+1; end if;
    if v_state='unknown' then v_unknown:=v_unknown+1; end if;

    if v_phase='gate' then
      v_gate_total:=v_gate_total+1;
      if v_state='satisfied' then v_gate_satisfied:=v_gate_satisfied+1; end if;
      if v_state='unknown' then v_gate_unknown:=v_gate_unknown+1; end if;
    elsif v_phase='progress' then
      if v_state in ('satisfied','partial') then v_progress_signal:=v_progress_signal+1; end if;
    elsif v_phase='realize' then
      v_realize_total:=v_realize_total+1;
      if v_state='satisfied' then
        v_realize_satisfied:=v_realize_satisfied+1;
        v_progress_signal:=v_progress_signal+1;
      elsif v_state='partial' then
        v_progress_signal:=v_progress_signal+1;
      elsif v_state='unknown' then
        v_realize_unknown:=v_realize_unknown+1;
      end if;
    end if;
  end loop;

  v_goal_state := case
    when v_total=0 then 'defined'
    when v_realize_total>0 and v_realize_satisfied=v_realize_total and v_realize_unknown=0 then 'realized'
    when v_gate_total>0 and v_gate_satisfied=v_gate_total and v_gate_unknown=0 then
      case when v_progress_signal>0 or v_partial>0 then 'in_production' else 'playable' end
    when v_progress_signal>0 or v_partial>0 then 'in_production'
    when v_satisfied>0 or v_waiting>0 or v_unknown>0 then 'tracking'
    else 'locked'
  end;

  return jsonb_build_object(
    'contractVersion','life_goal_evaluation_v1',
    'scope',p_goal_packet->'scope',
    'subject',p_goal_packet->'subject',
    'explicitUserEnd',p_goal_packet->'explicitUserEnd',
    'state',v_goal_state,
    'progress',jsonb_build_object(
      'satisfied',v_satisfied,
      'partial',v_partial,
      'waiting',v_waiting,
      'unmet',v_unmet,
      'unknown',v_unknown,
      'total',v_total
    ),
    'phaseSummary',jsonb_build_object(
      'gateTotal',v_gate_total,
      'gateSatisfied',v_gate_satisfied,
      'gateUnknown',v_gate_unknown,
      'progressSignals',v_progress_signal,
      'realizeTotal',v_realize_total,
      'realizeSatisfied',v_realize_satisfied,
      'realizeUnknown',v_realize_unknown
    ),
    'requirements',v_evaluated,
    'ambiguities',coalesce(p_goal_packet->'ambiguities','[]'::jsonb) || v_ambiguities,
    'truthBoundary',jsonb_build_object(
      'requirementResultsAreInputsNotInferences',true,
      'missingRequirementResultRemainsUnknown',true,
      'doesNotManufactureEvidence',true,
      'doesNotInventRequirements',true,
      'doesNotSelectNextTask',true,
      'doesNotReleaseWork',true,
      'doesNotArbitrateClock',true,
      'farmNearThresholdPolicyNotPartOfGenericCore',true
    ),
    'provenance',jsonb_build_object(
      'evaluator','atlas.evaluate_life_goal_state_v1',
      'sourceGoalPacket',p_goal_packet->'provenance'
    )
  );
end;
$$;

comment on function atlas.evaluate_life_goal_state_v1(jsonb,jsonb) is
  'Generic read-only Goal reducer. Domain providers submit independently evaluated requirement results; missing results remain unknown. The core derives goal state without querying farms/tasks or selecting work.';

create or replace function atlas.evaluate_life_state_consequence_policies_v1(
  p_snapshot jsonb,
  p_policies jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare
  v_policy jsonb;
  v_matches jsonb := '[]'::jsonb;
  v_active boolean;
  v_selector jsonb;
  v_state_match jsonb;
  v_role text;
  v_action_spec jsonb;
  v_carrier text;
  v_stable_key text;
  v_priority integer;
  v_index integer := 0;
begin
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then
    raise exception 'state consequence snapshot must be an object.' using errcode='22023';
  end if;
  if p_policies is null or jsonb_typeof(p_policies) <> 'array' then
    raise exception 'state consequence policies must be an array.' using errcode='22023';
  end if;

  for v_policy in select value from jsonb_array_elements(p_policies)
  loop
    v_index:=v_index+1;
    if jsonb_typeof(v_policy) <> 'object' then
      raise exception 'state consequence policy % must be an object.', v_index using errcode='22023';
    end if;

    if v_policy ? 'active' then
      if jsonb_typeof(v_policy->'active') <> 'boolean' then
        raise exception 'state consequence policy active must be boolean when supplied.' using errcode='22023';
      end if;
      v_active := (v_policy->>'active')::boolean;
    else
      v_active := true;
    end if;
    if not v_active then continue; end if;

    v_stable_key:=nullif(btrim(coalesce(v_policy->>'stableKey',v_policy->>'stable_key','')),'');
    if v_stable_key is null then
      raise exception 'state consequence policy stableKey is required.' using errcode='22023';
    end if;

    v_selector:=coalesce(v_policy->'subjectSelector',v_policy->'subject_selector','{}'::jsonb);
    v_state_match:=coalesce(v_policy->'stateMatch',v_policy->'state_match','{}'::jsonb);
    if jsonb_typeof(v_selector)<>'object' or jsonb_typeof(v_state_match)<>'object' then
      raise exception 'state consequence subjectSelector and stateMatch must be objects.' using errcode='22023';
    end if;

    if not (p_snapshot @> v_selector and p_snapshot @> v_state_match) then
      continue;
    end if;

    v_role:=nullif(btrim(coalesce(v_policy->>'consequenceRole',v_policy->>'consequence_role','')),'');
    if v_role not in ('operation_requirement','truth_acquisition','repair','preparation') then
      raise exception 'Unsupported shared consequence role for policy %: %',v_stable_key,coalesce(v_role,'<null>') using errcode='22023';
    end if;

    v_action_spec:=coalesce(v_policy->'actionSpec',v_policy->'action_spec','{}'::jsonb);
    if jsonb_typeof(v_action_spec)<>'object' then
      raise exception 'state consequence actionSpec must be an object.' using errcode='22023';
    end if;
    v_carrier:=nullif(btrim(coalesce(v_action_spec->>'carrierRef',v_action_spec->>'carrier_ref','')),'');
    v_priority:=coalesce((v_policy->>'priority')::integer,100);

    v_matches:=v_matches||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'stableKey',v_stable_key,
      'consequenceRole',v_role,
      'consequenceKind',coalesce(v_policy->>'consequenceKind',v_policy->>'consequence_kind'),
      'actionKey',coalesce(v_policy->>'actionKey',v_policy->>'action_key'),
      'priority',v_priority,
      'requirementState','established',
      'actionSpec',v_action_spec,
      'carrierRef',v_carrier,
      'carrierState',case when v_carrier is null then 'unresolved' else 'established' end,
      'placementState','unresolved',
      'executionReadiness','not_evaluated',
      'policyMetadata',coalesce(v_policy->'metadata','{}'::jsonb),
      'evidence',jsonb_build_object(
        'subjectSelector',v_selector,
        'stateMatch',v_state_match,
        'snapshot',p_snapshot
      )
    )));
  end loop;

  return jsonb_build_object(
    'contractVersion','life_state_consequence_evaluation_v1',
    'snapshot',p_snapshot,
    'openConsequences',v_matches,
    'openCount',jsonb_array_length(v_matches),
    'truthBoundary',jsonb_build_object(
      'matchingUsesExplicitSnapshotContainment',true,
      'policyMatchDoesNotInventCausation',true,
      'policyMatchDoesNotSelectCarrierUnlessPolicyExplicitlyDid',true,
      'policyMatchDoesNotCreateTask',true,
      'policyMatchDoesNotEvaluateExecutionReadiness',true,
      'policyMatchDoesNotPlaceClockClaim',true,
      'persistenceAndReleaseGenerationRemainAdapterResponsibilities',true
    ),
    'provenance',jsonb_build_object(
      'evaluator','atlas.evaluate_life_state_consequence_policies_v1',
      'farmPrecedent','atlas.reconcile_state_consequences_v1'
    )
  );
end;
$$;

comment on function atlas.evaluate_life_state_consequence_policies_v1(jsonb,jsonb) is
  'Generic read-only State Consequence matcher extracted from the existing farm reconciler: explicit snapshot containment activates explicit consequence policies. It creates no instance, task, carrier, readiness, or Clock placement.';

revoke all on function atlas.evaluate_life_goal_state_v1(jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.evaluate_life_state_consequence_policies_v1(jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.evaluate_life_goal_state_v1(jsonb,jsonb) to postgres;
grant execute on function atlas.evaluate_life_state_consequence_policies_v1(jsonb,jsonb) to postgres;

commit;
