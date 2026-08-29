create or replace function atlas.roll_expired_worker_tasks_v1_legacy(
  p_farm_id uuid,
  p_membership_id uuid,
  p_target_date date default null::date
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_timezone text := 'America/Chicago';
  v_today date;
  v_target date;
  v_task record;
  v_superseded integer := 0;
  v_expired_weekly_harvest integer := 0;
  v_preserved_open integer := 0;
  v_battery jsonb;
begin
  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_timezone
  from atlas.farms f
  where f.id=p_farm_id;

  v_today := (now() at time zone v_timezone)::date;
  v_target := coalesce(p_target_date,v_today);
  if v_target < v_today then v_target := v_today; end if;
  v_target := atlas.worker_day_on_or_after_v1(p_farm_id,p_membership_id,v_target);

  if v_target is null then
    return jsonb_build_object(
      'moved',0,
      'superseded',0,
      'expiredWeeklyHarvestRounds',0,
      'preservedOpenObligations',0,
      'reason','no_available_worker_day'
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||':'||p_membership_id::text||':calendar-rollover',0));

  for v_task in
    select t.*
    from atlas.tasks t
    where t.farm_id=p_farm_id
      and t.assigned_membership_id=p_membership_id
      and t.task_scope='farm_operation'
      and t.status='open'
      and t.due_date is not null
      and t.due_date<v_target
      and t.parent_task_id is null
      and nullif(t.metadata->>'parent_task_id','') is null
      and lower(coalesce(t.metadata->>'is_child_task','false'))<>'true'
      and coalesce(t.visibility_scope,'')<>'system_internal'
    order by t.due_date,t.created_at,t.id
    for update
  loop
    if lower(coalesce(v_task.metadata->>'farm_round_parent','false')) in ('true','yes','1')
       and exists(
         select 1
         from atlas.planned_work_occurrences o
         where o.farm_id=p_farm_id
           and o.planned_due_date=v_target
           and o.id<>coalesce(v_task.planned_occurrence_id,'00000000-0000-0000-0000-000000000000'::uuid)
           and o.state<>'cancelled'
           and o.source_kind='farm_round'
           and o.task_payload->>'assigned_membership_id'=p_membership_id::text
       )
    then
      perform atlas.record_task_transition_v1_internal(
        v_task.id,'changed_plan',
        left('calendar-rollover-farm-round-superseded:'||v_task.id::text||':'||v_target::text,160),
        null,null,'Expired Farm Round shell replaced by the destination day Farm Round.',
        v_task.action_key,'calendar_rollover',
        jsonb_build_object(
          'calendarRollover',false,
          'closedFromDate',v_task.due_date,
          'targetDate',v_target,
          'disposition','superseded_daily_farm_round'
        ),null
      );
      if v_task.planned_occurrence_id is not null then
        update atlas.planned_work_occurrences
        set state='cancelled',
            metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
              'calendarRollover',false,
              'calendarRolloverDisposition','superseded_daily_farm_round',
              'calendarRolloverTargetDate',v_target,
              'calendarRolloverAt',now()
            ),
            updated_at=now()
        where id=v_task.planned_occurrence_id
          and state not in ('completed','cancelled');
      end if;
      update atlas.farm_round_occurrences
      set status='cancelled',updated_at=now()
      where parent_task_id=v_task.id and status='open';
      v_superseded := v_superseded+1;
      continue;
    end if;

    if coalesce(v_task.metadata->>'task_style','')='weekly_harvest_round'
       and lower(coalesce(v_task.metadata->>'completion_independent_schedule','false')) in ('true','yes','1')
    then
      perform atlas.record_task_transition_v1_internal(
        v_task.id,'changed_plan',
        left('calendar-rollover-expired-weekly-harvest:'||v_task.id::text||':'||v_task.due_date::text,160),
        null,null,'Weekly Harvest round expired on its scheduled day; it does not carry forward.',
        v_task.action_key,'calendar_rollover',
        jsonb_build_object(
          'calendarRollover',false,
          'scheduledDate',v_task.due_date,
          'targetDate',v_target,
          'disposition','expired_weekly_harvest_round',
          'taskStyle','weekly_harvest_round'
        ),null
      );
      v_expired_weekly_harvest := v_expired_weekly_harvest+1;
      continue;
    end if;

    if exists(
      select 1
      from atlas.presented_work_selection_rows_unfiltered_v1(p_farm_id,p_membership_id,v_target) r
      where r.task_id=v_task.id
        and r.presentation_reason='superseded_rhythm_serving'
    )
    then
      perform atlas.record_task_transition_v1_internal(
        v_task.id,'changed_plan',
        left('calendar-rollover-superseded:'||v_task.id::text||':'||v_target::text,160),
        null,null,null,v_task.action_key,'calendar_rollover',
        jsonb_build_object(
          'calendarRollover',false,
          'closedFromDate',v_task.due_date,
          'targetDate',v_target,
          'disposition','superseded_rhythm_serving'
        ),null
      );
      v_superseded := v_superseded+1;
      continue;
    end if;

    -- Task custody boundary: an unresolved obligation is never rescheduled merely because
    -- its Worker Day elapsed. Its due date remains source truth; only placement may expire.
    v_preserved_open := v_preserved_open+1;
  end loop;

  v_battery := atlas.reconcile_worker_day_battery_sessions_v1(p_farm_id,p_membership_id,v_target);

  return jsonb_build_object(
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'targetDate',v_target,
    'moved',0,
    'superseded',v_superseded,
    'expiredWeeklyHarvestRounds',v_expired_weekly_harvest,
    'preservedOpenObligations',v_preserved_open,
    'batterySessionReconciliation',v_battery,
    'truthBoundary',jsonb_build_object(
      'elapsedDayDoesNotRewriteDueDate',true,
      'genericOpenObligationSurvivesRollover',true,
      'onlyExplicitLifecycleRulesMayCloseExpiredWork',true
    )
  );
