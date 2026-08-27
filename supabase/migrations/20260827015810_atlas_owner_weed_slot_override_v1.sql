create or replace function atlas.capture_anna_weeding_serial_queue_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_worker_key text;
  v_queue_key constant text := 'anna_weeding_rotation';
  v_position integer;
  v_existing_state text;
  v_has_active boolean;
begin
  if pg_trigger_depth() > 1 then return new; end if;
  if new.status not in ('open','blocked') then return new; end if;
  if lower(coalesce(new.metadata->>'weed_card_managed','false')) not in ('true','yes','1') then return new; end if;
  if lower(coalesce(new.metadata->>'persistent_weed_card','false')) not in ('true','yes','1') then return new; end if;
  -- Owner-directed exceptional Weed Card work is intentionally outside the
  -- ordinary completion-gated serial rotation. The reconciler already honors
  -- this marker; capture must honor the same contract or later metadata edits
  -- can silently recreate queue debris.
  if lower(coalesce(new.metadata->>'serial_queue_bypass','false')) in ('true','yes','1') then return new; end if;
  if nullif(new.metadata->>'sequence_key','') is not null then return new; end if;

  select fm.worker_key into v_worker_key
  from atlas.farm_memberships fm
  where fm.id=new.assigned_membership_id and fm.active=true;
  if v_worker_key is distinct from 'anna' then return new; end if;

  select qi.state into v_existing_state
  from atlas.task_release_queue_items qi
  where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key
    and (qi.task_id=new.id or qi.planned_occurrence_id=new.planned_occurrence_id)
  order by qi.position limit 1;
  if v_existing_state is not null then return new; end if;

  select exists(
    select 1 from atlas.task_release_queue_items qi
    left join atlas.tasks t on t.id=qi.task_id
    where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key and qi.state='active'
      and coalesce(t.status,'open') in ('open','blocked')
  ) into v_has_active;

  select coalesce(max(qi.position),0)+1 into v_position
  from atlas.task_release_queue_items qi
  where qi.farm_id=new.farm_id and qi.queue_key=v_queue_key;

  insert into atlas.task_release_queue_items(
    farm_id,queue_key,task_id,planned_occurrence_id,maintenance_object_id,
    position,state,initial_batch,original_due_date,metadata
  ) values (
    new.farm_id,v_queue_key,new.id,new.planned_occurrence_id,
    case when coalesce(new.metadata->>'maintenance_object_id','') ~* '^[0-9a-f-]{36}$' then (new.metadata->>'maintenance_object_id')::uuid else new.generated_from_id end,
    v_position,case when v_has_active then 'queued' else 'active' end,false,new.due_date,
    jsonb_build_object('source','anna_weeding_serial_gate','captured_at',now(),'policy','completion_gated_serial')
  );

  update atlas.tasks set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
    'release_queue_key',v_queue_key,
    'release_queue_position',v_position,
    'release_queue_policy','completion_gated_serial',
    'weed_serial_gate',true
  ) where id=new.id;

  if v_has_active then
    perform atlas.defer_existing_task_to_occurrence_v1(new.id,'Waiting for prior Anna weeding task to be completed');
  end if;
  return new;
end;
$function$;

