-- Atlas Life Rhythm Lease Core v1
--
-- Makes Rhythm strategy explicit and extracts the reusable lease/cadence state
-- machine from the farm-bound Rhythm runtime. This generic evaluator does not
-- create tasks, occurrences, transitions, or Clock placements.
--
-- v1 semantic boundary:
--   lease Rhythm = a qualifying satisfaction establishes/renews validity for a
--                  bounded interval, optionally with warning and grace windows.
--
-- Bounded quotas (for example, four accepted care practices before Friday) are
-- finite requirements/Goal structure, not automatically Rhythm. Event-triggered
-- capture (for example, record a dream if remembered) is Observation logic unless
-- a separate cadence is explicitly established.

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
  v_rhythm_model text;
  v_definition_state text;
  v_strategy_state text;
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
  v_rhythm_model := nullif(btrim(coalesce(p_signal->'state'->>'rhythmModel','')),'');

  v_definition_state := case
    when coalesce(p_signal->'timing','{}'::jsonb) = '{}'::jsonb
         and jsonb_array_length(v_requirements)=0 then 'incomplete'
    else 'bounded'
  end;

  v_strategy_state := case
    when v_rhythm_model is null then 'unresolved'
    when v_rhythm_model='lease' then 'supported'
    else 'unsupported_in_v1'
  end;

  return jsonb_build_object(
    'contractVersion','life_rhythm_packet_v1',
    'scope',p_signal->'scope',
    'subject',p_signal->'subject',
    'source',p_signal->'source',
    'epistemic',p_signal->'epistemic',
    'definitionState',v_definition_state,
    'authorizationState',v_authorization_state,
    'rhythmModel',v_rhythm_model,
    'strategyState',v_strategy_state,
    'timing',coalesce(p_signal->'timing','{}'::jsonb),
    'qualifyingRequirements',v_requirements,
    'constraints',coalesce(p_signal->'constraints','[]'::jsonb),
    'ambiguities',coalesce(p_signal->'ambiguities','[]'::jsonb),
    'satisfactionState','not_evaluated',
    'missState','unknown',
    'recoveryState','not_evaluated',
    'truthBoundary',jsonb_build_object(
      'rhythmStrategyMustBeExplicit',true,
      'cadenceDoesNotProveSatisfaction',true,
      'absenceOfSatisfactionEvidenceDoesNotProveFailure',true,
      'noPriorSatisfactionMeansUninitializedNotFailed',true,
      'missDoesNotCreateMoralDebt',true,
      'requirementDoesNotSelectCarrier',true,
      'boundedQuotaIsNotAutomaticallyRhythm',true,
      'eventTriggeredObservationIsNotAutomaticallyRhythm',true,
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
  'Pure Rhythm compatibility packet with explicit strategy identity. v1 supports the extracted lease model; quotas and event-triggered observations are deliberately routed elsewhere unless a separate cadence is established.';

create or replace function atlas.evaluate_life_lease_rhythm_v1(
  p_rhythm_packet jsonb,
  p_last_satisfied_at timestamptz,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_timing jsonb;
  v_validity integer;
  v_warning integer;
  v_grace integer;
  v_as_of timestamptz:=coalesce(p_as_of,now());
  v_warning_at timestamptz;
  v_due_at timestamptz;
  v_failure_at timestamptz;
  v_state text;
  v_boundary_mode text;
begin
  if p_rhythm_packet is null
     or jsonb_typeof(p_rhythm_packet)<>'object'
     or p_rhythm_packet->>'contractVersion'<>'life_rhythm_packet_v1' then
    raise exception 'life_rhythm_packet_v1 is required.' using errcode='22023';
  end if;

  if p_rhythm_packet->>'rhythmModel'<>'lease' then
    raise exception 'Lease evaluator requires rhythmModel=lease.' using errcode='22023';
  end if;

  v_timing:=coalesce(p_rhythm_packet->'timing','{}'::jsonb);
  v_boundary_mode:=coalesce(nullif(v_timing->>'boundaryMode',''),'exact_timestamp');
  if v_boundary_mode<>'exact_timestamp' then
    raise exception 'life lease rhythm v1 supports boundaryMode=exact_timestamp only.' using errcode='22023';
  end if;

  begin
    v_validity:=(v_timing->>'validityIntervalSeconds')::integer;
    v_warning:=coalesce((v_timing->>'warningWindowSeconds')::integer,0);
    v_grace:=coalesce((v_timing->>'graceWindowSeconds')::integer,0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'lease rhythm timing values must be integer seconds.' using errcode='22023';
  end;

  if v_validity is null or v_validity<=0 then
    raise exception 'validityIntervalSeconds must be greater than zero.' using errcode='22023';
  end if;
  if v_warning<0 or v_grace<0 then
    raise exception 'warningWindowSeconds and graceWindowSeconds must be nonnegative.' using errcode='22023';
  end if;

  if p_last_satisfied_at is null then
    return jsonb_build_object(
      'contractVersion','life_rhythm_evaluation_v1',
      'rhythmModel','lease',
      'scope',p_rhythm_packet->'scope',
      'subject',p_rhythm_packet->'subject',
      'state','uninitialized',
      'lastSatisfiedAt',null,
      'warningAt',null,
      'dueAt',null,
      'failureAt',null,
      'asOf',v_as_of,
      'truthBoundary',jsonb_build_object(
        'absenceOfPriorSatisfactionDoesNotProveFailure',true,
        'doesNotCreateTask',true,
        'doesNotCreateTransitionHistory',true,
        'doesNotArbitrateClock',true,
        'authorizationMustBeResolvedUpstream',true
      )
    );
  end if;

  v_warning_at:=p_last_satisfied_at + make_interval(secs=>greatest(0,v_validity-v_warning));
  v_due_at:=p_last_satisfied_at + make_interval(secs=>v_validity);
  v_failure_at:=p_last_satisfied_at + make_interval(secs=>v_validity+v_grace);

  v_state:=case
    when v_as_of<v_warning_at then 'resting'
    when v_warning>0 and v_as_of<v_due_at then 'coming_due'
    when v_as_of<v_failure_at then 'due'
    else 'fallen_out_of_rhythm'
  end;

  return jsonb_build_object(
    'contractVersion','life_rhythm_evaluation_v1',
    'rhythmModel','lease',
    'scope',p_rhythm_packet->'scope',
    'subject',p_rhythm_packet->'subject',
    'state',v_state,
    'lastSatisfiedAt',p_last_satisfied_at,
    'warningAt',v_warning_at,
    'dueAt',v_due_at,
    'failureAt',v_failure_at,
    'asOf',v_as_of,
    'truthBoundary',jsonb_build_object(
      'stateDerivedOnlyFromExplicitLeaseParametersAndSatisfactionEvidence',true,
      'doesNotCreateTask',true,
      'doesNotCreateTransitionHistory',true,
      'doesNotArbitrateClock',true,
      'fallenOutOfRhythmIsLeaseStateNotMoralJudgment',true,
      'authorizationMustBeResolvedUpstream',true
    ),
    'provenance',jsonb_build_object(
      'evaluator','atlas.evaluate_life_lease_rhythm_v1',
      'farmPrecedent','atlas.evaluate_rhythm_binding_v1',
      'taskCreationRemovedFromGenericCore',true
    )
  );
end;
$$;

comment on function atlas.evaluate_life_lease_rhythm_v1(jsonb,timestamptz,timestamptz) is
  'Generic read-only lease Rhythm reducer extracted from the existing farm engine. Satisfaction evidence defines warning/due/failure boundaries; no satisfaction remains uninitialized. The core creates no task, transition history, or Clock placement.';

revoke all on function atlas.life_signal_to_rhythm_packet_v1(jsonb) from public, anon, authenticated;
revoke all on function atlas.evaluate_life_lease_rhythm_v1(jsonb,timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function atlas.life_signal_to_rhythm_packet_v1(jsonb) to postgres;
grant execute on function atlas.evaluate_life_lease_rhythm_v1(jsonb,timestamptz,timestamptz) to postgres;

commit;
