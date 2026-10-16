-- SOURCE CANDIDATE ONLY: not a released migration.
-- Read-only Personal week context and provisional placement proposal.
-- No recurrence authority, schedule write, task, Clock replacement or inferred calendar facts.

create or replace function atlas.personal_week_planning_context_self_api_v1(
  p_week_of date default null
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_person uuid;
  v_atlas uuid;
  v_principal uuid;
  v_household uuid;
  v_zone text;
  v_today date;
  v_monday date;
  v_days jsonb;
  v_discovery jsonb;
  v_kernel_count integer;
  v_policy_count integer;
  v_event_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authenticated Personal Atlas required.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  if v_person is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;
  select a.id into v_atlas
  from personal.atlases a
  where a.person_entity_id=v_person and a.atlas_state='active' and a.native
  order by a.id limit 1;
  if v_atlas is null then
    raise exception 'Active native Personal Atlas required.' using errcode='42501';
  end if;
  v_principal:=atlas.personal_atlas_compatibility_principal_id_v1(v_person);
  if v_principal is null then
    raise exception 'Unique Personal compatibility carrier required.' using errcode='42501';
  end if;
  select h.id,h.timezone into v_household,v_zone
  from atlas.principals p
  join atlas.households h on h.id=p.active_household_id and h.status='active'
  where p.id=v_principal and p.person_id=v_person and p.status='active'
  limit 1;
  if v_household is null or nullif(v_zone,'') is null then
    raise exception 'Current Personal household and timezone required.' using errcode='42501';
  end if;
  v_today:=(statement_timestamp() at time zone v_zone)::date;
  v_monday:=coalesce(p_week_of,v_today);
  v_monday:=v_monday-(extract(isodow from v_monday)::integer-1);
  if v_monday < (v_today-14) or v_monday > (v_today+21) then
    raise exception 'Personal placement preview is limited to a near-term week.' using errcode='22023';
  end if;

  select count(*)::integer into v_policy_count from atlas.principal_capacity_policies cp
  where cp.principal_id=v_principal and cp.active
    and cp.effective_from <= v_monday+6
    and (cp.effective_through is null or cp.effective_through >= v_monday);

  select count(*)::integer into v_event_count from atlas.household_events e
  where e.household_id=v_household and e.ends_at > (v_monday::timestamp at time zone v_zone)
    and e.starts_at < ((v_monday+7)::timestamp at time zone v_zone);

  select count(*)::integer into v_kernel_count
  from atlas.household_kernel_instances k
  where k.household_id=v_household and k.state='active';

  v_discovery:=atlas.reality_discovery_context_self_api_v1();
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'localDate',d.day::text,
      'capacity',atlas.principal_capacity_day_state_v1(v_principal,d.day),
      'fixedHouseholdEvents',coalesce((
        select jsonb_agg(jsonb_build_object(
          'sourceKind','household_event','sourceId',e.id,'title',e.title,
          'startsAt',e.starts_at,'endsAt',e.ends_at,
          'fixed',e.fixed,'blocksCapacity',e.blocks_capacity)
          order by e.starts_at,e.id)
        from atlas.household_events e
        where e.household_id=v_household
          and e.starts_at < ((d.day+1)::timestamp at time zone v_zone)
          and e.ends_at > (d.day::timestamp at time zone v_zone)
          and e.fixed
      ),'[]'::jsonb),
      'ownerObligations',coalesce((
        select jsonb_agg(jsonb_build_object(
          'sourceKind','owner_obligation','sourceId',o.id,'title',o.title,
          'fixedAt',o.fixed_at,'mustBeginBy',o.must_begin_by,
          'mustFinishBy',o.must_finish_by,'expectedMinutes',o.expected_minutes)
          order by coalesce(o.fixed_at,o.must_begin_by,o.must_finish_by),o.id)
        from atlas.owner_obligations o
        where o.principal_id=v_principal
          and o.status not in ('completed','cancelled')
          and (
            (o.fixed_at at time zone v_zone)::date=d.day
            or (o.must_begin_by at time zone v_zone)::date=d.day
            or (o.must_finish_by at time zone v_zone)::date=d.day
          )
      ),'[]'::jsonb),
      'currentRhythmWindows',coalesce((
        select jsonb_agg(jsonb_build_object(
          'sourceKind','household_rhythm','sourceId',r.id,'title',r.title,
          'expectedMinutes',r.expected_minutes,
          'windowStart',r.next_window_start,'windowEnd',r.next_window_end)
          order by r.title,r.id)
        from atlas.household_rhythms r
        where r.household_id=v_household and r.active
          and r.next_window_start < ((d.day+1)::timestamp at time zone v_zone)
          and r.next_window_end > (d.day::timestamp at time zone v_zone)
      ),'[]'::jsonb)
    ) order by d.day),'[]'::jsonb)
  into v_days
  from (
    select (v_monday+g.day_number)::date as day
    from generate_series(0,6) g(day_number)
  ) d;

  return jsonb_build_object(
    'ok',true,'contractVersion','personal_week_planning_context_self_api_v1',
    'weekStart',v_monday::text,'weekEnd',(v_monday+6)::text,
    'timezone',v_zone,'householdId',v_household,'personEntityId',v_person,
    'days',v_days,
    'discovery',jsonb_build_object(
      'weekdayAnchor',v_discovery#>'{answers,life.weekday_anchor}',
      'workStructure',v_discovery#>'{answers,work.structure}'
    ),
    'sourceCoverage',jsonb_build_object(
      'capacityPoliciesFound',v_policy_count,
      'fixedHouseholdEventsFound',v_event_count,
      'activeHouseholdKernelsFound',v_kernel_count,
      'externalCalendarCoverageEstablished',false,
      'recordAbsenceDoesNotEstablishFreeTime',true
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,'sourcePreserved',true,
      'capacityUnknownWithoutEffectivePolicy',true,
      'noCalendarEventCopies',true,
      'doesNotAdmitClockWork',true,
      'noScheduleMutation',true,
      'noCrossKernelDependencyInferred',true
    )
  );
