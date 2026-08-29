create or replace function atlas.previous_worker_day_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_day date
)
returns date
language plpgsql
stable security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_day date;
  v_guard integer:=0;
begin
  if p_farm_id is null or p_membership_id is null or p_day is null then
    return null;
  end if;
  v_day:=p_day-1;
  while not atlas.worker_day_available_v1(p_farm_id,p_membership_id,v_day) loop
    v_day:=v_day-1;
    v_guard:=v_guard+1;
    if v_guard>370 then
      raise exception 'No previous available worker day found within one year.' using errcode='55000';
    end if;
  end loop;
  return v_day;
end;
$function$;

create or replace function atlas.sync_prior_work_reconciliation_cues_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_service_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_timezone text:='America/Chicago';
  v_service_date date;
  v_prior_day date;
  v_row record;
  v_cue_id uuid;
  v_created integer:=0;
  v_existing integer:=0;
  v_results jsonb:='[]'::jsonb;
begin
  if p_farm_id is null or p_membership_id is null then
    raise exception 'Farm and membership are required.' using errcode='22023';
  end if;
  if not exists(
    select 1 from atlas.farm_memberships fm
    where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true
  ) then
    raise exception 'Active membership required.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
    into v_timezone
  from atlas.farms f where f.id=p_farm_id;
  v_service_date:=coalesce(p_service_date,(now() at time zone v_timezone)::date);
  if not atlas.worker_day_available_v1(p_farm_id,p_membership_id,v_service_date) then
    return jsonb_build_object(
      'contractVersion','prior_work_reconciliation_cue_sync_v1',
      'farmId',p_farm_id,'membershipId',p_membership_id,'serviceDate',v_service_date,
      'createdCount',0,'existingCount',0,'cues','[]'::jsonb,'reason','service_day_not_available'
    );
  end if;
  v_prior_day:=atlas.previous_worker_day_v1(p_farm_id,p_membership_id,v_service_date);

  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||'|'||p_membership_id::text||'|'||v_service_date::text||'|prior_work_reconciliation',0));

  for v_row in
    select p.id as placement_id,p.organization_id,p.task_id,p.service_date as prior_service_date,
           t.title,t.status,t.due_date,t.action_key,t.task_type,t.priority
    from atlas.worker_day_task_placements p
    join atlas.tasks t on t.id=p.task_id
    where p.farm_id=p_farm_id
      and p.membership_id=p_membership_id
      and p.service_date=v_prior_day
      and p.state='returned_to_atlas'
      and t.status in ('open','blocked')
      and t.assigned_membership_id=p_membership_id
      and not exists(
        select 1
        from atlas.task_transitions tt
        where tt.task_id=t.id
          and tt.actor_membership_id=p_membership_id
          and tt.created_at >= (v_prior_day::timestamp at time zone v_timezone)
          and tt.transition in ('done','partial','blocked','not_relevant','changed_plan')
      )
    order by p.sort_order,p.task_id
  loop
    select cue.id into v_cue_id
    from atlas.worker_day_cues cue
    where cue.farm_id=p_farm_id
      and cue.membership_id=p_membership_id
      and cue.result_contract->>'kind'='prior_work_reconciliation_v1'
      and cue.result_contract->>'placementId'=v_row.placement_id::text
    order by cue.created_at desc
    limit 1;

    if v_cue_id is not null then
      v_existing:=v_existing+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object('cueId',v_cue_id,'taskId',v_row.task_id,'placementId',v_row.placement_id,'created',false));
      v_cue_id:=null;
      continue;
    end if;

    insert into atlas.worker_day_cues(
      organization_id,farm_id,membership_id,service_date,cue_kind,anchor_kind,anchor_task_id,
      scheduled_at,title,body,payload,result_contract,status,recovery_policy,
      available_from,expires_at,created_by_user_id
    ) values(
      v_row.organization_id,p_farm_id,p_membership_id,v_service_date,'result','first_open',null,
      null,'Yesterday — '||v_row.title,'What happened with this work?',
      jsonb_build_object(
        'stableKey','prior_work_reconciliation:'||v_row.placement_id::text,
        'taskId',v_row.task_id,
        'placementId',v_row.placement_id,
        'priorServiceDate',v_row.prior_service_date,
        'dueDate',v_row.due_date,
        'questions',jsonb_build_array(
          jsonb_build_object(
            'key','outcome','prompt','What happened with this work?',
            'choices',jsonb_build_array(
              jsonb_build_object('label','Finished','value','finished'),
              jsonb_build_object('label','Partly done','value','partial'),
              jsonb_build_object('label','Still open','value','still_open'),
              jsonb_build_object('label','Couldn’t do it','value','couldnt_do'),
              jsonb_build_object('label','No longer needed','value','no_longer_needed')
            )
          ),
          jsonb_build_object('key','note','input','text','prompt','Anything Atlas should know?','optional',true)
        )
      ),
      jsonb_build_object(
        'kind','prior_work_reconciliation_v1',
        'taskId',v_row.task_id,
        'placementId',v_row.placement_id,
        'priorServiceDate',v_row.prior_service_date
      ),
      'available','persist',null,null,null
    ) returning id into v_cue_id;

    v_created:=v_created+1;
    v_results:=v_results||jsonb_build_array(jsonb_build_object('cueId',v_cue_id,'taskId',v_row.task_id,'placementId',v_row.placement_id,'created',true));
    v_cue_id:=null;
  end loop;

  return jsonb_build_object(
    'contractVersion','prior_work_reconciliation_cue_sync_v1',
    'farmId',p_farm_id,'membershipId',p_membership_id,'serviceDate',v_service_date,
    'priorWorkerDay',v_prior_day,'createdCount',v_created,'existingCount',v_existing,'cues',v_results,
    'truthBoundary',jsonb_build_object(
      'onlyImmediatelyPrecedingWorkerDayIsQuestioned',true,
      'olderUnresolvedWorkStaysInNormalCustody',true,
      'cueCreationDoesNotMutateTaskTruth',true
    )
  );
