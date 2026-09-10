-- Turn the standing five-zone Cleaning exposure into a bounded daily attention projection.
--
-- Canonical truth remains separate:
--   * household_spaces = real rooms/spaces
--   * household_space_cleaning_requirements = durable user-confirmed recurring requirements
--   * household_cleaning_zone_assignments = confirmed room -> FlyLady attention zone
--   * care_current_state / care_result_events = room-level observed condition and results
--   * household_rhythms = semantic cadence, plus Clock windows only when explicitly established
--
-- This migration does NOT create daily task rows and does NOT infer that a semantic cadence is due.
-- The selector is a recomputed planning projection: choose one room receiving attention today, then fit
-- a small deterministic subset of that room's canonical requirements into the zone's attention budget.

create or replace function atlas.personal_cleaning_day_attention_v1(
  p_household_id uuid,
  p_day date,
  p_zone_number integer,
  p_minutes integer default 15
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_timezone text;
  v_candidate_count integer := 0;
  v_space_id uuid;
  v_space_name text;
  v_space_type text;
  v_condition_state text;
  v_disposition text;
  v_condition_known boolean := false;
  v_last_observed_at timestamptz;
  v_last_result_at timestamptz;
  v_next_reassess_at timestamptz;
  v_has_clock_window boolean := false;
  v_reason_key text;
  v_reason text;
  v_actions jsonb := '[]'::jsonb;
  v_instruction text;
begin
  if p_household_id is null or p_day is null or p_zone_number not between 1 and 5 then
    raise exception 'household, day, and Cleaning zone 1 through 5 are required.' using errcode='22023';
  end if;
  if p_minutes is null or p_minutes <= 0 then
    raise exception 'Cleaning attention minutes must be positive.' using errcode='22023';
  end if;

  select h.timezone
    into v_timezone
  from atlas.households h
  where h.id=p_household_id and h.status='active';

  if v_timezone is null then
    raise exception 'Active household required.' using errcode='P0002';
  end if;

  select count(*)::integer
    into v_candidate_count
  from atlas.household_cleaning_zone_assignments a
  join atlas.household_spaces s
    on s.id=a.space_id
   and s.household_id=p_household_id
   and s.active
   and s.care_relevant
  join atlas.household_zones z
    on z.id=a.zone_id
   and z.household_id=p_household_id
   and z.active
   and z.zone_number=p_zone_number
   and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention'
  where a.household_id=p_household_id;

  if v_candidate_count=0 then
    return jsonb_build_object(
      'minutes',p_minutes,
      'selectionKind','attention_projection',
      'candidateSpaceCount',0,
      'selectedRoom',null,
      'selectedActions','[]'::jsonb,
      'attentionInstruction','No rooms confirmed in this attention zone yet.'
    );
  end if;

  with latest_results as (
    select
      r.subject_id::uuid as space_id,
      max(r.occurred_at) as last_result_at
    from atlas.care_result_events r
    where r.subject_domain='household'
      and r.subject_kind='household_space'
      and r.scope_kind='household'
      and r.scope_id=p_household_id
    group by r.subject_id
  ), candidates as (
    select
      s.id,
      s.name,
      s.space_type,
      cs.condition_state,
      cs.disposition,
      cs.id is not null as condition_known,
      cs.last_observed_at,
      lr.last_result_at,
      cs.next_reassess_at,
      exists(
        select 1
        from atlas.household_space_cleaning_requirements req
        join atlas.household_rhythms rhythm on rhythm.id=req.rhythm_id and rhythm.active
        where req.household_id=p_household_id
          and req.space_id=s.id
          and req.active
          and coalesce(rhythm.metadata->>'clockWindowEstablished','false')='true'
          and rhythm.next_window_start is not null
          and (rhythm.next_window_start at time zone v_timezone)::date <= p_day
          and (coalesce(rhythm.next_window_end,rhythm.next_window_start) at time zone v_timezone)::date >= p_day
      ) as has_clock_window,
      case
        when exists(
          select 1
          from atlas.household_space_cleaning_requirements req
          join atlas.household_rhythms rhythm on rhythm.id=req.rhythm_id and rhythm.active
          where req.household_id=p_household_id
            and req.space_id=s.id
            and req.active
            and coalesce(rhythm.metadata->>'clockWindowEstablished','false')='true'
            and rhythm.next_window_start is not null
            and (rhythm.next_window_start at time zone v_timezone)::date <= p_day
            and (coalesce(rhythm.next_window_end,rhythm.next_window_start) at time zone v_timezone)::date >= p_day
        ) then 0
        when cs.condition_state='recovery_needed' then 1
        when cs.condition_state='losing_shape' then 2
        when cs.condition_state='needs_attention' then 3
        when cs.next_reassess_at is not null
          and (cs.next_reassess_at at time zone v_timezone)::date <= p_day then 4
        when cs.id is null or cs.condition_state='unknown' then 5
        when cs.condition_state='holding' then 6
        else 5
      end as priority_bucket,
      greatest(
        coalesce(cs.last_observed_at,'epoch'::timestamptz),
        coalesce(lr.last_result_at,'epoch'::timestamptz)
      ) as last_touch_at
    from atlas.household_cleaning_zone_assignments a
    join atlas.household_spaces s
      on s.id=a.space_id
     and s.household_id=p_household_id
     and s.active
     and s.care_relevant
    join atlas.household_zones z
      on z.id=a.zone_id
     and z.household_id=p_household_id
     and z.active
     and z.zone_number=p_zone_number
     and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention'
    left join atlas.care_current_state cs
      on cs.subject_domain='household'
     and cs.subject_kind='household_space'
     and cs.subject_id=s.id::text
     and cs.scope_kind='household'
     and cs.scope_id=p_household_id
    left join latest_results lr on lr.space_id=s.id
    where a.household_id=p_household_id
  )
  select
    c.id,c.name,c.space_type,c.condition_state,c.disposition,c.condition_known,
    c.last_observed_at,c.last_result_at,c.next_reassess_at,c.has_clock_window
  into
    v_space_id,v_space_name,v_space_type,v_condition_state,v_disposition,v_condition_known,
    v_last_observed_at,v_last_result_at,v_next_reassess_at,v_has_clock_window
  from candidates c
  order by
    c.priority_bucket,
    c.last_touch_at,
    md5(c.id::text||':'||p_day::text),
    c.id
  limit 1;

  v_condition_state:=coalesce(v_condition_state,'unknown');
  v_disposition:=coalesce(v_disposition,'reassess');

  if v_has_clock_window then
    v_reason_key:='clock_window';
    v_reason:='A real Cleaning window is established for this room today.';
  elsif v_condition_state='recovery_needed' then
    v_reason_key:='recovery_needed';
    v_reason:='This room was last observed as needing recovery.';
  elsif v_condition_state='losing_shape' then
    v_reason_key:='losing_shape';
    v_reason:='This room was last observed as losing shape.';
  elsif v_condition_state='needs_attention' then
    v_reason_key:='needs_attention';
    v_reason:='This room was last observed as needing attention.';
  elsif v_next_reassess_at is not null
    and (v_next_reassess_at at time zone v_timezone)::date <= p_day then
    v_reason_key:='reassessment_reached';
    v_reason:='This room has reached its next explicit reassessment.';
  elsif not v_condition_known or v_condition_state='unknown' then
    v_reason_key:='not_observed';
    v_reason:='This room has not been observed clearly yet.';
  else
    v_reason_key:='fairness';
    v_reason:='This room has gone longest without recent attention evidence among the rooms in this zone.';
  end if;

  with requirements as (
    select
      req.id,
      req.action_title,
      req.cadence_rule,
      req.expected_minutes,
      req.season,
      req.rhythm_id,
      (
        coalesce(rhythm.metadata->>'clockWindowEstablished','false')='true'
        and rhythm.next_window_start is not null
        and (rhythm.next_window_start at time zone v_timezone)::date <= p_day
        and (coalesce(rhythm.next_window_end,rhythm.next_window_start) at time zone v_timezone)::date >= p_day
      ) as scheduled_for_day,
      md5(req.id::text||':'||p_day::text) as rotation_key
    from atlas.household_space_cleaning_requirements req
    left join atlas.household_rhythms rhythm
      on rhythm.id=req.rhythm_id
     and rhythm.active
    where req.household_id=p_household_id
      and req.space_id=v_space_id
      and req.active
  ), ordered as (
    select
      r.*,
      row_number() over(
        order by r.scheduled_for_day desc,r.rotation_key,r.id
      ) as selection_order,
      sum(r.expected_minutes) over(
        order by r.scheduled_for_day desc,r.rotation_key,r.id
        rows between unbounded preceding and current row
      ) as cumulative_minutes
    from requirements r
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id',o.id,
      'actionTitle',o.action_title,
      'cadenceRule',o.cadence_rule,
      'expectedMinutes',o.expected_minutes,
      'season',o.season,
      'rhythmId',o.rhythm_id,
      'clockWindowEstablished',o.scheduled_for_day,
      'scheduledForDay',o.scheduled_for_day,
      'fitsBudget',o.cumulative_minutes<=p_minutes
    )
    order by o.selection_order
  ),'[]'::jsonb)
  into v_actions
  from ordered o
  where o.cumulative_minutes<=p_minutes or o.selection_order=1;

  if jsonb_array_length(v_actions)=0 then
    v_instruction:='Spend up to '||p_minutes::text||' minutes restoring '||v_space_name||'.';
  else
    v_instruction:='Give '||v_space_name||' up to '||p_minutes::text||' minutes. These are starting points, not completion claims.';
  end if;

  return jsonb_build_object(
    'minutes',p_minutes,
    'selectionKind','attention_projection',
    'candidateSpaceCount',v_candidate_count,
    'selectedRoom',jsonb_build_object(
      'id',v_space_id,
      'name',v_space_name,
      'spaceType',v_space_type,
      'conditionState',v_condition_state,
      'disposition',v_disposition,
      'conditionKnown',v_condition_known,
      'lastObservedAt',v_last_observed_at,
      'lastResultAt',v_last_result_at,
      'nextReassessAt',v_next_reassess_at,
      'selectionReasonKey',v_reason_key,
      'selectionReason',v_reason
    ),
    'selectedActions',v_actions,
    'attentionInstruction',v_instruction
  );
