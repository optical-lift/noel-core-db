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
      update atlas.worker_day_cues cue
      set payload=coalesce(cue.payload,'{}'::jsonb)||jsonb_build_object(
            'recoveryTitle','Prior work — '||v_row.title,
            'recoveryPrompt','What happened with this work on '||to_char(v_row.prior_service_date,'Dy, Mon FMDD')||'?'
          ),
          updated_at=now()
      where cue.id=v_cue_id
        and (
          nullif(cue.payload->>'recoveryTitle','') is null
          or nullif(cue.payload->>'recoveryPrompt','') is null
        );
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
        'recoveryTitle','Prior work — '||v_row.title,
        'recoveryPrompt','What happened with this work on '||to_char(v_row.prior_service_date,'Dy, Mon FMDD')||'?',
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
      'cueCreationDoesNotMutateTaskTruth',true,
      'staleRecoveryNamesOriginalServiceDay',true
    )
  );
end;
$function$;

update atlas.worker_day_cues cue
set payload=coalesce(cue.payload,'{}'::jsonb)||jsonb_build_object(
      'recoveryTitle','Prior work — '||regexp_replace(cue.title,'^Yesterday — ','') ,
      'recoveryPrompt','What happened with this work on '||to_char((cue.result_contract->>'priorServiceDate')::date,'Dy, Mon FMDD')||'?'
    ),
    updated_at=now()
where cue.result_contract->>'kind'='prior_work_reconciliation_v1'
  and cue.status not in ('resolved','dismissed')
  and (
    nullif(cue.payload->>'recoveryTitle','') is null
    or nullif(cue.payload->>'recoveryPrompt','') is null
  );