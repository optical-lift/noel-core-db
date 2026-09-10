-- Record execution evidence for individual user-confirmed Cleaning requirements without changing room condition.
-- A requirement result says an action was carried or partly carried. It does not say the room is holding,
-- does not create a due/missed claim, and does not complete/deactivate the recurring requirement.

create table if not exists atlas.household_cleaning_requirement_results (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  space_id uuid references atlas.household_spaces(id) on delete set null,
  requirement_id uuid references atlas.household_space_cleaning_requirements(id) on delete set null,
  requirement_stable_key_snapshot text not null,
  action_title_snapshot text not null,
  cadence_rule_snapshot text not null,
  expected_minutes_snapshot integer not null check (expected_minutes_snapshot > 0),
  season_snapshot text not null,
  occurred_at timestamptz not null default now(),
  result_kind text not null check (result_kind in ('carried','partial')),
  note text,
  source text not null default 'personal_cleaning_requirement_result_v1',
  source_action_id text,
  evidence jsonb not null default '{}'::jsonb,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now()
);

create unique index if not exists household_cleaning_requirement_results_request_uidx
  on atlas.household_cleaning_requirement_results(household_id,source_action_id)
  where source_action_id is not null;

create index if not exists household_cleaning_requirement_results_requirement_time_idx
  on atlas.household_cleaning_requirement_results(requirement_id,occurred_at desc)
  where requirement_id is not null;

create index if not exists household_cleaning_requirement_results_space_time_idx
  on atlas.household_cleaning_requirement_results(space_id,occurred_at desc)
  where space_id is not null;

alter table atlas.household_cleaning_requirement_results enable row level security;
revoke all on atlas.household_cleaning_requirement_results from public,anon,authenticated;

