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
  v_result jsonb;
  v_keeper uuid;
  v_substitute_queue_rows integer;
begin
  v_result:=atlas.owner_substitute_worker_day_weed_card_internal_v1(
    p_farm_id,
    p_membership_id,
    p_service_date,
    p_displaced_task_id,
    p_substitute_task_id,
    p_displaced_resume_date,
    p_owner_reason,
    p_day_window,
    p_observed_care_state,
    p_observed_care_pressure,
    p_idempotency_key
  );

  -- First stamp the day-bound provenance. This metadata update intentionally
  -- runs through the normal task decorators/derivers.
  update atlas.tasks t
  set metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object(
        'owner_weed_slot_day_bound',true,
        'owner_weed_slot_service_date',p_service_date,
        'owner_weed_slot_day_bound_contract','owner_weed_slot_override_v3'
      ),
      updated_at=now()
  where t.id=p_substitute_task_id and t.farm_id=p_farm_id;

  -- Then bind only the released task carrier to the exceptional day. Keeping
  -- metadata out of this statement prevents the generic weed-task derivation
  -- trigger from reclassifying the carrier back to rhythm/persistent.
  update atlas.tasks t
  set work_lane='required',
      commitment_kind='hard_date',
      updated_at=now()
  where t.id=p_substitute_task_id and t.farm_id=p_farm_id;

  perform atlas.sync_task_release_queue_summary_v1(p_farm_id,'anna_weeding_rotation');
  perform atlas.reconcile_anna_serial_weeding_v1(p_farm_id);

  select qi.task_id into v_keeper
  from atlas.task_release_queue_items qi
  join atlas.tasks t on t.id=qi.task_id
  where qi.farm_id=p_farm_id and qi.queue_key='anna_weeding_rotation'
    and qi.state='active' and t.status in ('open','blocked')
  order by qi.position limit 1;

  select count(*)::integer into v_substitute_queue_rows
  from atlas.task_release_queue_items qi
  join atlas.tasks t on t.id=p_substitute_task_id
  where qi.farm_id=p_farm_id and qi.queue_key='anna_weeding_rotation'
    and qi.state in ('active','queued')
    and (qi.task_id=p_substitute_task_id or qi.planned_occurrence_id=t.planned_occurrence_id);

  if v_keeper is distinct from p_displaced_task_id then
    raise exception 'Owner Weed Slot Override failed after day binding: displaced Weed Card is not the serial keeper.' using errcode='55000';
  end if;
  if v_substitute_queue_rows<>0 then
    raise exception 'Owner Weed Slot Override failed after day binding: substitute leaked into the serial queue.' using errcode='55000';
  end if;

  return v_result||jsonb_build_object(
    'contractVersion','owner_weed_slot_override_v3',
    'substituteWorkLane','required',
    'substituteCommitmentKind','hard_date',
    'substituteDayBound',true,
    'serialKeeperTaskId',v_keeper,
    'substituteSerialQueueRows',v_substitute_queue_rows
  );
end;
$function$;

update atlas.authenticated_rpc_registry
set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object(
      'contractVersion','owner_weed_slot_override_v3',
      'dayBoundTriggerOrdering','metadata derivation completes before carrier work_lane/commitment_kind binding'
    ),
    reviewed_at=now()
where signature='atlas.owner_substitute_worker_day_weed_card_v1(uuid, uuid, date, uuid, uuid, date, text, text, text, text, text)';