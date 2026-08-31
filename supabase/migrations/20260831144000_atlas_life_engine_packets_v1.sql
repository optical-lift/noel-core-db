-- Atlas Life Engine Packets v1
--
-- Pure JSON compatibility packets for Rhythm, Goal, and State Consequence.
-- These functions deliberately do not reference or mutate the live
-- institution-bound engine persistence. They let domain adapters prove shared
-- semantics while preserving the existing Atlas truth boundary:
--
--   requirement != carrier != placement
--
-- Domain evidence remains domain-owned. Readiness does not establish requirement
-- existence, and Clock placement is not evidence for originating truth.

begin;

create or replace function atlas.life_signal_to_rhythm_packet_v1(p_signal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_validation jsonb;
  v_requirements jsonb;
  v_authorization_state text;
  v_definition_state text;
begin
  v_validation := atlas.validate_life_signal_v1(p_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;

  if p_signal->>'signalKind' <> 'rhythm' then
    raise exception 'Rhythm packet requires signalKind=rhythm.' using errcode='22023';
  end if;

  v_requirements := coalesce(p_signal->'requirements','[]'::jsonb);
  v_authorization_state := nullif(btrim(coalesce(p_signal->'state'->>'authorizationState','')),'');

  v_definition_state := case
    when coalesce(p_signal->'timing','{}'::jsonb) = '{}'::jsonb
         and jsonb_array_length(v_requirements)=0 then 'incomplete'
    else 'bounded'
  end;

  return jsonb_build_object(
    'contractVersion','life_rhythm_packet_v1',
    'scope',p_signal->'scope',
    'subject',p_signal->'subject',
    'source',p_signal->'source',
    'epistemic',p_signal->'epistemic',
    'definitionState',v_definition_state,
    'authorizationState',v_authorization_state,
    'timing',coalesce(p_signal->'timing','{}'::jsonb),
    'qualifyingRequirements',v_requirements,
    'constraints',coalesce(p_signal->'constraints','[]'::jsonb),
    'ambiguities',coalesce(p_signal->'ambiguities','[]'::jsonb),
    'satisfactionState','not_evaluated',
    'missState','unknown',
    'recoveryState','not_evaluated',
    'truthBoundary',jsonb_build_object(
      'cadenceDoesNotProveSatisfaction',true,
      'absenceOfSatisfactionEvidenceDoesNotProveFailure',true,
      'missDoesNotCreateMoralDebt',true,
      'requirementDoesNotSelectCarrier',true,
      'taskGenerationAuthority',false,
      'clockPlacementAuthority',false,
      'clockPlacementCannotProveRhythmState',true,
      'domainEvidenceRemainsAuthoritative',true
    ),
    'provenance',jsonb_build_object(
      'adapter','atlas.life_signal_to_rhythm_packet_v1',
      'lifeSignalContract','atlas_life_signal_v1'
    )
  );
end;
$$;

comment on function atlas.life_signal_to_rhythm_packet_v1(jsonb) is
  'Pure Rhythm compatibility packet. It preserves cadence, satisfaction definition, authorization, and uncertainty without evaluating history, creating tasks, or placing Clock claims.';

create or replace function atlas.life_signal_to_goal_packet_v1(p_signal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_validation jsonb;
  v_requirements jsonb;
  v_explicit_end jsonb;
  v_definition_state text;
begin
  v_validation := atlas.validate_life_signal_v1(p_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;

  if p_signal->>'signalKind' <> 'goal' then
    raise exception 'Goal packet requires signalKind=goal.' using errcode='22023';
  end if;

  v_requirements := coalesce(p_signal->'requirements','[]'::jsonb);
  v_explicit_end := case
    when p_signal->'state' ? 'explicitUserEnd' then p_signal->'state'->'explicitUserEnd'
    else null
  end;
  v_definition_state := case when v_explicit_end is null then 'incomplete' else 'bounded' end;

  return jsonb_build_object(
    'contractVersion','life_goal_packet_v1',
    'scope',p_signal->'scope',
    'subject',p_signal->'subject',
    'source',p_signal->'source',
    'epistemic',p_signal->'epistemic',
    'definitionState',v_definition_state,
    'explicitUserEnd',v_explicit_end,
    'requirements',v_requirements,
    'requirementCount',jsonb_array_length(v_requirements),
    'constraints',coalesce(p_signal->'constraints','[]'::jsonb),
    'ambiguities',coalesce(p_signal->'ambiguities','[]'::jsonb),
    'satisfactionState','not_evaluated',
    'truthBoundary',jsonb_build_object(
      'goalLabelDoesNotInventRequirements',true,
      'customaryDomainPracticeIsNotRequirementEvidence',true,
      'requirementSatisfactionNeedsIndependentEvidence',true,
      'requirementDoesNotSelectCarrier',true,
      'taskGenerationAuthority',false,
      'clockPlacementAuthority',false,
      'domainEvidenceRemainsAuthoritative',true
    ),
    'provenance',jsonb_build_object(
      'adapter','atlas.life_signal_to_goal_packet_v1',
      'lifeSignalContract','atlas_life_signal_v1'
    )
  );
end;
$$;

comment on function atlas.life_signal_to_goal_packet_v1(jsonb) is
  'Pure Goal compatibility packet. An explicit desired end is preserved separately from independently warranted requirements; the adapter invents neither requirements nor satisfaction.';

create or replace function atlas.life_signal_to_consequence_packet_v1(p_signal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_validation jsonb;
  v_requirement jsonb;
  v_requirements jsonb;
  v_packets jsonb := '[]'::jsonb;
  v_role text;
  v_key text;
  v_operation text;
  v_carrier text;
  v_index integer := 0;
  v_subject_ref text;
begin
  v_validation := atlas.validate_life_signal_v1(p_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;

  if p_signal->>'signalKind' <> 'consequence' then
    raise exception 'Consequence packet requires signalKind=consequence.' using errcode='22023';
  end if;

  v_requirements := coalesce(p_signal->'requirements','[]'::jsonb);
  v_subject_ref := concat_ws(':',
    p_signal->'subject'->>'domain',
    p_signal->'subject'->>'kind',
    p_signal->'subject'->>'id'
  );

  for v_requirement in
    select value from jsonb_array_elements(v_requirements)
  loop
    v_index := v_index + 1;
    v_role := coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind');

    if v_role <> all(array['operation_requirement','truth_acquisition','repair','preparation']) then
      raise exception 'Unsupported consequence requirement role: %', v_role using errcode='22023';
    end if;

    v_key := nullif(btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key','')),'');
    if v_key is null then
      v_key := v_subject_ref || ':consequence:' || v_index::text;
    end if;

    v_operation := nullif(btrim(coalesce(v_requirement->>'operationKey',v_requirement->>'operation_key','')),'');
    v_carrier := nullif(btrim(coalesce(v_requirement->>'carrierRef',v_requirement->>'carrier_ref','')),'');

    v_packets := v_packets || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'requirementKey',v_key,
      'consequenceRole',v_role,
      'requirementState','established',
      'operationKey',v_operation,
      'operationState',case when v_operation is null then 'unresolved' else 'established' end,
      'carrierRef',v_carrier,
      'carrierState',case when v_carrier is null then 'unresolved' else 'established' end,
      'placementState','unresolved',
      'executionReadiness','not_evaluated',
      'entryCondition',nullif(v_requirement->>'entryCondition',''),
      'exitCondition',nullif(v_requirement->>'exitCondition',''),
      'expectedAfterState',coalesce(v_requirement->'expectedAfterState',v_requirement->'expected_after_state'),
      'blocker',nullif(v_requirement->>'blocker',''),
      'sourceRequirement',v_requirement
    )));
  end loop;

  return jsonb_build_object(
    'contractVersion','life_consequence_packet_v1',
    'scope',p_signal->'scope',
    'subject',p_signal->'subject',
    'source',p_signal->'source',
    'epistemic',p_signal->'epistemic',
    'presentState',coalesce(p_signal->'state','{}'::jsonb),
    'timing',coalesce(p_signal->'timing','{}'::jsonb),
    'requirements',v_packets,
    'constraints',coalesce(p_signal->'constraints','[]'::jsonb),
    'ambiguities',coalesce(p_signal->'ambiguities','[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'requirementAuthority','supplied_domain_evidence_only',
      'requirementExistenceNotInferredFromReadiness',true,
      'notReadyDoesNotMeanNotRequired',true,
      'requirementDoesNotSelectCarrier',true,
      'carrierDoesNotSelectPlacement',true,
      'capabilityHoldMayBlockExecutionWithoutDeletingObligation',true,
      'taskGenerationAuthority',false,
      'executionReadinessAuthority',false,
      'clockPlacementAuthority',false,
      'domainEvidenceRemainsAuthoritative',true
    ),
    'provenance',jsonb_build_object(
      'adapter','atlas.life_signal_to_consequence_packet_v1',
      'lifeSignalContract','atlas_life_signal_v1',
      'taskExecutionAuthorityPrecedent','atlas.task_execution_requirement_evaluation_v1'
    )
  );
end;
$$;

comment on function atlas.life_signal_to_consequence_packet_v1(jsonb) is
  'Pure State Consequence compatibility packet. It preserves operation/truth-acquisition/repair/preparation requirements while keeping requirement, carrier, execution readiness, and Clock placement as separate authorities.';

revoke all on function atlas.life_signal_to_rhythm_packet_v1(jsonb) from public, anon, authenticated;
revoke all on function atlas.life_signal_to_goal_packet_v1(jsonb) from public, anon, authenticated;
revoke all on function atlas.life_signal_to_consequence_packet_v1(jsonb) from public, anon, authenticated;
grant execute on function atlas.life_signal_to_rhythm_packet_v1(jsonb) to postgres;
grant execute on function atlas.life_signal_to_goal_packet_v1(jsonb) to postgres;
grant execute on function atlas.life_signal_to_consequence_packet_v1(jsonb) to postgres;

commit;