create or replace function atlas.record_personal_cleaning_requirement_result_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_requirement_id uuid;
  v_result_kind text;
  v_occurred_at timestamptz;
  v_note text;
  v_source_action_id text;
  v_evidence jsonb;
  v_requirement atlas.household_space_cleaning_requirements%rowtype;
  v_space atlas.household_spaces%rowtype;
  v_existing atlas.household_cleaning_requirement_results%rowtype;
  v_event atlas.household_cleaning_requirement_results%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Cleaning requirement result input must be an object.' using errcode='22023';
  end if;

  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  v_requirement_id:=nullif(trim(p_input->>'requirementId'),'')::uuid;
  v_result_kind:=nullif(trim(p_input->>'resultKind'),'');
  v_occurred_at:=coalesce(nullif(trim(p_input->>'occurredAt'),'')::timestamptz,now());
  v_note:=nullif(trim(p_input->>'note'),'');
  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  v_evidence:=coalesce(p_input->'evidence','{}'::jsonb);

  if v_requirement_id is null then raise exception 'requirementId is required.' using errcode='22023'; end if;
  if v_result_kind not in ('carried','partial') then
    raise exception 'Cleaning requirement resultKind must be carried or partial.' using errcode='22023';
  end if;
  if jsonb_typeof(v_evidence)<>'object' then raise exception 'evidence must be an object.' using errcode='22023'; end if;
  if v_occurred_at > now()+interval '5 minutes' then
    raise exception 'Cleaning requirement result cannot be recorded in the future.' using errcode='22023';
  end if;

  select * into v_requirement
  from atlas.household_space_cleaning_requirements r
  where r.id=v_requirement_id
    and r.household_id=v_household_id
    and r.active;
  if v_requirement.id is null then raise exception 'Active Cleaning requirement not found.' using errcode='22023'; end if;

  select * into v_space
  from atlas.household_spaces s
  where s.id=v_requirement.space_id
    and s.household_id=v_household_id
    and s.active;
  if v_space.id is null then raise exception 'Active household space required.' using errcode='22023'; end if;

  if v_source_action_id is not null then
    select * into v_existing
    from atlas.household_cleaning_requirement_results r
    where r.household_id=v_household_id and r.source_action_id=v_source_action_id;

    if v_existing.id is not null then
      if v_existing.requirement_id is distinct from v_requirement.id
        or v_existing.result_kind is distinct from v_result_kind then
        raise exception 'sourceActionId already belongs to a different Cleaning result.' using errcode='23505';
      end if;

      return jsonb_build_object(
        'ok',true,
        'contractVersion','personal_cleaning_requirement_result_v1',
        'idempotentReplay',true,
        'event',jsonb_build_object(
          'id',v_existing.id,
          'requirementId',v_existing.requirement_id,
          'spaceId',v_existing.space_id,
          'resultKind',v_existing.result_kind,
          'occurredAt',v_existing.occurred_at,
          'note',v_existing.note
        ),
        'requirement',jsonb_build_object('id',v_requirement.id,'actionTitle',v_requirement.action_title),
        'space',jsonb_build_object('id',v_space.id,'name',v_space.name),
        'roomConditionChanged',false
      );
    end if;
  end if;

  insert into atlas.household_cleaning_requirement_results(
    household_id,space_id,requirement_id,
    requirement_stable_key_snapshot,action_title_snapshot,cadence_rule_snapshot,
    expected_minutes_snapshot,season_snapshot,
    occurred_at,result_kind,note,source,source_action_id,evidence,created_by_user_id
  ) values(
    v_household_id,v_space.id,v_requirement.id,
    v_requirement.stable_key,v_requirement.action_title,v_requirement.cadence_rule,
    v_requirement.expected_minutes,v_requirement.season,
    v_occurred_at,v_result_kind,v_note,'personal_cleaning_requirement_result_v1',v_source_action_id,v_evidence,auth.uid()
  ) returning * into v_event;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_requirement_result_v1',
    'idempotentReplay',false,
    'event',jsonb_build_object(
      'id',v_event.id,
      'requirementId',v_event.requirement_id,
      'spaceId',v_event.space_id,
      'resultKind',v_event.result_kind,
      'occurredAt',v_event.occurred_at,
      'note',v_event.note
    ),
    'requirement',jsonb_build_object(
      'id',v_requirement.id,
      'actionTitle',v_requirement.action_title,
      'cadenceRule',v_requirement.cadence_rule,
      'expectedMinutes',v_requirement.expected_minutes,
      'season',v_requirement.season
    ),
    'space',jsonb_build_object('id',v_space.id,'name',v_space.name,'spaceType',v_space.space_type),
    'roomConditionChanged',false
  );
end;
$function$;

revoke all on function atlas.record_personal_cleaning_requirement_result_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.record_personal_cleaning_requirement_result_self_api_v1(jsonb) to authenticated,service_role;

create or replace function public.record_personal_cleaning_requirement_result_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.record_personal_cleaning_requirement_result_self_api_v1(p_input); $function$;

revoke all on function public.record_personal_cleaning_requirement_result_self_api_v1(jsonb) from public,anon;
grant execute on function public.record_personal_cleaning_requirement_result_self_api_v1(jsonb) to authenticated,service_role;

