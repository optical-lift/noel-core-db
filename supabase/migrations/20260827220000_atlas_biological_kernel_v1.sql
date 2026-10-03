-- Atlas biological kernel v1
--
-- This layer answers only biological questions:
--   * what state is the living crop body in?
--   * what biological operation is due or approaching?
--   * is continued biological dwell lawful right now?
--
-- Human routing, execution permission, spatial assignment, resources, weather,
-- commercial disposition, and presentation are intentionally outside this layer.

create or replace function atlas.biological_state_snapshot_v1(
  p_subject_kind text,
  p_subject_id uuid,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_kind text := lower(btrim(coalesce(p_subject_kind,'')));
  v_day date := coalesce(p_as_of_date,current_date);
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_observation atlas.crop_observations%rowtype;
  v_harvest atlas.crop_harvest_availability%rowtype;
  v_harvest_event atlas.crop_harvest_events%rowtype;
  v_hardening_started date;
  v_pot_up_date date;
  v_anchor_date date;
begin
  if v_kind='' or p_subject_id is null then
    raise exception 'Subject kind and subject id are required.' using errcode='22023';
  end if;

  if v_kind<>'crop_cycle' then
    raise exception 'biological_state_snapshot_v1 currently supports crop_cycle only.' using errcode='22023';
  end if;

  select * into v_cycle
  from atlas.crop_cycles
  where id=p_subject_id;

  if v_cycle.id is null then
    raise exception 'Crop cycle not found.' using errcode='P0002';
  end if;

  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  if v_cycle.crop_profile_id is not null then
    select * into v_profile
    from atlas.crop_profiles
    where id=v_cycle.crop_profile_id;
  end if;

  select * into v_observation
  from atlas.crop_observations
  where crop_cycle_id=v_cycle.id
    and coalesce(observed_date,created_at::date)<=v_day
  order by coalesce(observed_date,created_at::date) desc,created_at desc
  limit 1;

  select * into v_harvest
  from atlas.crop_harvest_availability
  where crop_cycle_id=v_cycle.id;

  select * into v_harvest_event
  from atlas.crop_harvest_events
  where crop_cycle_id=v_cycle.id
    and observed_date<=v_day
  order by observed_date desc,created_at desc
  limit 1;

  if coalesce(v_cycle.metadata->>'hardening_started_date','') ~ '^\d{4}-\d{2}-\d{2}$' then
    v_hardening_started := (v_cycle.metadata->>'hardening_started_date')::date;
  elsif coalesce(v_cycle.metadata->>'hardening_confirmed_date','') ~ '^\d{4}-\d{2}-\d{2}$' then
    v_hardening_started := (v_cycle.metadata->>'hardening_confirmed_date')::date;
  end if;

  if coalesce(v_cycle.metadata->>'pot_up_date','') ~ '^\d{4}-\d{2}-\d{2}$' then
    v_pot_up_date := (v_cycle.metadata->>'pot_up_date')::date;
  elsif coalesce(v_cycle.metadata->>'bumped_up_date','') ~ '^\d{4}-\d{2}-\d{2}$' then
    v_pot_up_date := (v_cycle.metadata->>'bumped_up_date')::date;
  end if;

  v_anchor_date := coalesce(v_cycle.planted_date,v_cycle.sown_date);

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','biological_state_snapshot_v1',
    'subjectKind','crop_cycle',
    'subjectId',v_cycle.id,
    'farmId',v_cycle.farm_id,
    'asOfDate',v_day,
    'identity',jsonb_strip_nulls(jsonb_build_object(
      'cropCycleKey',v_cycle.crop_cycle_key,
      'cropLabel',v_cycle.crop_label,
      'variety',v_cycle.variety,
      'cropProfileId',v_profile.id,
      'cropProfileStableKey',v_profile.stable_key
    )),
    'biologicalState',jsonb_strip_nulls(jsonb_build_object(
      'cycleState',v_cycle.cycle_state,
      'lifecycleStatus',v_cycle.lifecycle_status,
      'lifeCycle',v_profile.life_cycle,
      'harvestPattern',v_profile.harvest_pattern,
      'frostBehavior',v_profile.frost_behavior,
      'declineSignal',v_profile.decline_signal,
      'standCondition',nullif(v_cycle.metadata->>'stand_condition',''),
      'conditionNote',nullif(v_cycle.metadata->>'condition_note','')
    )),
    'biologicalAnchors',jsonb_strip_nulls(jsonb_build_object(
      'sownDate',v_cycle.sown_date,
      'plantedDate',v_cycle.planted_date,
      'anchorDate',v_anchor_date,
      'potUpDate',v_pot_up_date,
      'hardeningStartedDate',v_hardening_started,
      'germinationCheckedDate',v_cycle.germination_checked_date,
      'harvestStartedDate',v_cycle.harvest_started_date,
      'lastHarvestDate',v_cycle.last_harvest_date,
      'clearedDate',v_cycle.cleared_date,
      'turnoverDate',v_cycle.turnover_date
    )),
    'timingModel',jsonb_strip_nulls(jsonb_build_object(
      'daysToGerminationMin',v_profile.days_to_germination_min,
      'daysToGerminationMax',v_profile.days_to_germination_max,
      'daysToHarvestWatchMin',v_profile.days_to_harvest_watch_min,
      'daysToHarvestWatchMax',v_profile.days_to_harvest_watch_max,
      'expectedGerminationStart',v_cycle.expected_germination_start,
      'expectedGerminationEnd',v_cycle.expected_germination_end,
      'expectedHarvestWatchStart',v_cycle.expected_harvest_watch_start,
      'expectedHarvestWatchEnd',v_cycle.expected_harvest_watch_end,
      'expectedClearDate',v_cycle.expected_clear_date
    )),
    'latestObservation',case when v_observation.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'observationId',v_observation.id,
      'observedDate',coalesce(v_observation.observed_date,v_observation.created_at::date),
      'stage',v_observation.stage,
      'condition',v_observation.condition,
      'observedQuantity',v_observation.observed_quantity,
      'quantityUnit',v_observation.quantity_unit,
      'quantityKind',v_observation.quantity_kind,
      'standPercent',v_observation.stand_percent,
      'confidence',v_observation.confidence
    )) end,
    'harvestState',jsonb_strip_nulls(jsonb_build_object(
      'availabilityStatus',v_harvest.status,
      'availabilityObservedDate',v_harvest.observed_date,
      'estimatedQuantity',v_harvest.estimated_quantity,
      'unit',v_harvest.unit,
      'latestEvent',case when v_harvest_event.id is null then null else jsonb_strip_nulls(jsonb_build_object(
        'eventId',v_harvest_event.id,
        'eventKind',v_harvest_event.event_kind,
        'outcome',v_harvest_event.outcome,
        'observedDate',v_harvest_event.observed_date,
        'marketableQuantity',v_harvest_event.marketable_quantity,
        'secondsQuantity',v_harvest_event.seconds_quantity,
        'discardedQuantity',v_harvest_event.discarded_quantity,
        'unit',v_harvest_event.unit,
        'moreAvailable',v_harvest_event.more_available,
        'nextCheckDate',v_harvest_event.next_check_date
      )) end
    )),
    'truthBoundary',jsonb_build_object(
      'cropIdentityIsNotAnOperation',true,
      'biologicalStateIsNotExecutionPermission',true,
      'missingTimingModelIsNotProofOfNoBiologicalNeed',true,
      'lawfulDwellMustBeAffirmativelyDerived',true,
      'v1SubjectCoverage','crop_cycle_only'
    )
  ));