end;
$function$;

create or replace function atlas.roll_expired_worker_tasks_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_target_date date default null::date
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_timezone text := 'America/Chicago';
  v_today date;
  v_rollover_date date;
  v_task record;
  v_dest_occurrence atlas.planned_work_occurrences%rowtype;
  v_superseded integer := 0;
  v_result jsonb;
  v_elapsed jsonb;
begin
  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_timezone
  from atlas.farms f
  where f.id=p_farm_id;

  v_today := (now() at time zone v_timezone)::date;
  v_rollover_date := atlas.worker_day_on_or_after_v1(p_farm_id,p_membership_id,v_today);

  if v_rollover_date is null then
    return jsonb_build_object(
      'moved',0,'superseded',0,'expiredWeeklyHarvestRounds',0,
      'reason','no_available_worker_day','requestedViewDate',p_target_date,
      'rolloverHorizonDate',v_today
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||':'||p_membership_id::text||':daily-recurrence-handoff',0));

  for v_task in
    select t.*
    from atlas.tasks t
    where t.farm_id=p_farm_id
      and t.assigned_membership_id=p_membership_id
      and t.task_scope='farm_operation'
      and t.status='open'
      and t.due_date is not null
      and t.due_date<v_today
      and coalesce(t.visibility_scope,'')<>'system_internal'
      and t.task_series_key is not null
      and coalesce(t.metadata->>'repeat_rule','') like 'daily%'
    order by t.due_date,t.created_at,t.id
    for update
  loop
    select o.* into v_dest_occurrence
    from atlas.planned_work_occurrences o
    where o.farm_id=p_farm_id
      and o.planned_due_date=v_rollover_date
      and o.state<>'cancelled'
      and o.id<>coalesce(v_task.planned_occurrence_id,'00000000-0000-0000-0000-000000000000'::uuid)
      and o.occurrence_key=('recurring:'||v_task.task_series_key||':'||v_rollover_date::text)
    order by o.created_at,o.id
    limit 1;

    if v_dest_occurrence.id is null then continue; end if;

    perform atlas.record_task_transition_v1_internal(
      v_task.id,'changed_plan',
      left('daily-recurrence-handoff:'||v_task.id::text||':'||v_rollover_date::text,160),
      null,null,'Expired daily occurrence handed forward to the destination recurrence.',
      v_task.action_key,'daily_recurrence_handoff',
      jsonb_build_object(
        'calendarRollover',false,
        'closedFromDate',v_task.due_date,
        'targetDate',v_rollover_date,
        'disposition','superseded_by_destination_daily_occurrence',
        'destinationOccurrenceId',v_dest_occurrence.id
      ),null
    );

    if v_task.planned_occurrence_id is not null then
      update atlas.planned_work_occurrences
      set state='cancelled',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'dailyRecurrenceHandoff',true,
            'dailyRecurrenceHandoffDisposition','superseded_by_destination_daily_occurrence',
            'dailyRecurrenceHandoffTargetDate',v_rollover_date,
            'dailyRecurrenceHandoffDestinationOccurrenceId',v_dest_occurrence.id,
            'dailyRecurrenceHandoffAt',now()
          ),
          updated_at=now()
      where id=v_task.planned_occurrence_id
        and state not in ('completed','cancelled');
    end if;

    update atlas.planned_work_occurrences
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'carriedUnfinishedDailyRecurrence',true,
          'carriedUnfinishedFromTaskId',v_task.id,
          'carriedUnfinishedFromOccurrenceId',v_task.planned_occurrence_id,
          'carriedUnfinishedFromDate',v_task.due_date,
          'carriedUnfinishedAt',now()
        ),
        updated_at=now()
    where id=v_dest_occurrence.id;

    if v_dest_occurrence.released_task_id is not null then
      update atlas.tasks
      set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'carried_unfinished_daily_recurrence',true,
            'carried_unfinished_from_task_id',v_task.id,
            'carried_unfinished_from_occurrence_id',v_task.planned_occurrence_id,
            'carried_unfinished_from_date',v_task.due_date,
            'carried_unfinished_at',now()
          ),
          updated_at=now()
      where id=v_dest_occurrence.released_task_id;
    end if;

    v_superseded := v_superseded+1;
  end loop;

  -- Explicit lifecycle expiration is handled first. It may close a task only through
  -- a named recurrence/event/rhythm rule; it may never generically reschedule it.
  v_result := atlas.roll_expired_worker_tasks_v1_legacy(p_farm_id,p_membership_id,v_rollover_date);

  -- Any remaining open/blocked task keeps its obligation truth. Only its elapsed
  -- Worker Day placement is released back to Atlas for lawful future placement.
  v_elapsed := atlas.sync_elapsed_worker_day_placements_v1(p_farm_id,p_membership_id,now());

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'dailyRecurringIdentityHandoffs',v_superseded,
    'requestedViewDate',p_target_date,
    'rolloverHorizonDate',v_today,
    'rolloverDestinationDate',v_rollover_date,
    'elapsedPlacementReconciliation',coalesce(v_elapsed,'{}'::jsonb),
    'truthBoundary',jsonb_build_object(
      'viewDateNeverMutatesObligationTruth',true,
      'elapsedPlacementDoesNotCompleteOrRescheduleTask',true,
      'unresolvedObligationPersistsUntilExplicitResolution',true
    )
  );
end;
$function$;