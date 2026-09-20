begin;

-- Person Life Consequence -> Principal Clock Candidate v1.
-- Live V1 candidate/arbitration/API contracts remain untouched.


create or replace view atlas.principal_person_life_consequence_clock_candidates_v1
as
select
  p.id as principal_id,
  d.subject_domain as domain,
  'person_life_consequence'::text as source_type,
  i.id as source_id,
  case
    when i.consequence_kind='laundry_cycle_needed' then 'Laundry'
    when nullif(i.consequence_kind,'') is not null
      then initcap(replace(i.consequence_kind,'_',' '))
    when nullif(i.action_key,'') is not null
      then initcap(replace(replace(i.action_key,':',' '),'_',' '))
    else 'Required action'
  end as title,
  (cc.value->>'floorClass')::smallint as floor_class,
  nullif(cc.value#>>'{timing,windowStart}','')::timestamptz as window_start,
  nullif(cc.value#>>'{timing,windowEnd}','')::timestamptz as window_end,
  nullif(cc.value#>>'{timing,fixedStart}','')::timestamptz as fixed_start,
  nullif(cc.value#>>'{timing,mustBeginBy}','')::timestamptz as must_begin_by,
  nullif(cc.value#>>'{timing,mustFinishBy}','')::timestamptz as must_finish_by,
  (cc.value->>'expectedMinutes')::integer as expected_minutes,
  cc.value->>'protectionLevel' as protection_level,
  cc.value->>'interruptibility' as interruptibility,
  (cc.value->>'delegable')::boolean as delegable,
  (cc.value->>'ownerRequired')::boolean as owner_required,
  cc.value->>'consequenceOfDelay' as consequence,
  cc.value->>'reasonForFloor' as reason_for_floor,
  null::uuid as portfolio_unit_id,
  null::text as horizon,
  jsonb_build_object(
    'clockCandidateContract','person_life_consequence_clock_candidate_v1',
    'consequenceInstanceId',i.id,
    'definitionId',i.definition_id,
    'consequenceStableKey',i.stable_key,
    'consequenceKind',i.consequence_kind,
    'actionKey',i.action_key,
    'requirementState',i.requirement_state,
    'carrierRef',i.carrier_ref,
    'carrierState',i.carrier_state,
    'executionReadiness',i.execution_readiness,
    'sourceEventId',i.last_seen_event_id,
    'clockCharacterizationClaimId',cc.id,
    'clockCharacterizationPrimaryEvidenceId',cc.primary_evidence_id,
    'subject',jsonb_build_object(
      'domain',d.subject_domain,
      'kind',d.subject_kind,
      'id',d.subject_id
    ),
    'truthBoundary',jsonb_build_object(
      'requirementTruthRemainsPersonLifeConsequence',true,
      'carrierAuthorityPrecedesClockAdmission',true,
      'executionReadinessPrecedesClockAdmission',true,
      'characterizationAuthorityPrecedesClockAdmission',true,
      'relevanceStartIsExplicit',true,
      'candidateProjectionCreatesNoPlacement',true
    )
  ) as metadata
from atlas.person_life_consequence_instances i
join atlas.person_life_definitions d
  on d.id=i.definition_id
 and d.owner_user_id=i.owner_user_id
 and d.signal_kind='consequence'
 and d.status='active'
join lateral (
  select p0.id
  from atlas.principals p0
  where p0.user_id=i.owner_user_id
    and p0.status='active'
  limit 1
) p on true
join lateral (
  select c.*
  from atlas.claim_records c
  where c.scope_kind='person'
    and c.scope_id=i.owner_user_id
    and c.subject_domain='principal.clock'
    and c.subject_kind='person_life_consequence'
    and c.subject_id=i.id::text
    and c.claim_type='clock_characterization'
    and c.lifecycle_state='accepted'
  order by c.recorded_at desc,c.id desc
  limit 1
) cc on true
cross join lateral (
  select atlas.person_life_consequence_clock_characterization_completeness_v1(cc.value) as state
) complete
where i.status='open'
  and i.requirement_state='established'
  and i.carrier_state='established'
  and i.carrier_ref=('principal:'||p.id::text)
  and i.execution_readiness='ready'
  and coalesce((complete.state->>'complete')::boolean,false);

comment on view atlas.principal_person_life_consequence_clock_candidates_v1 is
  'Read-only Principal Clock candidate projection for Person Life consequences that independently satisfy requirement, Principal-carrier, execution-readiness, and complete accepted Clock-characterization admission.';

revoke all on table atlas.principal_person_life_consequence_clock_candidates_v1
  from public, anon, authenticated;
grant select on table atlas.principal_person_life_consequence_clock_candidates_v1
  to service_role;


create or replace view atlas.principal_clock_candidates_v2
as
select
  principal_id,domain,source_type,source_id,title,floor_class,
  window_start,window_end,fixed_start,must_begin_by,must_finish_by,
  expected_minutes,protection_level,interruptibility,delegable,owner_required,
  consequence,reason_for_floor,portfolio_unit_id,horizon,metadata
from atlas.principal_clock_candidates_v1
union all
select
  principal_id,domain,source_type,source_id,title,floor_class,
  window_start,window_end,fixed_start,must_begin_by,must_finish_by,
  expected_minutes,protection_level,interruptibility,delegable,owner_required,
  consequence,reason_for_floor,portfolio_unit_id,horizon,metadata
from atlas.principal_person_life_consequence_clock_candidates_v1;

comment on view atlas.principal_clock_candidates_v2 is
  'V2 Principal Clock candidate inventory: unchanged V1 candidate inventory plus fully admitted Person Life consequence candidates.';

revoke all on table atlas.principal_clock_candidates_v2
  from public, anon, authenticated;
grant select on table atlas.principal_clock_candidates_v2
  to service_role;


CREATE OR REPLACE FUNCTION atlas.principal_clock_arbitration_v2(p_principal_id uuid, p_day date, p_as_of timestamp with time zone DEFAULT now())
 RETURNS TABLE(arbitration_rank bigint, timing_tier smallint, timing_state text, why_now text, right_to_floor_now boolean, latest_start_at timestamp with time zone, next_boundary_at timestamp with time zone, placement_state text, individually_within_daily_plan boolean, capacity_state text, capacity_known boolean, maximum_planned_minutes integer, discretionary_capacity_minutes integer, principal_id uuid, domain text, source_type text, source_id uuid, title text, floor_class smallint, window_start timestamp with time zone, window_end timestamp with time zone, fixed_start timestamp with time zone, must_begin_by timestamp with time zone, must_finish_by timestamp with time zone, expected_minutes integer, protection_level text, interruptibility text, delegable boolean, owner_required boolean, consequence text, reason_for_floor text, portfolio_unit_id uuid, horizon text, metadata jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
with capacity as (
  select atlas.principal_capacity_day_state_v1(p_principal_id, p_day) as state
), base as (
  select
    c.*,
    coalesce(c.must_finish_by, c.window_end) as finish_boundary,
    case
      when c.expected_minutes is not null
       and c.expected_minutes > 0
       and coalesce(c.must_finish_by, c.window_end) is not null
      then coalesce(c.must_finish_by, c.window_end) - make_interval(mins => c.expected_minutes)
      else null
    end as derived_latest_start_at
  from atlas.principal_clock_candidates_v2 c
  where c.principal_id = p_principal_id
), classified as (
  select
    b.*,
    case
      when b.fixed_start is not null
       and b.fixed_start <= p_as_of
       and b.window_end is not null
       and p_as_of < b.window_end
        then 0
      when b.fixed_start is null
       and b.must_finish_by is not null
       and b.must_finish_by <= p_as_of
        then 10
      when b.fixed_start is null
       and b.must_finish_by is null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 11
      when b.fixed_start is not null
       and b.window_end is null
       and b.fixed_start <= p_as_of
        then 12
      when b.fixed_start is null
       and b.must_begin_by is not null
       and b.must_begin_by <= p_as_of
       and (b.finish_boundary is null or p_as_of < b.finish_boundary)
        then 20
      when b.fixed_start is null
       and b.derived_latest_start_at is not null
       and b.derived_latest_start_at <= p_as_of
       and b.finish_boundary is not null
       and p_as_of < b.finish_boundary
        then 21
      when b.fixed_start is null
       and (b.window_start is null or b.window_start <= p_as_of)
       and (b.window_end is null or p_as_of < b.window_end)
        then 30
      when b.fixed_start is not null
       and b.fixed_start > p_as_of
        then 50
      when b.fixed_start is not null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 90
      when b.window_start is not null
       and b.window_start > p_as_of
        then 60
      else 70
    end::smallint as derived_timing_tier,
    case
      when b.fixed_start is not null
       and b.fixed_start <= p_as_of
       and b.window_end is not null
       and p_as_of < b.window_end
        then 'fixed_active'
      when b.fixed_start is null
       and b.must_finish_by is not null
       and b.must_finish_by <= p_as_of
        then 'finish_boundary_breached'
      when b.fixed_start is null
       and b.must_finish_by is null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 'window_elapsed_unresolved'
      when b.fixed_start is not null
       and b.window_end is null
       and b.fixed_start <= p_as_of
        then 'fixed_point_reached'
      when b.fixed_start is null
       and b.must_begin_by is not null
       and b.must_begin_by <= p_as_of
       and (b.finish_boundary is null or p_as_of < b.finish_boundary)
        then 'must_begin_boundary_reached'
      when b.fixed_start is null
       and b.derived_latest_start_at is not null
       and b.derived_latest_start_at <= p_as_of
       and b.finish_boundary is not null
       and p_as_of < b.finish_boundary
        then 'latest_start_reached'
      when b.fixed_start is null
       and (b.window_start is null or b.window_start <= p_as_of)
       and (b.window_end is null or p_as_of < b.window_end)
        then 'relevant_window_open'
      when b.fixed_start is not null
       and b.fixed_start > p_as_of
        then 'fixed_upcoming'
      when b.fixed_start is not null
       and b.window_end is not null
       and b.window_end <= p_as_of
        then 'fixed_elapsed'
      when b.window_start is not null
       and b.window_start > p_as_of
        then 'future_window'
      else 'remembered_without_current_timing'
    end as derived_timing_state,
    (
      select min(x.boundary)
      from (values
        (b.fixed_start),
        (b.window_start),
        (b.must_begin_by),
        (b.derived_latest_start_at),
        (b.must_finish_by),
        (b.window_end)
      ) as x(boundary)
      where x.boundary > p_as_of
    ) as derived_next_boundary_at
  from base b
), enriched as (
  select
    c.*,
    case c.derived_timing_state
      when 'fixed_active' then 'A fixed commitment is in progress.'
      when 'finish_boundary_breached' then 'Its finish boundary has passed while the claim remains open.'
      when 'window_elapsed_unresolved' then 'Its relevant window has elapsed while the claim remains unresolved.'
      when 'fixed_point_reached' then 'Its fixed point has been reached while the claim remains open.'
      when 'must_begin_boundary_reached' then 'Its must-begin boundary has been reached.'
      when 'latest_start_reached' then 'Its latest start has been reached after accounting for expected duration.'
      when 'relevant_window_open' then 'Its relevant window is open.'
      when 'fixed_upcoming' then 'A fixed commitment is upcoming.'
      when 'future_window' then 'Its relevant window has not opened yet.'
      when 'fixed_elapsed' then 'The fixed commitment time window has elapsed.'
      else 'The claim is remembered, but no current timing boundary gives it the floor.'
    end as derived_why_now,
    case c.protection_level
      when 'critical' then 0
      when 'protected' then 1
      when 'standard' then 2
      when 'optional' then 3
      else 4
    end as protection_order
  from classified c
), ranked as (
  select
    e.*,
    row_number() over (
      order by
        e.derived_timing_tier,
        e.floor_class,
        e.protection_order,
        e.derived_next_boundary_at nulls last,
        e.title,
        e.source_id
    ) as derived_arbitration_rank
  from enriched e
), cap as (
  select
    state,
    state ->> 'state' as capacity_state,
    coalesce((state ->> 'capacityKnown')::boolean, false) as capacity_known,
    nullif(state ->> 'maximumPlannedMinutes','')::integer as maximum_planned_minutes,
    nullif(state ->> 'discretionaryCapacityMinutes','')::integer as discretionary_capacity_minutes
  from capacity
)
select
  r.derived_arbitration_rank as arbitration_rank,
  r.derived_timing_tier as timing_tier,
  r.derived_timing_state as timing_state,
  r.derived_why_now as why_now,
  (r.derived_timing_tier <= 30) as right_to_floor_now,
  r.derived_latest_start_at as latest_start_at,
  r.derived_next_boundary_at as next_boundary_at,
  case
    when r.fixed_start is not null or r.source_type = 'capacity_block' then 'fixed_or_precommitted'
    when not cap.capacity_known then 'capacity_anchor_required'
    when r.expected_minutes is null then 'duration_required'
    when cap.maximum_planned_minutes is null then 'capacity_anchor_required'
    when r.expected_minutes <= cap.maximum_planned_minutes then 'eligible_for_placement'
    else 'exceeds_daily_planning_capacity'
  end as placement_state,
  case
    when r.fixed_start is not null or r.source_type = 'capacity_block' then null::boolean
    when not cap.capacity_known then false
    when r.expected_minutes is null or cap.maximum_planned_minutes is null then false
    else r.expected_minutes <= cap.maximum_planned_minutes
  end as individually_within_daily_plan,
  cap.capacity_state,
  cap.capacity_known,
  cap.maximum_planned_minutes,
  cap.discretionary_capacity_minutes,
  r.principal_id,
  r.domain,
  r.source_type,
  r.source_id,
  r.title,
  r.floor_class,
  r.window_start,
  r.window_end,
  r.fixed_start,
  r.must_begin_by,
  r.must_finish_by,
  r.expected_minutes,
  r.protection_level,
  r.interruptibility,
  r.delegable,
  r.owner_required,
  r.consequence,
  r.reason_for_floor,
  r.portfolio_unit_id,
  r.horizon,
  r.metadata
from ranked r
cross join cap
order by r.derived_arbitration_rank;
$function$;


comment on function atlas.principal_clock_arbitration_v2(uuid,date,timestamptz) is
  'V2 read-only Principal Clock arbitration. Applies the released V1 arbitration law to principal_clock_candidates_v2, which adds only fully admitted Person Life consequences.';

revoke all on function atlas.principal_clock_arbitration_v2(uuid,date,timestamptz)
  from public, anon, authenticated, service_role;


CREATE OR REPLACE FUNCTION atlas.principal_clock_api_v2(p_day date DEFAULT CURRENT_DATE, p_as_of timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal_id uuid;
  v_capacity jsonb;
  v_candidates jsonb;
  v_floor jsonb;
  v_readiness jsonb;
  v_coverage_state text;
  v_coverage_mode text;
  v_floor_claim_state text;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if p_day is null then
    raise exception 'A Principal Clock date is required.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'A Principal Clock as-of time is required.' using errcode='22023';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_clock_api_v3',
      'state','principal_required',
      'serviceDate',p_day,
      'asOf',p_as_of,
      'allocationState','read_only_arbitration',
      'coverageState','principal_required',
      'coverageMode','no_principal_context',
      'floor',null,
      'candidates','[]'::jsonb
    );
  end if;

  v_capacity:=atlas.principal_capacity_day_state_v1(v_principal_id,p_day);
  v_readiness:=atlas.principal_reality_readiness_v3(v_principal_id,p_day);
  v_coverage_state:=coalesce(v_readiness->>'state','source_required');
  v_coverage_mode:=case
    when v_coverage_state='ready' then 'governed_field'
    else 'known_reality_slice'
  end;

  select coalesce(jsonb_agg(to_jsonb(a) order by a.arbitration_rank),'[]'::jsonb)
  into v_candidates
  from atlas.principal_clock_arbitration_v2(v_principal_id,p_day,p_as_of) a;

  select to_jsonb(a)
  into v_floor
  from atlas.principal_clock_arbitration_v2(v_principal_id,p_day,p_as_of) a
  where a.right_to_floor_now
    and a.timing_state<>'fixed_elapsed'
  order by a.arbitration_rank
  limit 1;

  v_floor_claim_state:=case
    when v_floor is null and v_coverage_state='ready' then 'no_known_claim_has_floor'
    when v_floor is null then 'no_known_claim_has_floor_but_coverage_incomplete'
    when v_coverage_state='ready' then 'valid_governed_floor'
    else 'valid_floor_within_known_slice'
  end;

  return jsonb_build_object(
    'contractVersion','principal_clock_api_v3',
    'state','ready',
    'arbitrationState','ready',
    'principalId',v_principal_id,
    'serviceDate',p_day,
    'asOf',p_as_of,
    'allocationState','read_only_arbitration',
    'coverageState',v_coverage_state,
    'coverageMode',v_coverage_mode,
    'completeFieldClaim',(v_coverage_state='ready'),
    'floorClaimState',v_floor_claim_state,
    'coverageSummary',v_readiness->'summary',
    'capacity',v_capacity,
    'floor',v_floor,
    'candidates',v_candidates,
    'truthBoundary',jsonb_build_object(
      'floorRanksOnlyKnownLawfulCandidates',true,
      'partialCoverageDoesNotInvalidateKnownCandidate',true,
      'partialCoverageDoesNotProveNoOtherCandidateExists',true,
      'unknownCapacityDoesNotBecomeFreeCapacity',true,
      'sourceGapsRemainOutsideClockCandidateInventory',true,
      'arbitrationReadyDoesNotMeanRealityCoverageComplete',true,
      'personLifeConsequenceCandidatesRequireExplicitAdmission',true,
      'missingCharacterizationNeverDefaultsToClockRelevance',true
    )
  );
end;
$function$;


comment on function atlas.principal_clock_api_v2(date,timestamptz) is
  'Authenticated V2 Principal Clock read. Preserves existing arbitration/capacity/coverage semantics while adding only fully admitted Person Life consequence candidates through the V2 inventory.';

revoke all on function atlas.principal_clock_api_v2(date,timestamptz)
  from public, anon;
grant execute on function atlas.principal_clock_api_v2(date,timestamptz)
  to authenticated, service_role;


insert into atlas.authenticated_rpc_registry(
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  reviewed_at,
  anonymous_execute_expected
)
values (
  'atlas.principal_clock_api_v2(date, timestamp with time zone)',
  'app_endpoint',
  'verified',
  'active',
  true,
  true,
  true,
  0,
  0,
  jsonb_build_object(
    'purpose','Return V2 read-only Principal Clock arbitration over unchanged V1 candidates plus fully admitted Person Life consequences.',
    'authorizationBoundary','Principal identity remains auth-bound. Person Life consequences enter only after requirement, Principal carrier, execution-readiness, and complete accepted Clock-characterization admission. Endpoint creates no placement.',
    'contract','principal_clock_api_v3',
    'directSignedInEndpoint',true
  ),
  now(),
  false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

commit;
