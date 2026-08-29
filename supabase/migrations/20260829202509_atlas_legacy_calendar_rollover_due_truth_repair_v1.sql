do $repair$
declare
  r record;
  v_restored date;
  v_key text;
begin
  for r in
    with roll as (
      select tt.task_id,
             min(tt.created_at) as first_roll_at,
             max(tt.created_at) as last_roll_at,
             min(tt.previous_due_date) filter (where tt.previous_due_date is not null) as earliest_roll_previous_due,
             max(tt.target_date) filter (where tt.target_date is not null) as latest_roll_target,
             count(*) as roll_count
      from atlas.task_transitions tt
      where tt.transition='rescheduled'
        and (
          coalesce((tt.payload->>'calendarRollover')::boolean,false)=true
          or tt.reason in ('Unfinished work moved to the next worker day.','Unfinished Farm Round item moved to the next worker day.')
        )
      group by tt.task_id
    )
    select t.*, roll.first_roll_at,roll.last_roll_at,roll.earliest_roll_previous_due,roll.latest_roll_target,roll.roll_count
    from atlas.tasks t
    join roll on roll.task_id=t.id
    where t.status in ('open','blocked')
      and roll.earliest_roll_previous_due is not null
      and t.due_date = roll.latest_roll_target
      and not exists (
        select 1
        from atlas.task_transitions x
        where x.task_id=t.id
          and x.created_at>roll.last_roll_at
          and x.transition='rescheduled'
          and not (
            coalesce((x.payload->>'calendarRollover')::boolean,false)=true
            or x.reason in ('Unfinished work moved to the next worker day.','Unfinished Farm Round item moved to the next worker day.')
          )
      )
    order by t.id
    for update of t
  loop
    v_restored := r.earliest_roll_previous_due;
    v_key := left('task-custody-repair:'||r.id::text||':'||v_restored::text,160);

    if exists(select 1 from atlas.task_transitions tt where tt.farm_id=r.farm_id and tt.idempotency_key=v_key) then
      continue;
    end if;

    insert into atlas.task_transitions(
      farm_id,task_id,transition,previous_status,next_status,previous_due_date,target_date,
      action_key,work_class,note,reason,idempotency_key,payload,created_by,actor_role
    ) values(
      r.farm_id,r.id,'rescheduled',r.status,r.status,r.due_date,v_restored,
      r.action_key,r.work_class,null,
      'Task custody repair: restored the last due date that existed before legacy calendar rollover began.',
      v_key,
      jsonb_build_object(
        'taskCustodyRepair',true,
        'legacyCalendarRolloverRepair',true,
        'incorrectCurrentDueDate',r.due_date,
        'restoredDueDate',v_restored,
        'firstLegacyRolloverAt',r.first_roll_at,
        'lastLegacyRolloverAt',r.last_roll_at,
        'legacyRolloverCount',r.roll_count,
        'statusPreserved',r.status,
        'repairPolicy','restore_only_when_current_due_equals_last_legacy_rollover_target_and_no_later_explicit_reschedule_exists'
      ),
      'atlas_task_custody_repair_v1','system'
    );

    update atlas.tasks
    set due_date=v_restored,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'task_custody_repair_v1',jsonb_build_object(
            'repairedAt',now(),
            'incorrectDueDate',r.due_date,
            'restoredDueDate',v_restored,
            'legacyRolloverCount',r.roll_count,
            'evidenceFirstRolloverAt',r.first_roll_at,
            'evidenceLastRolloverAt',r.last_roll_at
          )
        ),
        updated_at=now()
    where id=r.id
      and due_date=r.due_date
      and status=r.status;
  end loop;
end;
$repair$;