end;
$function$;

create or replace function atlas.apply_prior_work_reconciliation_v1(
  p_cue_id uuid,
  p_response jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_cue atlas.worker_day_cues%rowtype;
  v_task atlas.tasks%rowtype;
  v_task_id uuid;
  v_placement_id uuid;
  v_prior_day date;
  v_outcome text;
  v_note text;
  v_due_before date;
  v_status_before text;
  v_transition jsonb:='{}'::jsonb;
  v_event_id uuid;
  v_reconciliation jsonb;
begin
  select * into v_cue from atlas.worker_day_cues where id=p_cue_id for update;
  if v_cue.id is null then raise exception 'Cue was not found.' using errcode='P0002'; end if;
  if coalesce(v_cue.result_contract->>'kind','')<>'prior_work_reconciliation_v1' then
    raise exception 'Cue is not a prior-work reconciliation.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_response,'{}'::jsonb))<>'object' then
    raise exception 'Cue response data must be an object.' using errcode='22023';
  end if;

  begin v_task_id:=(v_cue.result_contract->>'taskId')::uuid; exception when others then raise exception 'Cue task id is invalid.' using errcode='22023'; end;
  begin v_placement_id:=(v_cue.result_contract->>'placementId')::uuid; exception when others then raise exception 'Cue placement id is invalid.' using errcode='22023'; end;
  begin v_prior_day:=(v_cue.result_contract->>'priorServiceDate')::date; exception when others then raise exception 'Cue prior service date is invalid.' using errcode='22023'; end;

  select * into v_task
  from atlas.tasks t
  where t.id=v_task_id and t.farm_id=v_cue.farm_id and t.assigned_membership_id=v_cue.membership_id
  for update;
  if v_task.id is null then raise exception 'Cue task is outside the worker Day.' using errcode='55000'; end if;
  if not exists(
    select 1 from atlas.worker_day_task_placements p
    where p.id=v_placement_id and p.task_id=v_task.id and p.farm_id=v_cue.farm_id
      and p.membership_id=v_cue.membership_id and p.service_date=v_prior_day and p.state='returned_to_atlas'
  ) then
    raise exception 'Prior Worker Day placement is not in returned custody.' using errcode='55000';
  end if;

  v_outcome:=lower(coalesce(nullif(btrim(p_response->>'outcome'),''),''));
  v_note:=nullif(btrim(p_response->>'note'),'');
  if v_outcome not in ('finished','partial','still_open','couldnt_do','no_longer_needed') then
    raise exception 'Choose what happened with the prior work.' using errcode='22023';
  end if;
  if v_note is not null and length(v_note)>4000 then raise exception 'Note must be 4000 characters or fewer.' using errcode='22023'; end if;

  v_due_before:=v_task.due_date;
  v_status_before:=v_task.status;
  v_reconciliation:=jsonb_strip_nulls(jsonb_build_object(
    'cueId',v_cue.id,'placementId',v_placement_id,'priorServiceDate',v_prior_day,
    'outcome',v_outcome,'note',v_note,'recordedAt',now(),
    'actorUserId',auth.uid(),'actorMembershipId',v_cue.membership_id,
    'dueDateAtReconciliation',v_due_before,'statusAtReconciliation',v_status_before
  ));

  if v_outcome='finished' then
    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'done','prior-work:'||v_cue.id::text||':finished',null,v_note,
      'Worker reconciled prior placed work as finished.',coalesce(v_task.action_key,v_task.task_type),'prior_work_reconciliation',
      jsonb_build_object('completion_source','prior_work_reconciliation','prior_work_reconciliation',v_reconciliation),null
    );
  elsif v_outcome='no_longer_needed' then
    v_transition:=atlas.record_task_transition_v1_internal(
      v_task.id,'not_relevant','prior-work:'||v_cue.id::text||':no-longer-needed',null,v_note,
      'Worker reconciled prior placed work as no longer needed.',coalesce(v_task.action_key,v_task.task_type),'prior_work_reconciliation',
      jsonb_build_object('completion_source','prior_work_reconciliation','prior_work_reconciliation',v_reconciliation),null
    );
  else
    select e.id into v_event_id
    from atlas.task_outcome_events e
    where e.task_id=v_task.id and e.metadata->>'prior_work_reconciliation_cue_id'=v_cue.id::text
    order by e.created_at desc limit 1;

    if v_event_id is null then
      insert into atlas.task_outcome_events(
        farm_id,task_id,outcome,lane_key,work_key,blocker_reason,note,task_title,task_type,zone_id,due_date,priority,created_by,source,metadata
      ) values(
        v_task.farm_id,v_task.id,
        case v_outcome when 'partial' then 'partial' when 'couldnt_do' then 'blocked' else 'unfinished' end,
        v_task.action_key,'prior_work_reconciliation',
        case when v_outcome='couldnt_do' then coalesce(v_note,'Worker reported they could not complete the prior placed work.') else null end,
        v_note,v_task.title,v_task.task_type,v_task.zone_id,v_task.due_date,v_task.priority,
        'worker_day_cue','prior_work_reconciliation',
        jsonb_build_object(
          'prior_work_reconciliation_cue_id',v_cue.id,
          'prior_work_reconciliation',v_reconciliation,
          'task_status_unchanged',true,
          'due_date_unchanged',true
        )
      ) returning id into v_event_id;
    end if;

    update atlas.tasks t
    set metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object('latest_prior_work_reconciliation',v_reconciliation),
        updated_at=now()
    where t.id=v_task.id;
  end if;

  select * into v_task from atlas.tasks where id=v_task_id;
  if v_outcome in ('partial','still_open','couldnt_do') and v_task.due_date is distinct from v_due_before then
    raise exception 'Prior-work reconciliation attempted to rewrite obligation due truth.' using errcode='55000';
  end if;

  return jsonb_build_object(
    'applied',true,'kind','prior_work_reconciliation_v1','taskId',v_task.id,
    'outcome',v_outcome,'priorServiceDate',v_prior_day,'dueDateBefore',v_due_before,'dueDateAfter',v_task.due_date,
    'statusBefore',v_status_before,'statusAfter',v_task.status,'outcomeEventId',v_event_id,'transition',v_transition,
    'truthBoundary',jsonb_build_object(
      'nonterminalReconciliationDoesNotReschedule',true,
      'nonterminalReconciliationDoesNotCloseTask',true,
      'finishedAndNoLongerNeededRequireExplicitWorkerAnswer',true
    )
  );