end;
$$;

revoke all on function atlas.biological_state_snapshot_v1(text,uuid,date) from public, anon;
grant execute on function atlas.biological_state_snapshot_v1(text,uuid,date) to authenticated, service_role;

comment on function atlas.biological_state_snapshot_v1(text,uuid,date) is
  'Pure biological snapshot for a canonical subject. v1 supports crop cycles and excludes human execution and presentation state.';

create or replace function atlas.biological_operations_due_v1(
  p_subject_kind text,
  p_subject_id uuid,
  p_as_of_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_day date := coalesce(p_as_of_date,current_date);
  v_snapshot jsonb;
  v_state text;
  v_lifecycle_status text;
  v_life_cycle text;
  v_harvest_pattern text;
  v_harvest_status text;
  v_expected_germination_start date;
  v_expected_harvest_start date;
  v_expected_clear_date date;
  v_hardening_started date;
  v_anchor_date date;
  v_latest_observed date;
  v_next_harvest_check date;
  v_operations jsonb := '[]'::jsonb;
  v_model_gaps jsonb := '[]'::jsonb;
  v_continuation text := 'unresolved';
  v_next_boundary jsonb := null;
  v_reason text;
  v_known_active_by date;
begin
  v_snapshot := atlas.biological_state_snapshot_v1(p_subject_kind,p_subject_id,v_day);

  v_state := coalesce(v_snapshot#>>'{biologicalState,cycleState}','');
  v_lifecycle_status := coalesce(v_snapshot#>>'{biologicalState,lifecycleStatus}','');
  v_life_cycle := coalesce(v_snapshot#>>'{biologicalState,lifeCycle}','');
  v_harvest_pattern := coalesce(v_snapshot#>>'{biologicalState,harvestPattern}','');
  v_harvest_status := coalesce(v_snapshot#>>'{harvestState,availabilityStatus}','');

  v_expected_germination_start := nullif(v_snapshot#>>'{timingModel,expectedGerminationStart}','')::date;
  v_expected_harvest_start := nullif(v_snapshot#>>'{timingModel,expectedHarvestWatchStart}','')::date;
  v_expected_clear_date := nullif(v_snapshot#>>'{timingModel,expectedClearDate}','')::date;
  v_hardening_started := nullif(v_snapshot#>>'{biologicalAnchors,hardeningStartedDate}','')::date;
  v_anchor_date := nullif(v_snapshot#>>'{biologicalAnchors,anchorDate}','')::date;
  v_latest_observed := nullif(v_snapshot#>>'{latestObservation,observedDate}','')::date;
  v_next_harvest_check := nullif(v_snapshot#>>'{harvestState,latestEvent,nextCheckDate}','')::date;

  if v_lifecycle_status not in ('active','living') or v_state='cleared' then
    v_continuation := 'terminal_or_inactive';
    v_reason := 'The canonical crop body is not in an active living lifecycle state.';

  elsif v_harvest_status='harvestable' then
    v_known_active_by := coalesce(nullif(v_snapshot#>>'{harvestState,availabilityObservedDate}','')::date,v_day);
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','harvest',
      'timeState','due',
      'knownActiveBy',v_known_active_by,
      'basis','current_harvestability_state',
      'consequenceClass',case when v_harvest_pattern='single_cut' then 'narrow_window_single_cut' else 'harvestable_crop' end,
      'reason','Canonical biological readiness currently says the crop is harvestable.'
    ));
    v_continuation := 'operation_due';

  elsif v_state='hardening_off' then
    v_known_active_by := coalesce(v_hardening_started,v_latest_observed,v_anchor_date,v_day);
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','transplant',
      'timeState','due',
      'knownActiveBy',v_known_active_by,
      'exactOnsetKnown',v_hardening_started is not null,
      'basis','current_hardening_state',
      'consequenceClass','transplant_window',
      'reason','Hardening-off is a pre-planting biological state; the living crop now requires a transplant response.'
    ));
    v_continuation := 'operation_due';

  elsif v_state in ('seedling','seedling_care') then
    v_known_active_by := coalesce(v_latest_observed,v_anchor_date,v_day);
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','observe_seedling_progression',
      'timeState','attention_required',
      'knownActiveBy',v_known_active_by,
      'basis','transition_state_requires_progression',
      'reason','Seedling care is a transition state. Atlas needs a current biological observation to establish continued care, pot-up, hardening, transplant readiness, or a problem state.'
    ));
    if v_anchor_date is null then
      v_model_gaps := v_model_gaps || jsonb_build_array(jsonb_build_object(
        'gapKey','biological_anchor_missing',
        'reason','The living seedling lacks a witnessed sow or plant anchor; timing confidence is limited but the need for continued biological observation remains.'
      ));
    end if;
    v_continuation := 'operation_due';

  elsif v_state='establishing' then
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','observe_establishment',
      'timeState','attention_required',
      'knownActiveBy',coalesce(v_latest_observed,v_anchor_date,v_day),
      'basis','establishment_transition',
      'reason','Establishing is not durable dwell. A current observation must confirm continued establishment, stable occupancy, stress, or failure.'
    ));
    v_continuation := 'operation_due';

  elsif v_state in ('compromised','stressed','browsed_alive','partial_stand') then
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','inspect_condition_and_reclassify',
      'timeState','due',
      'knownActiveBy',coalesce(v_latest_observed,v_day),
      'basis','altered_living_condition',
      'reason','The crop remains alive but its physical condition has materially changed; current condition and remaining production must be observed.'
    ));
    v_continuation := 'operation_due';

  elsif v_state='cut_back' then
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','inspect_regrowth_or_termination',
      'timeState','attention_required',
      'knownActiveBy',coalesce(v_latest_observed,v_day),
      'basis','cut_back_transition',
      'reason','Cut-back is a transition state; regrowth, continued production, or biological termination must be established.'
    ));
    v_continuation := 'operation_due';

  elsif v_state in ('declining','finished','finished_harvest') then
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','assess_postproduction_state',
      'timeState','due',
      'knownActiveBy',coalesce(v_latest_observed,v_day),
      'basis','postproduction_transition',
      'reason','Decline or finished harvest does not itself prove the living body is cleared or terminal; remaining yield and biological condition must be assessed.'
    ));
    v_continuation := 'operation_due';

  elsif v_state in ('budding','flowering','fruiting') then
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','inspect_harvest_readiness',
      'timeState','due',
      'knownActiveBy',coalesce(v_latest_observed,v_day),
      'basis','reproductive_state',
      'consequenceClass',case when v_harvest_pattern='single_cut' then 'narrow_window_single_cut' else 'reproductive_crop' end,
      'reason','Observed reproductive state requires a current readiness observation; reproductive state alone does not prove marketable harvestability.'
    ));
    v_continuation := 'operation_due';

  elsif v_state in ('planted','sown_awaiting_emergence') then
    if v_expected_germination_start is not null and v_expected_germination_start<=v_day then
      v_operations := jsonb_build_array(jsonb_build_object(
        'operationKey','inspect_emergence',
        'timeState','due',
        'knownActiveBy',v_expected_germination_start,
        'basis','expected_germination_boundary',
        'reason','The canonical germination/emergence boundary has arrived or passed while the crop remains in a pre-emergence state.'
      ));
      v_continuation := 'operation_due';
    elsif v_expected_germination_start is not null then
      v_continuation := 'lawful_biological_wait';
      v_next_boundary := jsonb_build_object('kind','expected_germination_start','date',v_expected_germination_start);
      v_reason := 'The crop is lawfully awaiting its canonical emergence boundary.';
    else
      v_operations := jsonb_build_array(jsonb_build_object(
        'operationKey','observe_emergence',
        'timeState','attention_required',
        'knownActiveBy',coalesce(v_anchor_date,v_latest_observed,v_day),
        'basis','pre_emergence_without_timing_model',
        'reason','The crop is physically in a pre-emergence state but lacks a canonical emergence boundary; direct biological observation is required rather than silent waiting.'
      ));
      v_model_gaps := v_model_gaps || jsonb_build_array(jsonb_build_object(
        'gapKey','germination_timing_model_missing',
        'reason','No canonical expected germination boundary is available.'
      ));
      v_continuation := 'operation_due';
    end if;

  elsif v_state='growing' then
    if v_next_harvest_check is not null and v_next_harvest_check<=v_day then
      v_operations := jsonb_build_array(jsonb_build_object(
        'operationKey','inspect_harvest_readiness',
        'timeState','due',
        'knownActiveBy',v_next_harvest_check,
        'basis','explicit_next_harvest_check',
        'consequenceClass',case when v_harvest_pattern='single_cut' then 'narrow_window_single_cut' else 'harvest_watch' end,
        'reason','The most recent biological harvest observation established a recheck date that has arrived or passed.'
      ));
      v_continuation := 'operation_due';
    elsif v_expected_harvest_start is not null and v_expected_harvest_start<=v_day then
      v_operations := jsonb_build_array(jsonb_build_object(
        'operationKey','inspect_harvest_readiness',
        'timeState','due',
        'knownActiveBy',v_expected_harvest_start,
        'basis','expected_harvest_watch_boundary',
        'consequenceClass',case when v_harvest_pattern='single_cut' then 'narrow_window_single_cut' else 'harvest_watch' end,
        'reason','The canonical expected harvest-watch boundary has arrived or passed.'
      ));
      v_continuation := 'operation_due';
    elsif v_expected_clear_date is not null and v_expected_clear_date<=v_day then
      v_operations := jsonb_build_array(jsonb_build_object(
        'operationKey','assess_end_of_cycle',
        'timeState','attention_required',
        'knownActiveBy',v_expected_clear_date,
        'basis','expected_clear_boundary',
        'reason','The expected end-of-cycle boundary has arrived while the crop remains biologically active.'
      ));
      v_continuation := 'operation_due';
    elsif v_expected_harvest_start is not null then
      v_continuation := 'lawful_biological_wait';
      v_next_boundary := jsonb_build_object('kind','expected_harvest_watch_start','date',v_expected_harvest_start);
      v_reason := 'The crop is in normal growth and its canonical harvest-watch boundary remains in the future.';
    elsif v_life_cycle='annual' then
      v_operations := jsonb_build_array(jsonb_build_object(
        'operationKey','observe_crop_progression',
        'timeState','attention_required',
        'knownActiveBy',coalesce(v_latest_observed,v_anchor_date,v_day),
        'basis','annual_growth_without_timing_boundary',
        'reason','The annual crop is growing without a canonical next biological boundary; direct progression observation is required rather than indefinite silent growth.'
      ));
      v_model_gaps := v_model_gaps || jsonb_build_array(jsonb_build_object(
        'gapKey','harvest_watch_timing_model_missing',
        'reason','No canonical harvest-watch boundary is available for this active annual crop.'
      ));
      v_continuation := 'operation_due';
    else
      v_continuation := 'stable_growth_without_current_boundary';
      v_reason := 'No current biological boundary is established for this growing body.';
    end if;

  elsif v_state in ('established','living','established_division') and v_life_cycle in ('perennial','perennial_bulb') then
    v_continuation := 'lawful_dwell';
    v_reason := 'The crop profile establishes durable perennial life and the current state is stable living occupancy with no current harvest or transition signal.';
    v_next_boundary := jsonb_build_object('kind','seasonal_or_observed_condition_change');

  elsif v_state in ('planned','planned_gap_fill') then
    v_continuation := 'planned_not_yet_physical';
    v_reason := 'This crop-cycle record has not yet entered a witnessed physical biological state.';

  else
    v_operations := jsonb_build_array(jsonb_build_object(
      'operationKey','observe_and_reclassify_biological_state',
      'timeState','attention_required',
      'knownActiveBy',coalesce(v_latest_observed,v_anchor_date,v_day),
      'basis','uncovered_active_state',
      'reason','The active living body is not covered by a lawful stable-state rule; a current biological observation is required.'
    ));
    v_continuation := 'operation_due';
    v_model_gaps := v_model_gaps || jsonb_build_array(jsonb_build_object(
      'gapKey','kernel_state_coverage_missing',
      'cycleState',v_state
    ));
  end if;

  return jsonb_build_object(
    'contractVersion','biological_operations_due_v1',
    'subjectKind',p_subject_kind,
    'subjectId',p_subject_id,
    'asOfDate',v_day,
    'continuationState',v_continuation,
    'operationsDue',v_operations,
    'modelGaps',v_model_gaps,
    'nextBoundary',v_next_boundary,
    'reason',v_reason,
    'snapshot',v_snapshot,
    'truthBoundary',jsonb_build_object(
      'operationExistenceComesFromBiology',true,
      'executionReadinessEvaluatedElsewhere',true,
      'lawfulDwellIsAnAffirmativeResult',true,
      'missingModelCoverageCreatesAttentionNotSilence',true
    )
  );
end;
$$;

revoke all on function atlas.biological_operations_due_v1(text,uuid,date) from public, anon;
grant execute on function atlas.biological_operations_due_v1(text,uuid,date) to authenticated, service_role;

comment on function atlas.biological_operations_due_v1(text,uuid,date) is
  'Pure biological operation evaluator. Determines due/attention/wait/dwell from canonical crop biology without consulting human execution or presentation state.';