end;
$function$;

revoke all on function atlas.personal_cleaning_day_attention_v1(uuid,date,integer,integer) from public,anon,authenticated;

create or replace function atlas.personal_cleaning_week_self_api_v1(p_anchor_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_week_start date;
  v_week_end date;
  v_zone_minutes integer := 15;
  v_zones jsonb := '[]'::jsonb;
  v_spaces jsonb := '[]'::jsonb;
  v_days jsonb := '[]'::jsonb;
  v_objects jsonb := '[]'::jsonb;
  v_blessings jsonb := jsonb_build_array(
    jsonb_build_object('key','trash','title','Gather household trash'),
    jsonb_build_object('key','sheets','title','Change sheets'),
    jsonb_build_object('key','dust','title','Quick whole-house dust'),
    jsonb_build_object('key','glass','title','Shine mirrors / door glass'),
    jsonb_build_object('key','hotspots','title','Clear hot spots'),
    jsonb_build_object('key','vacuum','title','Vacuum the middles'),
    jsonb_build_object('key','mop','title','Quick mop kitchen / bathrooms')
  );
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  v_week_start:=p_anchor_date-(extract(isodow from p_anchor_date)::integer-1);
  v_week_end:=v_week_start+6;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',z.id,
    'zoneNumber',z.zone_number,
    'name',z.name,
    'minutes',coalesce(nullif(z.metadata->>'zoneMinutes','')::integer,v_zone_minutes)
  ) order by z.zone_number),'[]'::jsonb)
  into v_zones
  from atlas.household_zones z
  where z.household_id=v_household_id
    and z.active
    and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'name',s.name,
    'spaceType',s.space_type,
    'confirmedZoneNumber',z.zone_number,
    'suggestedZoneNumber',atlas.flylady_suggested_zone_for_space_v1(s.space_type,s.functional_tags),
    'requirements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'actionTitle',r.action_title,
        'cadenceRule',r.cadence_rule,
        'expectedMinutes',r.expected_minutes,
        'season',r.season
      ) order by r.created_at,r.id)
      from atlas.household_space_cleaning_requirements r
      where r.household_id=v_household_id and r.space_id=s.id and r.active
    ),'[]'::jsonb)
  ) order by s.created_at,s.id),'[]'::jsonb)
  into v_spaces
  from atlas.household_spaces s
  left join atlas.household_cleaning_zone_assignments a
    on a.space_id=s.id and a.household_id=v_household_id
  left join atlas.household_zones z on z.id=a.zone_id and z.active
  where s.household_id=v_household_id and s.active and s.care_relevant;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date',d.day,
    'dayName',trim(to_char(d.day,'FMDay')),
    'isoDow',extract(isodow from d.day)::integer,
    'zoneNumber',d.zone_number,
    'zoneName',z.name,
    'zoneFocus',case
      when extract(isodow from d.day)::integer between 1 and 5 then
        atlas.personal_cleaning_day_attention_v1(
          v_household_id,
          d.day,
          d.zone_number,
          coalesce(nullif(z.metadata->>'zoneMinutes','')::integer,v_zone_minutes)
        )
      else null
    end,
    'weeklyHomeBlessing',case when extract(isodow from d.day)::integer=1 then v_blessings else '[]'::jsonb end
  ) order by d.day),'[]'::jsonb)
  into v_days
  from (
    select g::date as day,atlas.flylady_zone_number_for_date_v1(g::date) as zone_number
    from generate_series(v_week_start,v_week_end,interval '1 day') g
  ) d
  left join atlas.household_zones z
    on z.household_id=v_household_id
    and z.zone_number=d.zone_number
    and z.active
    and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,
    'name',o.name,
    'spaceName',s.name,
    'actionTitle',r.action_title,
    'cadenceRule',r.cadence_rule,
    'expectedMinutes',r.expected_minutes,
    'season',r.season
  ) order by o.name,r.action_title),'[]'::jsonb)
  into v_objects
  from atlas.household_care_objects o
  join atlas.household_object_care_requirements r
    on r.object_id=o.id and r.active and r.care_kind='cleaning'
  left join atlas.household_spaces s on s.id=o.space_id
  where o.household_id=v_household_id and o.active;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_week_self_api_v1',
    'attentionPolicy',jsonb_build_object(
      'key','atlas_cleaning_flylady_attention',
      'sourceMethod','FlyLady five-zone rotation',
      'zoneMinutes',v_zone_minutes,
      'zoneWeekStarts','sunday',
      'spreadWeekStarts','monday',
      'physicalConditionClaim',false,
      'optional',false
    ),
    'anchorDate',p_anchor_date,
    'weekStart',v_week_start,
    'weekEnd',v_week_end,
    'zones',v_zones,
    'spaces',v_spaces,
    'days',v_days,
    'weeklyHomeBlessingItems',v_blessings,
    'specialObjectCare',v_objects,
    'truthBoundary',jsonb_build_object(
      'spacesAreRealSubjects',true,
      'zoneAssignmentsAreConfirmedTruth',true,
      'suggestedZonesAreNotTruth',true,
      'zoneCalendarIsAttentionExposure',true,
      'zoneCalendarDoesNotClaimPhysicalCondition',true,
      'roomRequirementsRemainCanonical',true,
      'currentRoomConditionIsSeparate',true,
      'dailySelectionIsPlanningProjection',true,
      'selectedActionsAreNotCompletionClaims',true,
      'semanticCadenceDoesNotMeanDue',true,
      'roomConditionMayPrioritizeAttention',true,
      'clockWindowCountsOnlyWhenEstablished',true,
      'objectCareRemainsSeparate',true,
      'flyLadyIsNotASelectableModel',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_cleaning_week_self_api_v1(date) from public,anon;
grant execute on function atlas.personal_cleaning_week_self_api_v1(date) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values(
  'atlas.personal_cleaning_week_self_api_v1(p_anchor_date date)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Expose the standing five-zone Cleaning week with one bounded, truth-preserving room/action attention choice per workday.',
    'dailySelectionIsPlanningProjection',true,
    'semanticCadenceDoesNotMeanDue',true
  ),now()
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();