end;
$function$;

alter function atlas.apply_worker_day_cue_result_contract_v1(uuid,jsonb) rename to apply_worker_day_cue_result_contract_v1_pre_prior_work;

create or replace function atlas.apply_worker_day_cue_result_contract_v1(p_cue_id uuid,p_response jsonb)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_kind text;
begin
  select nullif(c.result_contract->>'kind','') into v_kind
  from atlas.worker_day_cues c where c.id=p_cue_id;
  if v_kind='prior_work_reconciliation_v1' then
    return atlas.apply_prior_work_reconciliation_v1(p_cue_id,p_response);
  end if;
  return atlas.apply_worker_day_cue_result_contract_v1_pre_prior_work(p_cue_id,p_response);
end;
$function$;

alter function atlas.roll_expired_worker_tasks_v1(uuid,uuid,date) rename to roll_expired_worker_tasks_v1_pre_prior_work;

create or replace function atlas.roll_expired_worker_tasks_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_target_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_result jsonb;
  v_service_date date;
  v_reconciliation jsonb:='{}'::jsonb;
begin
  v_result:=atlas.roll_expired_worker_tasks_v1_pre_prior_work(p_farm_id,p_membership_id,p_target_date);
  begin
    v_service_date:=nullif(v_result->>'rolloverDestinationDate','')::date;
  exception when others then
    v_service_date:=null;
  end;
  if v_service_date is not null then
    v_reconciliation:=atlas.sync_prior_work_reconciliation_cues_v1(p_farm_id,p_membership_id,v_service_date);
  end if;
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'priorWorkReconciliation',coalesce(v_reconciliation,'{}'::jsonb),
    'contractVersion','worker_calendar_rollover_with_prior_work_reconciliation_v1'
  );
end;
$function$;

revoke all on function atlas.previous_worker_day_v1(uuid,uuid,date) from public,anon,authenticated;
revoke all on function atlas.sync_prior_work_reconciliation_cues_v1(uuid,uuid,date) from public,anon,authenticated;
revoke all on function atlas.apply_prior_work_reconciliation_v1(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.apply_worker_day_cue_result_contract_v1_pre_prior_work(uuid,jsonb) from public,anon,authenticated;
revoke all on function atlas.roll_expired_worker_tasks_v1_pre_prior_work(uuid,uuid,date) from public,anon,authenticated;