create or replace function atlas.owner_substitute_worker_day_weed_card_v1(
  p_farm_id uuid,
  p_membership_id uuid,
  p_service_date date,
  p_displaced_task_id uuid,
  p_substitute_task_id uuid,
  p_displaced_resume_date date,
  p_owner_reason text,
  p_day_window text default null,
  p_observed_care_state text default null,
  p_observed_care_pressure text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_displaced atlas.tasks%rowtype;
  v_substitute atlas.tasks%rowtype;
  v_displaced_card atlas.weed_cards%rowtype;
  v_substitute_card atlas.weed_cards%rowtype;
  v_displaced_object atlas.growing_objects%rowtype;
  v_substitute_object atlas.growing_objects%rowtype;
  v_substitute_maintenance atlas.maintenance_objects%rowtype;
  v_displaced_placement atlas.worker_day_task_placements%rowtype;
  v_substitute_placement atlas.worker_day_task_placements%rowtype;
  v_after_displaced_placement atlas.worker_day_task_placements%rowtype;
  v_after_substitute_placement atlas.worker_day_task_placements%rowtype;
  v_queue_key text;
  v_day_window text;
  v_displaced_day_window text;
  v_sort_order numeric(12,3);
  v_duration integer;
  v_displaced_duration integer;
  v_release_time time;
  v_notification_active boolean;
  v_removed_queue_rows integer := 0;
  v_reconcile jsonb;
  v_active_keeper uuid;
  v_substitute_queue_rows integer;
  v_same_idempotency boolean := false;
  v_existing_override jsonb;
  v_card_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  if not exists (
    select 1 from atlas.farm_memberships fm
    where fm.farm_id=p_farm_id and fm.active=true and fm.role='owner' and fm.user_id=auth.uid()
  ) then
    raise exception 'Owner farm membership required.' using errcode='42501';
  end if;
  if not exists (
    select 1 from atlas.farm_memberships fm
    where fm.id=p_membership_id and fm.farm_id=p_farm_id and fm.active=true and fm.role='farm_hand'
  ) then
    raise exception 'Active Farm Hand membership required.' using errcode='42501';
  end if;
  if p_service_date is null or p_displaced_resume_date is null then
    raise exception 'Service date and displaced resume date are required.' using errcode='22023';
  end if;
  if p_displaced_resume_date <= p_service_date then
    raise exception 'The displaced Weed Card must resume on a later worker day.' using errcode='22023';
  end if;
  if not atlas.worker_day_available_v1(p_farm_id,p_membership_id,p_displaced_resume_date) then
    raise exception 'The displaced resume date is not an available worker day.' using errcode='22023';
  end if;
  if p_displaced_task_id is null or p_substitute_task_id is null or p_displaced_task_id=p_substitute_task_id then
    raise exception 'Distinct displaced and substitute Weed Card tasks are required.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_owner_reason,'')),'') is null or length(btrim(p_owner_reason))>600 then
    raise exception 'Owner reason is required and must be 600 characters or fewer.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null or length(btrim(p_idempotency_key))>200 then
    raise exception 'An idempotency key is required and must be 200 characters or fewer.' using errcode='22023';
  end if;
  if p_day_window is not null and p_day_window not in ('morning','afternoon','evening') then
    raise exception 'Day window must be morning, afternoon, or evening.' using errcode='22023';
  end if;
  if p_observed_care_state is not null and p_observed_care_state not in (
    'settled','stirring','needs_tending','losing_shape','recovery_needed','resting','suppressed','decision_needed','unknown'
  ) then
    raise exception 'Unsupported observed care state.' using errcode='22023';
  end if;
  if p_observed_care_pressure is not null and p_observed_care_pressure not in ('none','light','moderate','heavy','severe','unknown') then
    raise exception 'Unsupported observed care pressure.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_farm_id::text||'|'||p_membership_id::text||'|owner_weed_slot_override_v1',0
  ));

  select * into v_displaced
  from atlas.tasks t
  where t.id=p_displaced_task_id and t.farm_id=p_farm_id and t.assigned_membership_id=p_membership_id
  for update;
  if v_displaced.id is null or v_displaced.status not in ('open','blocked') or v_displaced.action_key<>'weed' or v_displaced.parent_task_id is not null then
    raise exception 'The displaced task must be an active top-level Weed Card task assigned to this worker.' using errcode='55000';
  end if;

  select * into v_substitute
  from atlas.tasks t
  where t.id=p_substitute_task_id and t.farm_id=p_farm_id and t.assigned_membership_id=p_membership_id
  for update;
  if v_substitute.id is null or v_substitute.status not in ('open','blocked') or v_substitute.action_key<>'weed' or v_substitute.parent_task_id is not null then
    raise exception 'The substitute task must be an active top-level Weed Card task assigned to this worker.' using errcode='55000';
  end if;

  select count(distinct wc.id)::integer into v_card_count
  from atlas.task_objects tx join atlas.weed_cards wc on wc.object_id=tx.object_id
  where tx.task_id=v_displaced.id;
  if v_card_count<>1 then
    raise exception 'The displaced task must resolve to exactly one Weed Card.' using errcode='55000';
  end if;
  select wc.* into v_displaced_card
  from atlas.task_objects tx join atlas.weed_cards wc on wc.object_id=tx.object_id
  where tx.task_id=v_displaced.id limit 1;
  select go.* into v_displaced_object from atlas.growing_objects go where go.id=v_displaced_card.object_id;

  select count(distinct wc.id)::integer into v_card_count
  from atlas.task_objects tx join atlas.weed_cards wc on wc.object_id=tx.object_id
  where tx.task_id=v_substitute.id;
  if v_card_count<>1 then
    raise exception 'The substitute task must resolve to exactly one Weed Card.' using errcode='55000';
  end if;
  select wc.* into v_substitute_card
  from atlas.task_objects tx join atlas.weed_cards wc on wc.object_id=tx.object_id
  where tx.task_id=v_substitute.id limit 1;
  if v_substitute_card.id=v_displaced_card.id then
    raise exception 'The substitute must be a different Weed Card.' using errcode='22023';
  end if;
  select go.* into v_substitute_object from atlas.growing_objects go where go.id=v_substitute_card.object_id;
  select mo.* into v_substitute_maintenance from atlas.maintenance_objects mo where mo.id=v_substitute_card.maintenance_object_id;

  select qi.queue_key into v_queue_key
  from atlas.task_release_queue_items qi
  where qi.farm_id=p_farm_id and qi.task_id=v_displaced.id and qi.state='active'
  order by qi.position limit 1;
  if v_queue_key is distinct from 'anna_weeding_rotation' then
    raise exception 'The displaced task is not the active Anna serial Weed Card.' using errcode='55000';
  end if;

  select * into v_displaced_placement from atlas.worker_day_task_placements p where p.task_id=v_displaced.id;
  select * into v_substitute_placement from atlas.worker_day_task_placements p where p.task_id=v_substitute.id;

  v_existing_override:=coalesce(v_substitute.metadata->'owner_weed_slot_override','{}'::jsonb);
  v_same_idempotency:=coalesce(v_existing_override->>'idempotencyKey','')=btrim(p_idempotency_key);

  v_day_window:=coalesce(
    p_day_window,
    case when v_substitute_placement.id is not null and v_substitute_placement.service_date=p_service_date and v_substitute_placement.state='placed' then v_substitute_placement.day_window end,
    case when v_displaced_placement.id is not null and v_displaced_placement.service_date=p_service_date and v_displaced_placement.state='placed' then v_displaced_placement.day_window end,
    case when v_substitute.metadata->>'work_window_key' in ('morning','afternoon','evening') then v_substitute.metadata->>'work_window_key' end,
    'morning'
  );
  v_displaced_day_window:=coalesce(
    case when v_displaced_placement.id is not null then v_displaced_placement.day_window end,
    case when v_displaced.metadata->>'work_window_key' in ('morning','afternoon','evening') then v_displaced.metadata->>'work_window_key' end,
    v_day_window,
    'morning'
  );
  v_sort_order:=coalesce(
    case when v_substitute_placement.id is not null and v_substitute_placement.service_date=p_service_date and v_substitute_placement.state='placed' then v_substitute_placement.sort_order end,
    case when v_displaced_placement.id is not null and v_displaced_placement.service_date=p_service_date and v_displaced_placement.state='placed' then v_displaced_placement.sort_order end,
    10000
  );

  select greatest(coalesce(
    nullif(v_substitute_maintenance.remaining_effort_minutes,0),
    nullif(v_substitute_maintenance.current_effort_minutes,0),
    (select cp.expected_active_minutes from atlas.task_capacity_profiles cp where cp.task_id=v_substitute.id),
    case when coalesce(v_substitute.metadata->>'estimated_minutes','') ~ '^\d+$' then (v_substitute.metadata->>'estimated_minutes')::integer end,
    30
  ),5) into v_duration;

  select greatest(coalesce(
    v_displaced_placement.planned_duration_minutes,
    (select cp.expected_active_minutes from atlas.task_capacity_profiles cp where cp.task_id=v_displaced.id),
    case when coalesce(v_displaced.metadata->>'estimated_minutes','') ~ '^\d+$' then (v_displaced.metadata->>'estimated_minutes')::integer end,
    30
  ),5) into v_displaced_duration;

  update atlas.tasks t
  set metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object(
        'serial_queue_bypass',true,
        'owner_schedule_override',true,
        'calendar_commitment_kind','owner_hard_date',
        'estimated_minutes',v_duration,
        'work_window_key',v_day_window,
        'owner_weed_slot_override',jsonb_build_object(
          'contractVersion','owner_weed_slot_override_v1',
          'serviceDate',p_service_date,
          'displacedTaskId',v_displaced.id,
          'displacedWeedCardId',v_displaced_card.id,
          'substituteWeedCardId',v_substitute_card.id,
          'displacedResumeDate',p_displaced_resume_date,
          'ownerReason',btrim(p_owner_reason),
          'idempotencyKey',btrim(p_idempotency_key),
          'appliedAt',now(),
          'appliedBy',auth.uid()
        )
      ),
      updated_at=now()
  where t.id=v_substitute.id;

  update atlas.tasks t
  set metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object(
        'owner_weed_slot_displacement',jsonb_build_object(
          'contractVersion','owner_weed_slot_override_v1',
          'serviceDate',p_service_date,
          'substituteTaskId',v_substitute.id,
          'substituteWeedCardId',v_substitute_card.id,
          'resumeDate',p_displaced_resume_date,
          'ownerReason',btrim(p_owner_reason),
          'idempotencyKey',btrim(p_idempotency_key),
          'recordedAt',now(),
          'recordedBy',auth.uid()
        )
      ),
      updated_at=now()
  where t.id=v_displaced.id;

  if v_substitute.planned_occurrence_id is not null then
    update atlas.planned_work_occurrences o
    set state='released',
        planned_due_date=p_service_date,
        not_before_date=p_service_date,
        released_task_id=v_substitute.id,
        released_at=coalesce(o.released_at,now()),
        gate_satisfied_at=coalesce(o.gate_satisfied_at,now()),
        metadata=(coalesce(o.metadata,'{}'::jsonb)-'serialWeedingQueued'-'serialWeedingQueuedAt'-'serialWeedingQueueKey')
          ||jsonb_build_object(
            'ownerWeedSlotOverride',true,
            'ownerWeedSlotOverrideAt',now(),
            'calendar_commitment_kind','owner_hard_date',
            'ownerWeedSlotOverrideIdempotencyKey',btrim(p_idempotency_key)
          ),
        task_payload=jsonb_set(
          coalesce(o.task_payload,'{}'::jsonb),
          '{metadata}',
          (coalesce(o.task_payload->'metadata','{}'::jsonb)-'serial_queue_state')
            ||jsonb_build_object('serial_queue_bypass',true,'owner_schedule_override',true,'calendar_commitment_kind','owner_hard_date'),
          true
        ),
        updated_at=now()
    where o.id=v_substitute.planned_occurrence_id;
  end if;

  delete from atlas.task_release_queue_items qi
  where qi.farm_id=p_farm_id
    and qi.queue_key=v_queue_key
    and qi.state in ('active','queued')
    and (qi.task_id=v_substitute.id or qi.planned_occurrence_id=v_substitute.planned_occurrence_id);
  get diagnostics v_removed_queue_rows=row_count;

  insert into atlas.worker_day_task_placements(
    organization_id,farm_id,membership_id,task_id,service_date,day_window,sort_order,
    placement_source,placement_reason,state,owner_actor_user_id,planned_duration_minutes
  ) values (
    v_substitute.organization_id,p_farm_id,p_membership_id,v_substitute.id,p_service_date,v_day_window,v_sort_order,
    'owner','Owner Weed Slot Override: '||btrim(p_owner_reason),'placed',auth.uid(),v_duration
  )
  on conflict(task_id) do update set
    service_date=excluded.service_date,
    day_window=excluded.day_window,
    sort_order=excluded.sort_order,
    placement_source='owner',
    placement_reason=excluded.placement_reason,
    state='placed',
    owner_actor_user_id=auth.uid(),
    planned_duration_minutes=excluded.planned_duration_minutes,
    updated_at=now()
  returning * into v_after_substitute_placement;

  insert into atlas.worker_day_task_placements(
    organization_id,farm_id,membership_id,task_id,service_date,day_window,sort_order,
    placement_source,placement_reason,state,owner_actor_user_id,planned_duration_minutes
  ) values (
    v_displaced.organization_id,p_farm_id,p_membership_id,v_displaced.id,p_displaced_resume_date,v_displaced_day_window,
    coalesce(v_displaced_placement.sort_order,10000),
    'owner','Owner Weed Slot Override: displaced on '||p_service_date::text||' by '||v_substitute_object.label||'; remains unresolved and resumes '||p_displaced_resume_date::text||'. '||btrim(p_owner_reason),
    'placed',auth.uid(),v_displaced_duration
  )
  on conflict(task_id) do update set
    service_date=excluded.service_date,
    day_window=excluded.day_window,
    placement_source='owner',
    placement_reason=excluded.placement_reason,
    state='placed',
    owner_actor_user_id=auth.uid(),
    planned_duration_minutes=excluded.planned_duration_minutes,
    updated_at=now()
  returning * into v_after_displaced_placement;

  if not v_same_idempotency then
    insert into atlas.worker_day_task_placement_events(
      organization_id,farm_id,membership_id,task_id,placement_id,event_kind,
      from_service_date,to_service_date,from_day_window,to_day_window,from_sort_order,to_sort_order,
      actor_user_id,metadata,from_planned_occurrence_id,to_planned_occurrence_id
    ) values (
      v_substitute.organization_id,p_farm_id,p_membership_id,v_substitute.id,v_after_substitute_placement.id,
      case when v_substitute_placement.id is null then 'owner_added' else 'owner_rescheduled' end,
      v_substitute_placement.service_date,v_after_substitute_placement.service_date,
      v_substitute_placement.day_window,v_after_substitute_placement.day_window,
      v_substitute_placement.sort_order,v_after_substitute_placement.sort_order,
      auth.uid(),jsonb_build_object(
        'contractVersion','owner_weed_slot_override_v1','role','substitute','ownerReason',btrim(p_owner_reason),
        'displacedTaskId',v_displaced.id,'displacedResumeDate',p_displaced_resume_date,'idempotencyKey',btrim(p_idempotency_key)
      ),v_substitute_placement.planned_occurrence_id,v_after_substitute_placement.planned_occurrence_id
    );

    insert into atlas.worker_day_task_placement_events(
      organization_id,farm_id,membership_id,task_id,placement_id,event_kind,
      from_service_date,to_service_date,from_day_window,to_day_window,from_sort_order,to_sort_order,
      actor_user_id,metadata,from_planned_occurrence_id,to_planned_occurrence_id
    ) values (
      v_displaced.organization_id,p_farm_id,p_membership_id,v_displaced.id,v_after_displaced_placement.id,
      case when v_displaced_placement.id is null then 'owner_added' else 'owner_rescheduled' end,
      v_displaced_placement.service_date,v_after_displaced_placement.service_date,
      v_displaced_placement.day_window,v_after_displaced_placement.day_window,
      v_displaced_placement.sort_order,v_after_displaced_placement.sort_order,
      auth.uid(),jsonb_build_object(
        'contractVersion','owner_weed_slot_override_v1','role','displaced','ownerReason',btrim(p_owner_reason),
        'substituteTaskId',v_substitute.id,'resumeDate',p_displaced_resume_date,'idempotencyKey',btrim(p_idempotency_key)
      ),v_displaced_placement.planned_occurrence_id,v_after_displaced_placement.planned_occurrence_id
    );
  end if;

  v_release_time:=case v_day_window when 'afternoon' then time '14:00' when 'evening' then time '17:00' else time '08:00' end;
  v_notification_active:=atlas.worker_day_placement_is_live_v1(p_farm_id,p_membership_id,p_service_date,now());

  insert into atlas.task_notification_plans(
    farm_id,task_id,release_local_time,close_local_time,nudge_after_minutes,group_key,group_label,source,active,metadata
  ) values (
    p_farm_id,v_substitute.id,v_release_time,null,60,'owner-weed-slot:'||v_substitute_object.stable_key,'Weeding',
    'owner_weed_slot_override_v1',v_notification_active,
    jsonb_build_object(
      'contractVersion','owner_weed_slot_override_v1','serviceDate',p_service_date,'dayWindow',v_day_window,
      'ownerReason',btrim(p_owner_reason),'displacedTaskId',v_displaced.id,'idempotencyKey',btrim(p_idempotency_key)
    )
  )
  on conflict(task_id) do update set
    release_local_time=excluded.release_local_time,
    close_local_time=excluded.close_local_time,
    nudge_after_minutes=excluded.nudge_after_minutes,
    group_key=excluded.group_key,
    group_label=excluded.group_label,
    source=excluded.source,
    active=excluded.active,
    metadata=excluded.metadata,
    updated_at=now();

  if p_observed_care_state is not null then
    insert into atlas.object_state(
      object_id,farm_id,care_state,care_pressure,care_freshness,care_observed_at,care_source_kind,
      presentability,last_checked_at,care_reason,metadata
    ) values (
      v_substitute_object.id,p_farm_id,p_observed_care_state,coalesce(p_observed_care_pressure,'unknown'),'observed',now(),'observation',
      case when p_observed_care_state in ('needs_tending','losing_shape','recovery_needed') then 'needs_attention' else 'unknown' end,
      p_service_date,
      jsonb_build_object('source','owner_weed_slot_override_v1','ownerReason',btrim(p_owner_reason),'idempotencyKey',btrim(p_idempotency_key)),
      jsonb_build_object('current_care_truth_source','owner_weed_slot_override_v1','weed_pressure_unquantified',p_observed_care_pressure is null)
    )
    on conflict(object_id) do update set
      care_state=excluded.care_state,
      care_pressure=coalesce(p_observed_care_pressure,atlas.object_state.care_pressure,'unknown'),
      care_freshness='observed',
      care_observed_at=now(),
      care_source_kind='observation',
      presentability=case when p_observed_care_state in ('needs_tending','losing_shape','recovery_needed') then 'needs_attention' else atlas.object_state.presentability end,
      last_checked_at=p_service_date,
      care_reason=excluded.care_reason,
      metadata=coalesce(atlas.object_state.metadata,'{}'::jsonb)||excluded.metadata,
      care_updated_at=now(),
      updated_at=now();

    if p_observed_care_state in ('needs_tending','losing_shape','recovery_needed') then
      update atlas.weed_cards wc
      set next_review_on=p_service_date,
          metadata=coalesce(wc.metadata,'{}'::jsonb)||jsonb_build_object(
            'weed_card_condition_stale',wc.current_condition='clear',
            'weed_card_observation','needs_tending_unquantified',
            'weed_card_observation_source','owner_weed_slot_override_v1',
            'weed_card_observation_at',now()
          ),
          updated_at=now()
      where wc.id=v_substitute_card.id;

      update atlas.maintenance_objects mo
      set remaining_effort_minutes=greatest(coalesce(mo.remaining_effort_minutes,0),v_duration),
          metadata=coalesce(mo.metadata,'{}'::jsonb)||jsonb_build_object(
            'maintenance_condition_stale',mo.condition='maintained',
            'maintenance_observation','needs_tending_unquantified',
            'maintenance_observation_source','owner_weed_slot_override_v1',
            'maintenance_observation_at',now()
          ),
          updated_at=now()
      where mo.id=v_substitute_card.maintenance_object_id;
    end if;
  end if;

  perform atlas.sync_task_release_queue_summary_v1(p_farm_id,v_queue_key);
  v_reconcile:=atlas.reconcile_anna_serial_weeding_v1(p_farm_id);

  select qi.task_id into v_active_keeper
  from atlas.task_release_queue_items qi
  join atlas.tasks t on t.id=qi.task_id
  where qi.farm_id=p_farm_id and qi.queue_key=v_queue_key and qi.state='active' and t.status in ('open','blocked')
  order by qi.position limit 1;

  select count(*)::integer into v_substitute_queue_rows
  from atlas.task_release_queue_items qi
  where qi.farm_id=p_farm_id and qi.queue_key=v_queue_key
    and (qi.task_id=v_substitute.id or qi.planned_occurrence_id=v_substitute.planned_occurrence_id)
    and qi.state in ('active','queued');

  if v_active_keeper is distinct from v_displaced.id then
    raise exception 'Owner Weed Slot Override failed: displaced Weed Card is no longer the serial keeper.' using errcode='55000';
  end if;
  if v_substitute_queue_rows<>0 then
    raise exception 'Owner Weed Slot Override failed: substitute Weed Card leaked into the serial queue.' using errcode='55000';
  end if;

  return jsonb_build_object(
    'contractVersion','owner_weed_slot_override_v1',
    'idempotencyKey',btrim(p_idempotency_key),
    'deduplicated',v_same_idempotency,
    'farmId',p_farm_id,
    'membershipId',p_membership_id,
    'serviceDate',p_service_date,
    'dayWindow',v_day_window,
    'plannedDurationMinutes',v_duration,
    'displacedTaskId',v_displaced.id,
    'displacedWeedCardId',v_displaced_card.id,
    'displacedResumeDate',p_displaced_resume_date,
    'substituteTaskId',v_substitute.id,
    'substituteWeedCardId',v_substitute_card.id,
    'serialKeeperTaskId',v_active_keeper,
    'substituteSerialQueueRows',v_substitute_queue_rows,
    'queueRowsRemoved',v_removed_queue_rows,
    'notificationActive',v_notification_active,
    'reconcile',v_reconcile
  );
end;
$function$;

revoke all on function atlas.owner_substitute_worker_day_weed_card_v1(uuid,uuid,date,uuid,uuid,date,text,text,text,text,text) from public;
grant execute on function atlas.owner_substitute_worker_day_weed_card_v1(uuid,uuid,date,uuid,uuid,date,text,text,text,text,text) to authenticated;
grant execute on function atlas.owner_substitute_worker_day_weed_card_v1(uuid,uuid,date,uuid,uuid,date,text,text,text,text,text) to service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,
  service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.owner_substitute_worker_day_weed_card_v1(uuid, uuid, date, uuid, uuid, date, text, text, text, text, text)',
  'owner_admin_endpoint','verified','active',true,true,true,1,1,
  jsonb_build_object(
    'source','atlas_owner_weed_slot_override_v1',
    'authorization','owner only',
    'purpose','Substitute one Weed Card into a specific worker day without advancing or duplicating the ordinary Anna serial Weed Card queue.',
    'serialInvariant','displaced task remains the active serial keeper; substitute has zero active/queued serial rows',
    'publicInheritanceRemoved',true
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  evidence=excluded.evidence,
  reviewed_at=now(),
  anonymous_execute_expected=false;