create or replace function atlas.recurrence_expectation_temporal_adapter_v1(
  p_organization_id uuid,
  p_recurrence_rule_ids uuid[],
  p_start_date date,
  p_end_date date,
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path to pg_catalog, atlas, local_intel
as $function$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit,5000),10000));
  v_requested_rule_count integer := 0;
  v_resolved_rule_count integer := 0;
  v_lifecycles jsonb := '[]'::jsonb;
  v_expectations jsonb := '[]'::jsonb;
  v_admissions jsonb := '[]'::jsonb;
  v_observed_count integer := 0;
  v_returned_count integer := 0;
  v_truncated boolean := false;
  v_derived_count integer := 0;
  v_realized_count integer := 0;
  v_standalone_count integer := 0;
  v_conflict_count integer := 0;
begin
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Valid recurrence adapter date window is required.' using errcode='22023';
  end if;

  if p_end_date-p_start_date > 3660 then
    raise exception 'Recurrence adapter window may not exceed 3660 days.' using errcode='22023';
  end if;

  select count(distinct x.rule_id)::integer
  into v_requested_rule_count
  from unnest(coalesce(p_recurrence_rule_ids,'{}'::uuid[])) as x(rule_id);

  if v_requested_rule_count=0 then
    return jsonb_build_object(
      'contractVersion','recurrence_expectation_temporal_adapter_v1',
      'organizationId',p_organization_id,
      'window',jsonb_build_object('startDate',p_start_date,'endDate',p_end_date),
      'expectationContributions','[]'::jsonb,
      'occurrenceAdmissions','[]'::jsonb,
      'coverage',jsonb_build_object(
        'partial',false,
        'requestedRuleCount',0,
        'resolvedRuleCount',0,
        'observedLifecycleCount',0,
        'returnedLifecycleCount',0,
        'truncated',false,
        'derivedWithoutPersistedInstanceCount',0,
        'realizedOccurrenceAdmissionCount',0,
        'standaloneExpectationCount',0,
        'realizationConflictCount',0
      )
    );
  end if;

  select count(*)::integer
  into v_resolved_rule_count
  from atlas.organization_recurrence_rules r
  where r.organization_id=p_organization_id
    and r.id=any(p_recurrence_rule_ids);

  with selected_rules as (
    select r.*
    from atlas.organization_recurrence_rules r
    where r.organization_id=p_organization_id
      and r.id=any(p_recurrence_rule_ids)
  ), generated_sources as (
    select r.id as rule_id,gs::date as source_local_date
    from selected_rules r
    cross join lateral generate_series(
      greatest(p_start_date,r.effective_start_date)::timestamp,
      least(p_end_date,coalesce(r.effective_end_date,p_end_date))::timestamp,
      interval '1 day'
    ) gs
    where r.rule_state='active'
      and (
        (
          r.frequency='weekly'
          and extract(dow from gs)::smallint=any(r.weekdays)
          and mod(
            floor(((gs::date-r.effective_start_date)::numeric)/7)::integer,
            r.interval_count
          )=0
        )
        or
        (
          r.frequency='monthly_nth_weekday'
          and extract(dow from gs)::smallint=any(r.weekdays)
          and mod(
            (extract(year from gs)::integer-extract(year from r.effective_start_date)::integer)*12
            + extract(month from gs)::integer
            - extract(month from r.effective_start_date)::integer,
            r.interval_count
          )=0
          and (
            (((extract(day from gs)::integer-1)/7)+1)::smallint=any(r.month_ordinals)
            or (
              (-1)::smallint=any(r.month_ordinals)
              and extract(month from (gs+interval '7 day'))<>extract(month from gs)
            )
          )
        )
      )
  ), moved_in_sources as (
    select e.recurrence_rule_id as rule_id,e.source_local_date
    from atlas.organization_recurrence_exceptions e
    join selected_rules r
      on r.id=e.recurrence_rule_id
     and r.organization_id=e.organization_id
    where e.exception_state='active'
      and e.exception_action='move'
      and e.replacement_date between p_start_date and p_end_date
  ), stored_sources as (
    select i.recurrence_rule_id as rule_id,i.source_local_date
    from atlas.organization_recurrence_instances i
    join selected_rules r
      on r.id=i.recurrence_rule_id
     and r.organization_id=i.organization_id
    where i.local_date between p_start_date and p_end_date
  ), source_dates as (
    select * from generated_sources
    union
    select * from moved_in_sources
    union
    select * from stored_sources
  ), base as (
    select
      r.*,
      s.source_local_date,
      e.id as exception_id,
      e.exception_action,
      e.replacement_date,
      e.override_start_time,
      e.override_end_time,
      e.temporal_binding_id,
      e.reason as exception_reason,
      e.payload as exception_payload,
      i.id as recurrence_instance_id,
      i.local_date as instance_local_date,
      i.expected_start_at as instance_expected_start_at,
      i.expected_end_at as instance_expected_end_at,
      i.schedule_state as instance_schedule_state,
      i.realization_state as instance_realization_state,
      i.occurrence_binding_id,
      case
        when e.id is not null and e.exception_action='move' then e.replacement_date
        else s.source_local_date
      end as effective_local_date,
      coalesce(e.override_start_time,r.local_start_time) as effective_start_time,
      coalesce(e.override_end_time,r.local_end_time) as effective_end_time,
      case
        when i.id is not null and i.schedule_state='retired' then 'retired'
        when e.id is null then 'expected'
        when e.exception_action='skip' then 'skipped'
        when e.exception_action='override' then 'overridden'
        when e.exception_action='move' then 'moved'
        else 'expected'
      end as effective_schedule_state
    from source_dates s
    join selected_rules r on r.id=s.rule_id
    left join atlas.organization_recurrence_exceptions e
      on e.organization_id=r.organization_id
     and e.recurrence_rule_id=r.id
     and e.source_local_date=s.source_local_date
     and e.exception_state='active'
    left join atlas.organization_recurrence_instances i
      on i.organization_id=r.organization_id
     and i.recurrence_rule_id=r.id
     and i.source_local_date=s.source_local_date
  ), timed as (
    select
      b.*,
      (b.effective_local_date+b.effective_start_time) at time zone b.timezone_name as effective_start_at,
      case
        when b.effective_end_time is null then null
        when b.effective_end_time>=b.effective_start_time
          then (b.effective_local_date+b.effective_end_time) at time zone b.timezone_name
        else ((b.effective_local_date+1)+b.effective_end_time) at time zone b.timezone_name
      end as effective_end_at,
      (b.source_local_date+b.local_start_time) at time zone b.timezone_name as origin_start_at,
      case
        when b.local_end_time is null then null
        when b.local_end_time>=b.local_start_time
          then (b.source_local_date+b.local_end_time) at time zone b.timezone_name
        else ((b.source_local_date+1)+b.local_end_time) at time zone b.timezone_name
      end as origin_end_at
    from base b
  ), lifecycle_rows as (
    select
      t.*,
      ob.occurrence_id,
      o.title as occurrence_title,
      o.status as occurrence_status,
      o.start_at as occurrence_start_at,
      o.end_at as occurrence_end_at
    from timed t
    left join atlas.organization_occurrence_bindings ob
      on ob.id=t.occurrence_binding_id
     and ob.organization_id=t.organization_id
    left join local_intel.occurrences o on o.id=ob.occurrence_id
    where t.effective_local_date between p_start_date and p_end_date
  ), packed as (
    select
      jsonb_build_object(
        'expectationKey','recurrence_expectation:'||l.id::text||':'||l.source_local_date::text,
        'recurrenceRule',jsonb_build_object(
          'ruleId',l.id,
          'stableKey',l.stable_key,
          'title',l.title,
          'ruleState',l.rule_state,
          'frequency',l.frequency,
          'intervalCount',l.interval_count,
          'timezoneName',l.timezone_name,
          'effectiveStartDate',l.effective_start_date,
          'effectiveEndDate',l.effective_end_date,
          'weekdays',to_jsonb(l.weekdays),
          'monthOrdinals',to_jsonb(l.month_ordinals)
        ),
        'lineage',jsonb_build_object(
          'kind','current_effective',
          'revisionHistoryAvailable',false,
          'sourceLocalDate',l.source_local_date,
          'originCoordinate',jsonb_strip_nulls(jsonb_build_object(
            'dateKey',l.source_local_date,
            'startsAt',l.origin_start_at,
            'endsAt',l.origin_end_at,
            'timezoneName',l.timezone_name
          )),
          'exception',case when l.exception_id is null then null else jsonb_strip_nulls(jsonb_build_object(
            'exceptionId',l.exception_id,
            'action',l.exception_action,
            'replacementDate',l.replacement_date,
            'overrideStartTime',l.override_start_time,
            'overrideEndTime',l.override_end_time,
            'temporalBindingId',l.temporal_binding_id,
            'reason',l.exception_reason,
            'payload',l.exception_payload
          )) end,
          'effectiveLocalDate',l.effective_local_date
        ),
        'effectiveCoordinate',jsonb_strip_nulls(jsonb_build_object(
          'dateKey',l.effective_local_date,
          'startsAt',l.effective_start_at,
          'endsAt',l.effective_end_at,
          'precision',case when l.effective_end_at is null then 'instant' else 'interval' end,
          'timezoneName',l.timezone_name
        )),
        'scheduleState',l.effective_schedule_state,
        'persistedInstance',case when l.recurrence_instance_id is null then null else jsonb_strip_nulls(jsonb_build_object(
          'recurrenceInstanceId',l.recurrence_instance_id,
          'localDate',l.instance_local_date,
          'expectedStartAt',l.instance_expected_start_at,
          'expectedEndAt',l.instance_expected_end_at,
          'scheduleState',l.instance_schedule_state,
          'realizationState',l.instance_realization_state
        )) end,
        'realization',jsonb_strip_nulls(jsonb_build_object(
          'state',coalesce(l.instance_realization_state,'unmaterialized'),
          'occurrenceBindingId',l.occurrence_binding_id,
          'occurrenceId',l.occurrence_id,
          'occurrenceTitle',l.occurrence_title,
          'occurrenceStatus',l.occcurrence_status,
         'occurrenceStartsAt',l.occurrence_start_at,
          'occurrenceEndsAt',l.occurrence_end_at
        )),
        'temporalPressure',case
          when l.effective_schedule_state in ('skipped','retired') or l.occurrence_status='cancelled'
            then jsonb_build_object(
              'active',false,
              'class','none',
              'startsAt',l.effective_start_at,
              'endsAt',l.effective_end_at
            )
          when l.occurrence_id is not null and l.instance_realization_state='conflict'
            then jsonb_build_object(
              'active',true,
              'class','conflict',
              'startsAt',l.effective_start_at,
              'endsAt',l.effective_end_at
            )
          when l.occurrence_id is not null
            then jsonb_build_object(
              'active',false,
              'class','delegated_to_realization',
              'startsAt',l.effective_start_at,
              'endsAt',l.effective_end_at,
              'ownerRef',jsonb_build_object(
                'authority','local_intel',
                'kind','occurrence',
                'id',l.occurrence_id
              )
            )
          else jsonb_build_object(
            'active',true,
            'class','expectation',
            'startsAt',l.effective_start_at,
            'endsAt',l.effective_end_at
          )
        end
      ) as lifecycle,
      l.effective_local_date,
      l.effective_start_at,
      l.title,
      l.id,
      l.source_local_date
    from lifecycle_rows l
    order by l.effective_local_date,l.effective_start_at,l.title,l.id,l.source_local_date
    limit (v_limit+1)
  )
  select coalesce(
    jsonb_agg(
      lifecycle
      order by effective_local_date,effective_start_at,title,id,source_local_date
    ),
    '[]'::jsonb
  )
  into v_lifecycles
  from packed;

  v_observed_count:=jsonb_array_length(v_lifecycles);
  v_truncated:=v_observed_count>v_limit;

  if v_truncated then
    select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
    into v_lifecycles
    from jsonb_array_elements(v_lifecycles) with ordinality as x(value,ordinality)
    where ordinality<=v_limit;
  end if;

  v_returned_count:=jsonb_array_length(v_lifecycles);

  select count(*)::integer
  into v_derived_count
  from jsonb_array_elements(v_lifecycles) as x(lifecycle)
  where coalesce(lifecycle->'persistedInstance','null'::jsonb)='null'::jsonb;

  select count(*)::integer
  into v_realized_count
  from jsonb_array_elements(v_lifecycles) as x(lifecycle)
  where nullif(lifecycle#>>'{realization,occurrenceId}','') is not null;

  select count(*)::integer
  into v_conflict_count
  from jsonb_array_elements(v_lifecycles) as x(lifecycle)
  where lifecycle#>>'{realization,state}'='conflict';

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'projectionKey',lifecycle->>'expectationKey',
        'sourceRef',jsonb_build_object(
          'authority','atlas',
          'kind','recurrence_rule',
          'id',lifecycle#>>'{recurrenceRule,ruleId}'
        ),
        'standing',case
          when lifecycle#>>'{realization,state}'='conflict' then 'conflict'
          else 'expected'
        end,
        'coordinate',lifecycle->'effectiveCoordinate',
        'display',jsonb_build_object(
          'title',lifecycle#>>'{recurrenceRule,title}'
        ),
        'epistemic',jsonb_build_object(
          'state',case
            when lifecycle->>'scheduleState' in ('skipped','retired')
              or lifecycle#>>'{realization,state}'='cancelled' then 'cancelled'
            when lifecycle#>>'{realization,state}'='conflict' then 'conflicted'
            else 'expected'
          end,
          'sourceStatus',lifecycle->>'scheduleState'
        ),
        'encounter',jsonb_build_object(
          'kind','recurrence_rule',
          'id',lifecycle#>>'{recurrenceRule,ruleId}'
        ),
        'temporalPressure',lifecycle->'temporalPressure',
        'sourceSnapshot',lifecycle,
        'contexts','[]'::jsonb
      )
      order by
        nullif(lifecycle#>>'{effectiveCoordinate,dateKey}','')::date,
        nullif(lifecycle#>>'{effectiveCoordinate,startsAt}','')::timestamptz,
        lifecycle#>>'{recurrenceRule,title}',
        lifecycle->>'expectationKey'
    ),
    '[]'::jsonb
  )
  into v_expectations
  from jsonb_array_elements(v_lifecycles) as x(lifecycle)
  where nullif(lifecycle#>>'{realization,occurrenceId}','') is null
     or lifecycle#>>'{realization,state}'='conflict';

  v_standalone_count:=jsonb_array_length(v_expectations);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'occurrenceId',lifecycle#>>'{realization,occurrenceId}',
        'lifecycle',lifecycle
      )
      order by
        nullif(lifecycle#>>'{effectiveCoordinate,dateKey}','')::date,
        nullif(lifecycle#>>'{effectiveCoordinate,startsAt}','')::timestamptz,
        lifecycle#>>'{recurrenceRule,title}',
        lifecycle->>'expectationKey'
    ),
    '[]'::jsonb
  )
  into v_admissions
  from jsonb_array_elements(v_lifecycles) as x(lifecycle)
  where nullif(lifecycle#>>'{realization,occurrenceId}','') is not null;

  return jsonb_build_object(
    'contractVersion','recurrence_expectation_temporal_adapter_v1',
    'organizationId',p_organization_id,
    'window',jsonb_build_object('startDate',p_start_date,'endDate',p_end_date),
    'expectationContributions',v_expectations,
    'occurrenceAdmissions',v_admissions,
    'coverage',jsonb_build_object(
      'partial',(v_truncated or v_resolved_rule_count<>v_requested_rule_count),
      'requestedRuleCount',v_requested_rule_count,
      'resolvedRuleCount',v_resolved_rule_count,
      'observedLifecycleCount',v_observed_count,
      'returnedLifecycleCount',v_returned_count,
      'truncated',v_truncated,
      'derivedWithoutPersistedInstanceCount',v_derived_count,
      'realizedOccurrenceAdmissionCount',v_realized_count,
      'standaloneExpectationCount',v_standalone_count,
      'realizationConflictCount',v_conflict_count
    )
  );
end
$function$;

revoke all on function atlas.recurrence_expectation_temporal_adapter_v1(uuid,uuid[],date,date,integer) from public,anon,authenticated;
grant execute on function atlas.recurrence_expectation_temporal_adapter_v1(uuid,uuid[],date,date,integer) to service_role;

comment on function atlas.recurrence_expectation_temporal_adapter_v1(uuid,uuid[],date,date,integer)
is 'Internal read-only recurrence lifecycle adapter: derives expectations from rules, applies current exceptions, reconciles persisted instances/Occurrence realizations, and exposes non-authoritative temporal pressure.';