-- Replace the daily planning helper so requirement-level result evidence informs attention without becoming
-- room-condition truth or a fake due/completion state.
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
  v_day_start timestamptz;
  v_day_end timestamptz;
  v_candidate_count integer := 0;
  v_requirement_count integer := 0;
  v_space_id uuid;
  v_space_name text;
  v_space_type text;
  v_condition_state text;
  v_disposition text;
  v_condition_known boolean := false;
  v_last_observed_at timestamptz;
  v_last_room_result_at timestamptz;
  v_last_requirement_result_at timestamptz;
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

  select h.timezone into v_timezone
  from atlas.households h
  where h.id=p_household_id and h.status='active';
  if v_timezone is null then raise exception 'Active household required.' using errcode='P0002'; end if;

  v_day_start:=p_day::timestamp at time zone v_timezone;
  v_day_end:=(p_day+1)::timestamp at time zone v_timezone;

  select count(*)::integer into v_candidate_count
  from atlas.household_cleaning_zone_assignments a
  join atlas.household_spaces s on s.id=a.space_id and s.household_id=p_household_id and s.active and s.care_relevant
  join atlas.household_zones z on z.id=a.zone_id and z.household_id=p_household_id and z.active
    and z.zone_number=p_zone_number and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention'
  where a.household_id=p_household_id;

  if v_candidate_count=0 then
    return jsonb_build_object(
      'minutes',p_minutes,'selectionKind','attention_projection','candidateSpaceCount',0,
      'selectedRoom',null,'selectedActions','[]'::jsonb,
      'attentionInstruction','No rooms confirmed in this attention zone yet.'
    );
  end if;

  with latest_room_results as (
    select r.subject_id,max(r.occurred_at) as last_result_at
    from atlas.care_result_events r
    where r.subject_domain='household'
      and r.subject_kind='household_space'
      and r.scope_kind='household'
      and r.scope_id=p_household_id
      and r.occurred_at<v_day_end
    group by r.subject_id
  ), latest_requirement_results as (
    select r.space_id,max(r.occurred_at) as last_result_at
    from atlas.household_cleaning_requirement_results r
    where r.household_id=p_household_id
      and r.space_id is not null
      and r.occurred_at<v_day_end
    group by r.space_id
  ), candidates as (
    select
      s.id,s.name,s.space_type,
      case when cs.last_observed_at<v_day_end then cs.condition_state else null end as condition_state,
      case when cs.last_observed_at<v_day_end then cs.disposition else null end as disposition,
      (cs.id is not null and cs.last_observed_at<v_day_end) as condition_known,
      case when cs.last_observed_at<v_day_end then cs.last_observed_at else null end as last_observed_at,
      lrr.last_result_at as last_room_result_at,
      lqr.last_result_at as last_requirement_result_at,
      case when cs.last_observed_at<v_day_end then cs.next_reassess_at else null end as next_reassess_at,
      exists(
        select 1
        from atlas.household_space_cleaning_requirements req
        join atlas.household_rhythms rhythm on rhythm.id=req.rhythm_id and rhythm.active
        where req.household_id=p_household_id and req.space_id=s.id and req.active
          and coalesce(rhythm.metadata->>'clockWindowEstablished','false')='true'
          and rhythm.next_window_start is not null
          and (rhythm.next_window_start at time zone v_timezone)::date<=p_day
          and (coalesce(rhythm.next_window_end,rhythm.next_window_start) at time zone v_timezone)::date>=p_day
      ) as has_clock_window,
      case
        when exists(
          select 1 from atlas.household_space_cleaning_requirements req
          join atlas.household_rhythms rhythm on rhythm.id=req.rhythm_id and rhythm.active
          where req.household_id=p_household_id and req.space_id=s.id and req.active
            and coalesce(rhythm.metadata->>'clockWindowEstablished','false')='true'
            and rhythm.next_window_start is not null
            and (rhythm.next_window_start at time zone v_timezone)::date<=p_day
            and (coalesce(rhythm.next_window_end,rhythm.next_window_start) at time zone v_timezone)::date>=p_day
        ) then 0
        when cs.last_observed_at<v_day_end and cs.condition_state='recovery_needed' then 1
        when cs.last_observed_at<v_day_end and cs.condition_state='losing_shape' then 2
        when cs.last_observed_at<v_day_end and cs.condition_state='needs_attention' then 3
        when cs.last_observed_at<v_day_end and cs.next_reassess_at is not null
          and (cs.next_reassess_at at time zone v_timezone)::date<=p_day then 4
        when cs.id is null or cs.last_observed_at>=v_day_end or cs.condition_state='unknown' then 5
        when cs.condition_state='holding' then 6
        else 5
      end as priority_bucket,
      greatest(
        coalesce(case when cs.last_observed_at<v_day_end then cs.last_observed_at end,'epoch'::timestamptz),
        coalesce(lrr.last_result_at,'epoch'::timestamptz),
        coalesce(lqr.last_result_at,'epoch'::timestamptz)
      ) as last_touch_at
    from atlas.household_cleaning_zone_assignments a
    join atlas.household_spaces s on s.id=a.space_id and s.household_id=p_household_id and s.active and s.care_relevant
    join atlas.household_zones z on z.id=a.zone_id and z.household_id=p_household_id and z.active
      and z.zone_number=p_zone_number and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention'
    left join atlas.care_current_state cs on cs.subject_domain='household' and cs.subject_kind='household_space'
      and cs.subject_id=s.id::text and cs.scope_kind='household' and cs.scope_id=p_household_id
    left join latest_room_results lrr on lrr.subject_id=s.id::text
    left join latest_requirement_results lqr on lqr.space_id=s.id
    where a.household_id=p_household_id
  )
  select
    c.id,c.name,c.space_type,c.condition_state,c.disposition,c.condition_known,c.last_observed_at,
    c.last_room_result_at,c.last_requirement_result_at,c.next_reassess_at,c.has_clock_window
  into
    v_space_id,v_space_name,v_space_type,v_condition_state,v_disposition,v_condition_known,v_last_observed_at,
    v_last_room_result_at,v_last_requirement_result_at,v_next_reassess_at,v_has_clock_window
  from candidates c
  order by c.priority_bucket,c.last_touch_at,md5(c.id::text||':'||p_day::text),c.id
  limit 1;

  v_condition_state:=coalesce(v_condition_state,'unknown');
  v_disposition:=coalesce(v_disposition,'reassess');

  if v_has_clock_window then
    v_reason_key:='clock_window';
    v_reason:='A real Cleaning window is established for this room today.';
  elsif v_condition_state='recovery_needed' then
    v_reason_key:='recovery_needed'; v_reason:='This room was last observed as needing recovery.';
  elsif v_condition_state='losing_shape' then
    v_reason_key:='losing_shape'; v_reason:='This room was last observed as losing shape.';
  elsif v_condition_state='needs_attention' then
    v_reason_key:='needs_attention'; v_reason:='This room was last observed as needing attention.';
  elsif v_next_reassess_at is not null and (v_next_reassess_at at time zone v_timezone)::date<=p_day then
    v_reason_key:='reassessment_reached'; v_reason:='This room has reached its next explicit reassessment.';
  elsif not v_condition_known or v_condition_state='unknown' then
    v_reason_key:='not_observed'; v_reason:='This room has not been observed clearly yet.';
  else
    v_reason_key:='fairness';
    v_reason:='This room has gone longest without recent attention evidence among the rooms in this zone.';
  end if;

  select count(*)::integer into v_requirement_count
  from atlas.household_space_cleaning_requirements req
  where req.household_id=p_household_id and req.space_id=v_space_id and req.active;

  with requirements as (
    select
      req.id,req.action_title,req.cadence_rule,req.expected_minutes,req.season,req.rhythm_id,
      (
        coalesce(rhythm.metadata->>'clockWindowEstablished','false')='true'
        and rhythm.next_window_start is not null
        and (rhythm.next_window_start at time zone v_timezone)::date<=p_day
        and (coalesce(rhythm.next_window_end,rhythm.next_window_start) at time zone v_timezone)::date>=p_day
      ) as scheduled_for_day,
      lr.occurred_at as last_result_at,
      lr.result_kind as last_result_kind,
      exists(
        select 1
        from atlas.household_cleaning_requirement_results today_result
        where today_result.household_id=p_household_id
          and today_result.requirement_id=req.id
          and today_result.result_kind='carried'
          and today_result.occurred_at>=v_day_start
          and today_result.occurred_at<v_day_end
      ) as carried_today,
      md5(req.id::text||':'||p_day::text) as rotation_key
    from atlas.household_space_cleaning_requirements req
    left join atlas.household_rhythms rhythm on rhythm.id=req.rhythm_id and rhythm.active
    left join lateral (
      select rr.occurred_at,rr.result_kind
      from atlas.household_cleaning_requirement_results rr
      where rr.household_id=p_household_id
        and rr.requirement_id=req.id
        and rr.occurred_at<v_day_end
      order by rr.occurred_at desc,rr.id desc
      limit 1
    ) lr on true
    where req.household_id=p_household_id and req.space_id=v_space_id and req.active
  ), remaining as (
    select * from requirements where not carried_today
  ), ordered as (
    select
      r.*,
      row_number() over(
        order by r.scheduled_for_day desc,
          case when r.last_result_at is null then 0 else 1 end,
          r.last_result_at asc nulls first,
          case when r.last_result_kind='partial' then 0 else 1 end,
          r.rotation_key,r.id
      ) as selection_order,
      sum(r.expected_minutes) over(
        order by r.scheduled_for_day desc,
          case when r.last_result_at is null then 0 else 1 end,
          r.last_result_at asc nulls first,
          case when r.last_result_kind='partial' then 0 else 1 end,
          r.rotation_key,r.id
        rows between unbounded preceding and current row
      ) as cumulative_minutes
    from remaining r
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,
    'actionTitle',o.action_title,
    'cadenceRule',o.cadence_rule,
    'expectedMinutes',o.expected_minutes,
    'season',o.season,
    'rhythmId',o.rhythm_id,
    'clockWindowEstablished',o.scheduled_for_day,
    'scheduledForDay',o.scheduled_for_day,
    'fitsBudget',o.cumulative_minutes<=p_minutes,
    'lastResultAt',o.last_result_at,
    'lastResultKind',o.last_result_kind
  ) order by o.selection_order),'[]'::jsonb)
  into v_actions
  from ordered o
  where o.cumulative_minutes<=p_minutes or o.selection_order=1;

  if jsonb_array_length(v_actions)>0 then
    v_instruction:='Give '||v_space_name||' up to '||p_minutes::text||' minutes. These are starting points, not completion claims.';
  elsif v_requirement_count>0 then
    v_instruction:='The known Cleaning requirements for '||v_space_name||' have already been carried today.';
  else
    v_instruction:='Spend up to '||p_minutes::text||' minutes restoring '||v_space_name||'. No specific Cleaning requirements are mapped here yet.';
  end if;

  return jsonb_build_object(
    'minutes',p_minutes,
    'selectionKind','attention_projection',
    'candidateSpaceCount',v_candidate_count,
    'selectedRoom',jsonb_build_object(
      'id',v_space_id,'name',v_space_name,'spaceType',v_space_type,
      'conditionState',v_condition_state,'disposition',v_disposition,'conditionKnown',v_condition_known,
      'lastObservedAt',v_last_observed_at,
      'lastRoomResultAt',v_last_room_result_at,
      'lastRequirementResultAt',v_last_requirement_result_at,
      'lastResultAt',greatest(coalesce(v_last_room_result_at,'epoch'::timestamptz),coalesce(v_last_requirement_result_at,'epoch'::timestamptz)),
      'nextReassessAt',v_next_reassess_at,
      'selectionReasonKey',v_reason_key,'selectionReason',v_reason
    ),
    'selectedActions',v_actions,
    'attentionInstruction',v_instruction,
    'truthBoundary',jsonb_build_object(
      'requirementResultsAreExecutionEvidence',true,
      'requirementResultsDoNotSetRoomCondition',true,
      'noMissedInferenceFromSemanticCadence',true
    )
  );
end;
$function$;

revoke all on function atlas.personal_cleaning_day_attention_v1(uuid,date,integer,integer) from public,anon,authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values(
  'atlas.record_personal_cleaning_requirement_result_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append carried/partial execution evidence for one canonical room Cleaning requirement without changing room condition or inventing missed/due state.',
    'roomConditionChanged',false,
    'missedInferenceAllowed',false
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