end
$function$;

revoke all on function atlas.personal_week_planning_context_self_api_v1(date)
  from public,anon,authenticated;
create or replace function public.personal_week_planning_context_self_api_v1(
  p_week_of date default null
) returns jsonb
language sql stable security definer set search_path to ''
as $function$
  select atlas.personal_week_planning_context_self_api_v1(p_week_of);
$function$;
revoke all on function public.personal_week_planning_context_self_api_v1(date) from public,anon;
grant execute on function public.personal_week_planning_context_self_api_v1(date) to authenticated;

create or replace function atlas.personal_week_work_fit_preview_self_api_v1(
  p_kernel_key text,
  p_week_of date default null,
  p_before_household_event_id uuid default null,
  p_estimated_minutes integer default null
) returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_context jsonb;
  v_days jsonb;
  v_household uuid;
  v_anchor_date date;
  v_anchor_title text;
  v_week_start date;
  v_duration integer;
  v_kernel_title text;
  v_days_known integer;
  v_eligible integer;
  v_ranked jsonb;
  v_selected jsonb;
  v_alternates jsonb;
  v_state text;
begin
  if p_kernel_key not in ('household.cleaning','household.laundry','household.groceries') then
    raise exception 'Only a supported Household package may be previewed.' using errcode='22023';
  end if;
  v_context:=atlas.personal_week_planning_context_self_api_v1(p_week_of);
  v_household:=(v_context->>'householdId')::uuid;
  v_week_start:=(v_context->>'weekStart')::date;
  v_days:=v_context->'days';
  select d.title into v_kernel_title from atlas.world_kernel_definitions d
  where d.kernel_key=p_kernel_key and d.active
  order by d.version desc limit 1;
  if v_kernel_title is null then
    raise exception 'Active world kernel not available.' using errcode='22023';
  end if;
  if p_estimated_minutes is not null and (p_estimated_minutes < 1 or p_estimated_minutes > 600) then
    raise exception 'Estimated effort must be positive and at most 600 minutes.' using errcode='22023';
  end if;
  v_duration:=p_estimated_minutes;
  if v_duration is null then
    select round(avg((m.configuration->>'expectedMinutes')::numeric))::integer
    into v_duration from atlas.world_kernel_models m
    where m.kernel_key=p_kernel_key and m.active
      and (m.configuration->>'expectedMinutes') ~ '^[0-9]+$';
  end if;
  if coalesce(v_duration,0)<=0 then
    return jsonb_build_object(
      'ok',true,'contractVersion','personal_week_work_fit_preview_self_api_v1',
      'state','effort_estimate_needed','context',v_context,'recommendation',null,
      'truthBoundary',jsonb_build_object('readOnly',true,'noPlacementEstablished',true)
    );
  end if;

  if p_before_household_event_id is not null then
    select (e.starts_at at time zone (v_context->>'timezone'))::date,e.title
    into v_anchor_date,v_anchor_title
    from atlas.household_events e
    where e.id=p_before_household_event_id and e.household_id=v_household
      and e.fixed and e.starts_at is not null
      and e.starts_at >= ((v_week_start)::timestamp at time zone (v_context->>'timezone'))
      and e.starts_at < ((v_week_start+14)::timestamp at time zone (v_context->>'timezone'))
    limit 1;
    if v_anchor_date is null then
      raise exception 'Verified fixed household anchor not found in this planning horizon.' using errcode='22023';
    end if;
  end if;

  select count(*) filter(where coalesce((x.value#>>'{capacity,capacityKnown}')::boolean,false)),
         count(*) filter(where coalesce((x.value#>>'{capacity,capacityKnown}')::boolean,false)
           and coalesce((x.value#>>'{capacity,discretionaryCapacityMinutes}')::integer,0)>=v_duration
           -- Date-level fit must not pretend to know a free hour inside a fixed event.
           and jsonb_array_length(coalesce(x.value->'fixedHouseholdEvents','[]'::jsonb))=0
           and (v_anchor_date is null or (x.value->>'localDate')::date<v_anchor_date))
  into v_days_known,v_eligible
  from jsonb_array_elements(v_days) x;

  -- All seven source days must have a policy-defined capacity for a date
  -- recommendation. Missing capacity is not evidence that any day is free.
  v_state:=case when v_days_known<7 then 'capacity_anchor_required'
    when v_eligible=0 then 'no_fitting_window_in_known_capacity'
    else 'provisional_ranked' end;

  with compared as (
    select
      (x.value->>'localDate')::date as local_day,
      coalesce((x.value#>>'{capacity,capacityKnown}')::boolean,false) as capacity_known,
      coalesce((x.value#>>'{capacity,discretionaryCapacityMinutes}')::integer,0) as free_minutes,
      jsonb_array_length(coalesce(x.value->'fixedHouseholdEvents','[]'::jsonb)) as fixed_count,
      jsonb_array_length(coalesce(x.value->'ownerObligations','[]'::jsonb)) as obligation_count,
      jsonb_array_length(coalesce(x.value->'currentRhythmWindows','[]'::jsonb)) as rhythm_count
    from jsonb_array_elements(v_days) x
  ), eligible as (
    select *,
       (free_minutes-v_duration) as remaining_minutes
    from compared
    where capacity_known and free_minutes>=v_duration
      and fixed_count=0
      and (v_anchor_date is null or local_day<v_anchor_date)
  ), ordered as (
    select row_number() over(order by fixed_count,obligation_count,rhythm_count,
      case when v_anchor_date is not null then v_anchor_date-local_day else 0 end,
      free_minutes desc,local_day) as rank,
      local_day,free_minutes,remaining_minutes,fixed_count,obligation_count,rhythm_count
    from eligible
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',o.rank,'localDate',o.local_day::text,
    'sourceAvailableMinutes',o.free_minutes,
    'remainingAfterEstimate',o.remaining_minutes,
    'knownFixedEventCount',o.fixed_count,
    'knownOwnerObligationCount',o.obligation_count,
    'existingRhythmWindowCount',o.rhythm_count,
    'epistemicState','provisional_candidate_not_approved'
  ) order by o.rank),'[]'::jsonb)
  into v_ranked from ordered o;

  v_selected:=case when v_state='provisional_ranked' then v_ranked->0 else null end;
  v_alternates:=case when v_state='provisional_ranked' then
    (select coalesce(jsonb_agg(a.value),'[]'::jsonb)
      from jsonb_array_elements(v_ranked) with ordinality a(value,ordinal)
      where a.ordinal between 2 and 3)
    else '[]'::jsonb end;

  return jsonb_build_object(
    'ok',true,'contractVersion','personal_week_work_fit_preview_self_api_v1',
    'kernelKey',p_kernel_key,'kernelTitle',v_kernel_title,
    'state',v_state,'estimatedMinutes',v_duration,
    'effortEstimateSource',case when p_estimated_minutes is null then 'unaccepted_kernel_model_average' else 'explicit_preview_input' end,
    'constraint',case when v_anchor_date is null then null
      else jsonb_build_object('beforeSourceKind','household_event',
      'sourceId',p_before_household_event_id,
      'eventTitle',v_anchor_title,'beforeLocalDate',v_anchor_date::text) end,
    'context',v_context,'recommendation',v_selected,'alternatives',v_alternates,
    'availableKnownCapacityDays',v_days_known,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,'noPlacementEstablished',true,
      'allSevenCapacityDaysRequired',true,
      'provisionalFitOnly',true,
      'incompleteExternalSourceCoverage',true,
      'noCrossKernelDependencyInferred',true,
      'noClockAdmission',true,
      'noFixedCalendarWrites',true,
      'notEvidenceOfPhysicalCompletion',true
    )
  );
end
$function$;

revoke all on function atlas.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)
  from public,anon,authenticated;
create or replace function public.personal_week_work_fit_preview_self_api_v1(
  p_kernel_key text,
  p_week_of date default null,
  p_before_household_event_id uuid default null,
  p_estimated_minutes integer default null
) returns jsonb
language sql stable security definer set search_path to ''
as $function$
  select atlas.personal_week_work_fit_preview_self_api_v1(
    p_kernel_key,p_week_of,p_before_household_event_id,p_estimated_minutes);
$function$;
revoke all on function public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)
  from public,anon;
grant execute on function public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)
  to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
)
values
('public.personal_week_planning_context_self_api_v1(date)','app_endpoint','provisional','active',true,true,false,0,0,
  '{"source":"atlas_personal_week_fit_readonly_v1","sourceOwned":true,"readOnly":true}'::jsonb,false),
('public.personal_week_work_fit_preview_self_api_v1(text,date,uuid,integer)','app_endpoint','provisional','active',true,true,false,0,0,
  '{"source":"atlas_personal_week_fit_readonly_v1","sourceOwned":true,"readOnly":true}'::jsonb,false)
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  reviewed_at=now();
