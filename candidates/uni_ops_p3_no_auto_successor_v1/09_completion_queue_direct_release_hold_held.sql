-- 6A HELD: exact live source of atlas.release_next_task_in_queue_v1.
-- Original pg_get_functiondef MD5 f0457263c5e559bfe47feaf477111412; do not rebaseline silently.
-- Preserves independently authorized original release routes not involving
-- the three known completion-gated queues. This is NOT production SQL.
BEGIN;
DO $pin$
BEGIN
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='atlas' AND p.proname='release_next_task_in_queue_v1') IS DISTINCT FROM 'f0457263c5e559bfe47feaf477111412' THEN
  RAISE EXCEPTION 'One-source completion gated old queue writer drift';
 END IF;
END;
$pin$;

CREATE OR REPLACE FUNCTION atlas.release_next_task_in_queue_v1(p_farm_id uuid, p_queue_key text, p_completed_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_next_item atlas.task_release_queue_items%rowtype;
  v_due_date date;
  v_completed_date date:=coalesce(p_completed_date,(now() at time zone 'America/Chicago')::date);
  v_occurrence_id uuid;
  v_task_id uuid;
  v_release_timing text;
  v_approval_required boolean:=false;
  v_approved_date date;
  v_is_pot_up_serial boolean:=false;
  v_is_owner_completion_gated boolean:=false;
  v_is_anna_weeding boolean:=false;
  v_expected_requirement_set_key text;
  v_boundary_id uuid;
  v_authorized_from_item_id uuid;
  v_authorizer atlas.task_release_queue_items%rowtype;
  v_boundary atlas.requirement_boundary_events%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_farm_id::text||':'||p_queue_key,0));

  if exists(
    select 1
    from atlas.task_release_queue_items qi
    left join atlas.tasks task on task.id=qi.task_id
    left join atlas.planned_work_occurrences occurrence on occurrence.id=qi.planned_occurrence_id
    where qi.farm_id=p_farm_id
      and qi.queue_key=p_queue_key
      and qi.initial_batch
      and qi.state<>'completed'
      and coalesce(task.status,'open')<>'done'
      and coalesce(occurrence.state,'released')<>'completed'
  ) then
    perform atlas.sync_task_release_queue_summary_v1(p_farm_id,p_queue_key);
    return null;
  end if;

  select qi.* into v_next_item
  from atlas.task_release_queue_items qi
  where qi.farm_id=p_farm_id
    and qi.queue_key=p_queue_key
    and qi.state='queued'
  order by qi.position
  for update
  limit 1;

  if not found then
    perform atlas.sync_task_release_queue_summary_v1(p_farm_id,p_queue_key);
    return null;
  end if;

  v_is_pot_up_serial:=coalesce(v_next_item.metadata->>'queue_kind','')='pot_up_serial';
  v_is_owner_completion_gated:=p_queue_key in ('owner_social_content_queue','owner_venue_marketing_queue');
  v_is_anna_weeding:=p_queue_key='anna_weeding_rotation';

  if v_is_pot_up_serial or v_is_owner_completion_gated or v_is_anna_weeding then
    v_expected_requirement_set_key:=case
      when v_is_pot_up_serial then 'pot_up_serial_predecessor_completion_v1'
      when v_is_owner_completion_gated then 'owner_completion_gated_predecessor_completion_v1'
      else 'anna_weeding_predecessor_completion_v1'
    end;

    begin
      v_boundary_id:=nullif(v_next_item.metadata->>'release_boundary_event_id','')::uuid;
      v_authorized_from_item_id:=nullif(v_next_item.metadata->>'release_authorized_from_queue_item_id','')::uuid;
    exception when invalid_text_representation then
      raise exception 'Completion-gated release provenance is malformed.' using errcode='23514';
    end;

    if v_boundary_id is null
       or v_authorized_from_item_id is null
       or coalesce(v_next_item.metadata->>'release_requirement_set_key','')<>v_expected_requirement_set_key then
      raise exception 'Completion-gated release requires an authorizing State Progression boundary.' using errcode='23514';
    end if;

    select qi.* into v_authorizer
    from atlas.task_release_queue_items qi
    where qi.id=v_authorized_from_item_id
      and qi.farm_id=v_next_item.farm_id
      and qi.queue_key=v_next_item.queue_key
      and qi.id=(
        select previous.id
        from atlas.task_release_queue_items previous
        where previous.farm_id=v_next_item.farm_id
          and previous.queue_key=v_next_item.queue_key
          and previous.position<v_next_item.position
          and previous.state<>'skipped'
        order by previous.position desc
        limit 1
      );

    if v_authorizer.id is null
       or v_authorizer.state<>'completed'
       or coalesce(v_authorizer.metadata->>'completion_boundary_event_id','')<>v_boundary_id::text then
      raise exception 'Completion-gated release is not authorized by the immediately preceding completed queue item.' using errcode='23514';
    end if;

    select b.* into v_boundary
    from atlas.requirement_boundary_events b
    where b.id=v_boundary_id;

    if v_boundary.id is null
       or v_boundary.subject_kind<>'task_release_queue_item'
       or v_boundary.subject_id is distinct from v_authorizer.id
       or v_boundary.requirement_set_key<>v_expected_requirement_set_key
       or v_boundary.boundary_kind<>'closed'
       or v_boundary.from_state<>'open'
       or v_boundary.to_state<>'satisfied'
       or v_boundary.source_kind<>'task'
       or v_boundary.source_id is distinct from v_authorizer.task_id then
      raise exception 'Completion-gated release boundary does not match its predecessor evidence.' using errcode='23514';
    end if;
  end if;

  -- P3 / November 4 amendment 6A: predecessor completion is a proven
  -- requirement boundary, NEVER a standing grant to create/release another
  -- Work. Direct callers of this helper cannot bypass the five old Done
  -- trigger overlays by supplying an older closed boundary event. Preserve
  -- the pending queue and its true source evidence for a later independent
  -- first-Work offer and worker acceptance. Do not mark it eligible or
  -- manufacture the next task.
  IF v_is_pot_up_serial OR v_is_owner_completion_gated OR v_is_anna_weeding THEN
    UPDATE atlas.task_release_queue_items
    SET metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'completion_requirement_boundary_id',v_boundary_id,
          'predecessor_requirement_satisfied',true,
          'independent_new_work_authorization_required',true,
          'new_work_released',false,
          'gate_classification','predecessor_done_is_not_new_issuance'
        ),
        updated_at=now()
    WHERE id=v_next_item.id
      AND state='queued';
    PERFORM atlas.sync_task_release_queue_summary_v1(p_farm_id,p_queue_key);
    RETURN NULL;
  END IF;

  v_approval_required:=coalesce((v_next_item.metadata->>'owner_schedule_approval_required')::boolean,false);
  v_approved_date:=nullif(v_next_item.metadata->>'owner_schedule_approved_date','')::date;

  if v_approval_required and v_approved_date is null then
    update atlas.task_release_queue_items
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'owner_schedule_approval_required',true,
          'awaiting_owner_schedule_approval',true,
          'awaiting_owner_schedule_approval_at',now()
        ),
        updated_at=now()
    where id=v_next_item.id;
    perform atlas.sync_task_release_queue_summary_v1(p_farm_id,p_queue_key);
    return null;
  end if;

  v_occurrence_id:=coalesce(
    v_next_item.planned_occurrence_id,
    (select task.planned_occurrence_id from atlas.tasks task where task.id=v_next_item.task_id)
  );
  if v_occurrence_id is null then
    raise exception 'Queued item % has no planned occurrence and cannot be released safely.',v_next_item.id using errcode='23514';
  end if;

  v_release_timing:=coalesce(nullif(v_next_item.metadata->>'release_timing',''),'next_workday');
  if v_release_timing='same_day' then
    v_due_date:=v_completed_date;
  else
    v_due_date:=v_completed_date+1;
    if extract(dow from v_due_date)=0 then v_due_date:=v_due_date+1; end if;
  end if;

  if v_approved_date is not null then
    v_due_date:=greatest(v_due_date,v_approved_date);
  end if;
  if extract(dow from v_due_date)=0 then v_due_date:=v_due_date+1; end if;

  update atlas.planned_work_occurrences
  set planned_due_date=v_due_date,
      not_before_date=v_due_date,
      gate_satisfied_at=now(),
      state=case when state in ('released','completed') then state else 'eligible' end,
      work_lane=case when v_is_pot_up_serial then 'process_continuation' else work_lane end,
      commitment_kind=case when v_is_pot_up_serial then 'dependency' else commitment_kind end,
      task_payload=case when v_is_pot_up_serial then
        jsonb_set(
          jsonb_set(
            jsonb_set(
              coalesce(task_payload,'{}'::jsonb),
              '{work_lane}',to_jsonb('process_continuation'::text),true
            ),
            '{commitment_kind}',to_jsonb('dependency'::text),true
          ),
          '{metadata}',
          coalesce(task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
            'work_lane','process_continuation',
            'commitment_kind','dependency',
            'classification_correction_reason','Completion-gated serial pot-up work is process continuation and cannot be treated as discretionary backlog.',
            'classification_correction_source','release_next_task_in_queue_v1'
          ),
          true
        )
      else task_payload end,
      metadata=(coalesce(metadata,'{}'::jsonb)-'budgetBlocked')||jsonb_build_object(
        'release_queue_key',p_queue_key,
        'release_queue_position',v_next_item.position,
        'released_after_previous_completion',true,
        'released_for_date',v_due_date,
        'queue_gate_satisfied_at',now(),
        'queue_release_timing',v_release_timing,
        'serial_process_continuation',v_is_pot_up_serial
      ),
      updated_at=now()
  where id=v_occurrence_id;

  if v_is_pot_up_serial then
    perform atlas.materialize_specific_work_occurrence_v1(v_occurrence_id,v_due_date);
  else
    perform atlas.release_eligible_work_v1(p_farm_id,v_due_date,1);
  end if;

  select released_task_id into v_task_id
  from atlas.planned_work_occurrences
  where id=v_occurrence_id;

  if v_task_id is not null
     and exists(select 1 from atlas.tasks where id=v_task_id and status in ('open','blocked')) then
    update atlas.task_release_queue_items
    set task_id=v_task_id,
        planned_occurrence_id=v_occurrence_id,
        state='active',
        activated_at=now(),
        updated_at=now(),
        metadata=(coalesce(metadata,'{}'::jsonb)-'awaiting_owner_schedule_approval'-'awaiting_owner_schedule_approval_at'-'release_waiting_on_capacity')||jsonb_build_object(
          'owner_schedule_approval_required',v_approval_required,
          'released_after_completion',true,
          'released_for_date',v_due_date,
          'released_at',now(),
          'release_timing',v_release_timing,
          'release_architecture',case
            when v_is_pot_up_serial then 'boundary_authorized_process_continuation_v1'
            when v_is_owner_completion_gated then 'boundary_authorized_completion_gated_release_v1'
            when v_is_anna_weeding then 'boundary_authorized_completion_gated_release_v1'
            else 'planned_occurrence_gate'
          end
        )
    where id=v_next_item.id;
  else
    update atlas.task_release_queue_items
    set planned_occurrence_id=v_occurrence_id,
        task_id=null,
        state='queued',
        updated_at=now(),
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'owner_schedule_approval_required',v_approval_required,
          'release_attempted_at',now(),
          'release_waiting_on_capacity',true,
          'release_timing',v_release_timing,
          'release_architecture',case
            when v_is_pot_up_serial then 'boundary_authorized_process_continuation_v1'
            when v_is_owner_completion_gated then 'boundary_authorized_completion_gated_release_v1'
            when v_is_anna_weeding then 'boundary_authorized_completion_gated_release_v1'
            else 'planned_occurrence_gate'
          end
        )
    where id=v_next_item.id;
    v_task_id:=null;
  end if;

  perform atlas.sync_task_release_queue_summary_v1(p_farm_id,p_queue_key);
  return v_task_id;
end;
$function$

COMMIT;
