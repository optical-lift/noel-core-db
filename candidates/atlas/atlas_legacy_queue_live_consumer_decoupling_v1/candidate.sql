-- HELD ATLAS PACKAGE B: decouple five live nonqueue consumers from the obsolete queue.
-- Bounded behavior preservation:
--   * Deferred Task capture still preserves existing occurrence/handoff payloads;
--     the old queue FK already ON DELETE SET NULL.
--   * Paid-work discovery continues excluding historical queue-origin Tasks
--     by their original immutable task.metadata.release_queue_key evidence.
--   * Worker future-day projections retain existing JSON field 'weedQueue'
--     as an empty array; work projection, capacity, and signed audience unchanged.
-- No new feature, grant, Work, Task, Result, history deletion, or harvest cutover.
-- This is source-only until protected clone proof and separately approved release.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';

CREATE TEMP TABLE atlas_retire_queue_consumer_before ON COMMIT DROP AS
 SELECT p.oid,p.proname,p.proowner,p.proacl,p.prosecdef,p.proconfig
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='atlas' AND p.proname IN (
  'capture_deferred_task_v1','deal_next_paid_work_v1','defer_existing_task_to_occurrence_v1','floating_paid_work_candidates_v1','worker_future_day_projection_source_v1'
 );
DO $atlas_consumer_source_guard$
DECLARE expected record; actual_oid oid; actual_md5 text;
BEGIN
 IF to_regclass('atlas.task_release_queue_items') IS NULL THEN
  RAISE EXCEPTION 'Expected historical queue source missing; final table retirement is separate';
 END IF;
 IF (SELECT count(*) FROM atlas_retire_queue_consumer_before)<>5 THEN
  RAISE EXCEPTION 'Exact five consumer functions are required';
 END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_constraint
  WHERE conrelid='atlas.task_release_queue_items'::regclass
    AND conname='task_release_queue_items_task_id_fkey'
    AND pg_get_constraintdef(oid) LIKE '%ON DELETE SET NULL'
 ) THEN
  RAISE EXCEPTION 'Deferred Task queue pointer lacks known ON DELETE SET NULL custody';
 END IF;
 FOR expected IN SELECT * FROM (VALUES
    ('atlas.capture_deferred_task_v1()','b1047a9bbfd648ef70b61cf08b8c8a15'),
    ('atlas.deal_next_paid_work_v1(uuid, uuid, date, boolean)','87859a475edb33e286963940de744a5b'),
    ('atlas.defer_existing_task_to_occurrence_v1(uuid, text)','b536ddcd18357fac00bcf468a563a963'),
    ('atlas.floating_paid_work_candidates_v1(uuid, uuid, date)','d0be6fa30c302d33b0033fd2cb38d519'),
    ('atlas.worker_future_day_projection_source_v1(uuid, uuid, date, date)','79d93269a25b07fa6d00fffc84c47081')
 ) t(signature,source_md5)
 LOOP
  actual_oid:=to_regprocedure(expected.signature)::oid;
  IF actual_oid IS NULL THEN
   RAISE EXCEPTION 'Expected exact function signature absent: %',expected.signature;
  END IF;
  SELECT md5(pg_get_functiondef(actual_oid)) INTO actual_md5;
  IF actual_md5 IS DISTINCT FROM expected.source_md5 THEN
   RAISE EXCEPTION 'Source drift for %, expected % got %',expected.signature,expected.source_md5,actual_md5;
  END IF;
 END LOOP;
 PERFORM set_config('atlas.pre_queue_count',(SELECT count(*)::text FROM atlas.task_release_queue_items),true);
 PERFORM set_config('atlas.pre_work_count',(SELECT count(*)::text FROM atlas.work_items),true);
 PERFORM set_config('atlas.pre_requirement_count',(SELECT count(*)::text FROM atlas.work_requirements),true);
 PERFORM set_config('atlas.pre_task_count',(SELECT count(*)::text FROM atlas.tasks),true);
END $atlas_consumer_source_guard$;

-- Existing signed capture_deferred_task_v1 — same signature, owner, ACL and SECURITY mode.
CREATE OR REPLACE FUNCTION atlas.capture_deferred_task_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_payload jsonb;
begin
  if coalesce(new.metadata->>'release_deferred','false')<>'true' then
    return null;
  end if;

  if coalesce(new.metadata->>'release_duplicate','false')<>'true' then
    v_payload := atlas.capture_task_relation_payload_v1(new.id);
    update atlas.planned_work_occurrences
    set
      relation_payload=case
        when v_payload='{}'::jsonb then relation_payload
        else v_payload
      end,
      updated_at=now()
    where id=new.planned_occurrence_id;
  end if;

  update atlas.workflow_handoffs h
  set
    target_occurrence_id=case
      when h.target_task_id=new.id then new.planned_occurrence_id
      else h.target_occurrence_id
    end,
    target_task_id=case
      when h.target_task_id=new.id then null
      else h.target_task_id
    end,
    source_occurrence_id=case
      when h.source_kind='task' and h.source_id=new.id
        then new.planned_occurrence_id
      else h.source_occurrence_id
    end,
    updated_at=now()
  where h.target_task_id=new.id
     or (h.source_kind='task' and h.source_id=new.id);

  -- The foreign key already sets the retired queue task pointer NULL on DELETE.

  delete from atlas.tasks where id=new.id;
  return null;
end;
$function$
;

-- Existing signed deal_next_paid_work_v1 — same signature, owner, ACL and SECURITY mode.
CREATE OR REPLACE FUNCTION atlas.deal_next_paid_work_v1(p_farm_id uuid, p_membership_id uuid, p_day date DEFAULT NULL::date, p_allow_outdoor boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_membership atlas.farm_memberships%rowtype;
  v_timezone text:='America/Chicago';
  v_today date;
  v_day date;
  v_task_id uuid;
  v_environment text;
  v_project_result jsonb;
begin
  select * into v_membership
  from atlas.farm_memberships
  where id=p_membership_id
    and farm_id=p_farm_id
    and active;

  if v_membership.id is null then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  if auth.uid() is not null
     and v_membership.user_id<>auth.uid()
     and not atlas.is_farm_owner(p_farm_id) then
    raise exception 'Only the member or farm owner may deal this work.' using errcode='42501';
  end if;

  select coalesce(nullif(f.metadata->>'timezone',''),'America/Chicago')
  into v_timezone
  from atlas.farms f
  where f.id=p_farm_id;
  v_today:=(now() at time zone v_timezone)::date;
  v_day:=coalesce(p_day,v_today);

  if v_day is distinct from v_today then
    return jsonb_build_object(
      'contractVersion','paid_work_conveyor_v1',
      'state','future_plan_only',
      'serviceDate',v_day,
      'taskId',null
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_farm_id::text||'|'||p_membership_id::text||'|'||v_day::text||'|paid_work_conveyor',0
  ));

  select task.id into v_task_id
  from atlas.project_pull_selections selection
  join atlas.tasks task on task.id=selection.task_id
  where selection.farm_id=p_farm_id
    and selection.membership_id=p_membership_id
    and selection.service_date=v_day
    and selection.state='selected'
    and task.status='open'
  order by selection.selected_at,selection.id
  limit 1;

  if v_task_id is not null then
    return jsonb_build_object(
      'contractVersion','paid_work_conveyor_v1',
      'state','current_project_serving_exists',
      'serviceDate',v_day,
      'taskId',v_task_id,
      'sourceKind','project_pull'
    );
  end if;

  select task.id,
         case
           when lower(coalesce(task.metadata->>'environment','')) in ('indoor','outdoor','either')
             then lower(task.metadata->>'environment')
           when task.operation_class in (
             'establish_aboveground','divide_reestablish_belowground','cultivate_prepare',
             'harvest_collect','irrigate_water','mow_cut','inspect_assess'
           ) and task.task_type not in ('inventory','administrative','network')
             then 'outdoor'
           when lower(coalesce(task.task_type,'')) in ('sowing','transplanting','weeding','mowing','watering','harvest')
             then 'outdoor'
           else 'either'
         end
  into v_task_id,v_environment
  from atlas.worker_week_projection projection
  join atlas.tasks task
    on projection.source_kind='floating_task'
   and task.id=projection.source_id
  join atlas.presented_work_rows_v1(p_farm_id,p_membership_id,v_day) presented
    on presented.task_id=task.id
   and presented.presentation_state='presented'
  where projection.farm_id=p_farm_id
    and projection.membership_id=p_membership_id
    and projection.planned_date=v_day
    and task.status='open'
    and task.due_date is null
    and (p_allow_outdoor or (
      case
        when lower(coalesce(task.metadata->>'environment','')) in ('indoor','outdoor','either')
          then lower(task.metadata->>'environment')
        when task.operation_class in (
          'establish_aboveground','divide_reestablish_belowground','cultivate_prepare',
          'harvest_collect','irrigate_water','mow_cut','inspect_assess'
        ) and task.task_type not in ('inventory','administrative','network')
          then 'outdoor'
        when lower(coalesce(task.task_type,'')) in ('sowing','transplanting','weeding','mowing','watering','harvest')
          then 'outdoor'
        else 'either'
      end
    )<>'outdoor')
  order by projection.plan_order,projection.created_at,projection.id
  limit 1;

  if v_task_id is not null then
    return jsonb_build_object(
      'contractVersion','paid_work_conveyor_v1',
      'state','current_floating_serving_exists',
      'serviceDate',v_day,
      'taskId',v_task_id,
      'sourceKind','floating_task',
      'environment',v_environment
    );
  end if;

  select task.id,
         case
           when lower(coalesce(task.metadata->>'environment','')) in ('indoor','outdoor','either')
             then lower(task.metadata->>'environment')
           when task.operation_class in (
             'establish_aboveground','divide_reestablish_belowground','cultivate_prepare',
             'harvest_collect','irrigate_water','mow_cut','inspect_assess'
           ) and task.task_type not in ('inventory','administrative','network')
             then 'outdoor'
           when lower(coalesce(task.task_type,'')) in ('sowing','transplanting','weeding','mowing','watering','harvest')
             then 'outdoor'
           else 'either'
         end
  into v_task_id,v_environment
  from atlas.presented_work_rows_v1(p_farm_id,p_membership_id,v_day) presented
  join atlas.tasks task on task.id=presented.task_id
  where presented.presentation_state='presented'
    and task.status='open'
    and task.due_date is null
    and task.assigned_membership_id=p_membership_id
    and task.task_scope='farm_operation'
    and task.parent_task_id is null
    and nullif(task.metadata->>'project_pull_item_id','') is null
    and task.work_lane='discretionary'
    and task.commitment_kind='floating'
    and coalesce((task.metadata->>'personal_task')::boolean,false)=false
    and lower(coalesce(task.metadata->>'paid_work','true')) not in ('false','no','0')
    and not (coalesce(task.metadata,'{}'::jsonb) ? 'release_queue_key')
    and (p_allow_outdoor or (
      case
        when lower(coalesce(task.metadata->>'environment','')) in ('indoor','outdoor','either')
          then lower(task.metadata->>'environment')
        when task.operation_class in (
          'establish_aboveground','divide_reestablish_belowground','cultivate_prepare',
          'harvest_collect','irrigate_water','mow_cut','inspect_assess'
        ) and task.task_type not in ('inventory','administrative','network')
          then 'outdoor'
        when lower(coalesce(task.task_type,'')) in ('sowing','transplanting','weeding','mowing','watering','harvest')
          then 'outdoor'
        else 'either'
      end
    )<>'outdoor')
  order by presented.lane_order,presented.selection_rank,task.created_at,task.id
  limit 1;

  if v_task_id is not null then
    insert into atlas.worker_week_projection(
      farm_id,membership_id,planned_date,source_kind,source_id,title,plan_state,environment,expected_active_minutes,reason,plan_order
    )
    select
      p_farm_id,p_membership_id,v_day,'floating_task',task.id,task.title,
      case when v_environment='outdoor' then 'flexible' else 'planned' end,
      v_environment,capacity.expected_active_minutes,
      'Same-day general paid-work reservoir serving · existing undated Atlas task · task date remains unchanged',
      coalesce((select max(plan_order)+1 from atlas.worker_week_projection where farm_id=p_farm_id and membership_id=p_membership_id and planned_date=v_day),700)
    from atlas.tasks task
    cross join lateral atlas.task_capacity_plan_v1(task,v_day) capacity
    where task.id=v_task_id
    on conflict do nothing;

    return jsonb_build_object(
      'contractVersion','paid_work_conveyor_v1',
      'state','adopted_floating_serving',
      'serviceDate',v_day,
      'taskId',v_task_id,
      'sourceKind','floating_task',
      'environment',v_environment
    );
  end if;

  v_project_result:=atlas.deal_next_paid_project_work_v1(
    p_farm_id,p_membership_id,v_day,p_allow_outdoor
  );

  return jsonb_build_object(
    'contractVersion','paid_work_conveyor_v1',
    'state',coalesce(v_project_result->>'state','no_fitting_paid_work'),
    'serviceDate',v_day,
    'taskId',v_project_result->>'taskId',
    'sourceKind',case when v_project_result->>'taskId' is not null then 'project_pull' else null end,
    'delegate',v_project_result
  );
end;
$function$
;

-- Existing signed defer_existing_task_to_occurrence_v1 — same signature, owner, ACL and SECURITY mode.
CREATE OR REPLACE FUNCTION atlas.defer_existing_task_to_occurrence_v1(p_task_id uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare t atlas.tasks%rowtype; o atlas.planned_work_occurrences%rowtype; p atlas.work_release_policies%rowtype; v_history boolean; v_relation jsonb;
begin
 select * into t from atlas.tasks where id=p_task_id for update; if t.id is null or t.status not in ('open','blocked') then return 'skipped'; end if; select * into o from atlas.planned_work_occurrences where id=t.planned_occurrence_id for update; select * into p from atlas.work_release_policies where id=t.release_policy_id; if o.id is null or p.id is null then raise exception 'Task % is missing its release gate.',p_task_id using errcode='23514'; end if;
 v_relation:=atlas.capture_task_relation_payload_v1(t.id); v_history:=atlas.task_has_authoritative_history_v1(t.id);
 update atlas.planned_work_occurrences set state='planned',gate_satisfied_at=null,released_at=null,released_task_id=null,not_before_date=case when t.due_date is null then not_before_date else t.due_date-p.horizon_days end,task_payload=(to_jsonb(t)-'id'-'created_at'-'updated_at'-'planned_occurrence_id'-'release_policy_id'-'released_at'-'release_reason')||jsonb_build_object('status','open','blocker_text',null),relation_payload=case when v_relation='{}'::jsonb then relation_payload else v_relation end,metadata=metadata||jsonb_build_object('migrated_out_of_task_table',true,'migration_reason',p_reason,'migrated_from_task_id',t.id,'migrated_at',now()),updated_at=now() where id=o.id;
 update atlas.workflow_handoffs h set target_occurrence_id=case when h.target_task_id=t.id then o.id else h.target_occurrence_id end,target_task_id=case when h.target_task_id=t.id then null else h.target_task_id end,source_occurrence_id=case when h.source_kind='task' and h.source_id=t.id then o.id else h.source_occurrence_id end,updated_at=now() where h.target_task_id=t.id or (h.source_kind='task' and h.source_id=t.id);
 -- Old queue state is no longer the source of deferral authority.
 if v_history then update atlas.tasks set status='archived',due_date=null,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('archived_reason','Replaced by gated planned occurrence','planned_occurrence_id',o.id,'migration_reason',p_reason,'archived_at',now()),updated_at=now() where id=t.id; return 'archived_history'; end if;
 delete from atlas.tasks where id=t.id; return 'deleted_redundant';
end;$function$
;

-- Existing signed floating_paid_work_candidates_v1 — same signature, owner, ACL and SECURITY mode.
CREATE OR REPLACE FUNCTION atlas.floating_paid_work_candidates_v1(p_farm_id uuid, p_membership_id uuid, p_day date)
 RETURNS TABLE(task_id uuid, title text, expected_active_minutes integer, physical_load text, environment text, priority text, effective_obligation_class text, sky_preference_order integer, obligation_order integer, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
  select
    task.id,
    task.title,
    capacity.expected_active_minutes,
    capacity.physical_load,
    case
      when lower(coalesce(task.metadata->>'environment','')) in ('indoor','outdoor','either')
        then lower(task.metadata->>'environment')
      when task.operation_class in (
        'establish_aboveground','divide_reestablish_belowground','cultivate_prepare',
        'harvest_collect','irrigate_water','mow_cut','inspect_assess'
      ) and task.task_type not in ('inventory','administrative','network')
        then 'outdoor'
      when lower(coalesce(task.task_type,'')) in ('sowing','transplanting','weeding','mowing','watering','harvest')
        then 'outdoor'
      else 'either'
    end as environment,
    task.priority,
    capacity.effective_obligation_class,
    case
      when coalesce(sky.gate->'fitness'->>'enforcementMode','')='preferred'
       and coalesce(sky.gate->'fitness'->>'fitness','')='favored'
      then 0 else 1
    end as sky_preference_order,
    case capacity.effective_obligation_class
      when 'hard_window' then 0
      when 'process_continuation' then 1
      when 'routine_production' then 2
      when 'recovery_work' then 3
      else 4
    end as obligation_order,
    task.created_at
  from atlas.tasks task
  cross join lateral atlas.task_capacity_plan_v1(task,p_day) capacity
  cross join lateral (
    select atlas.task_sky_presentation_gate_v1(task.id,p_day) as gate
  ) sky
  where task.farm_id=p_farm_id
    and task.assigned_membership_id=p_membership_id
    and task.task_scope='farm_operation'
    and task.status='open'
    and task.due_date is null
    and task.parent_task_id is null
    and nullif(task.metadata->>'parent_task_id','') is null
    and lower(coalesce(task.metadata->>'is_child_task','false'))<>'true'
    and nullif(task.metadata->>'project_pull_item_id','') is null
    and coalesce((task.metadata->>'personal_task')::boolean,false)=false
    and lower(coalesce(task.metadata->>'paid_work','true')) not in ('false','no','0')
    and lower(coalesce(task.metadata->>'reservoirDecisionState',''))<>'owner_review'
    and task.work_lane='discretionary'
    and task.commitment_kind='floating'
    and capacity.expected_active_minutes>0
    and atlas.task_prerequisites_ready_v1(task.id)
    and coalesce((sky.gate->>'withheldUnderSky')::boolean,false)=false
    and (
      task.planned_occurrence_id is null
      or exists (
        select 1
        from atlas.planned_work_occurrences occurrence
        where occurrence.id=task.planned_occurrence_id
          and occurrence.state='released'
      )
    )
    and not (coalesce(task.metadata,'{}'::jsonb) ? 'release_queue_key');
$function$
;

-- Existing signed worker_future_day_projection_source_v1 — same signature, owner, ACL and SECURITY mode.
CREATE OR REPLACE FUNCTION atlas.worker_future_day_projection_source_v1(p_farm_id uuid, p_membership_id uuid, p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_paid_target integer;
begin
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from atlas.farm_memberships fm
    where fm.user_id = v_user_id
      and fm.farm_id = p_farm_id
      and fm.active = true
  ) then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  select fm.role
    into v_role
  from atlas.farm_memberships fm
  where fm.id = p_membership_id
    and fm.farm_id = p_farm_id
    and fm.active = true
  limit 1;

  if v_role is null then
    raise exception 'Target membership is not active for this farm.' using errcode = '42501';
  end if;

  select mcs.regular_target_minutes
    into v_paid_target
  from atlas.member_capacity_settings mcs
  where mcs.farm_id = p_farm_id
    and mcs.membership_id = p_membership_id
    and mcs.active = true
  limit 1;

  v_paid_target := coalesce(
    v_paid_target,
    case
      when v_role = 'farm_hand' then 420
      when v_role = 'manager' then 360
      else 480
    end
  );

  return jsonb_build_object(
    'role', v_role,
    'paidTargetMinutes', v_paid_target,
    'projection', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', o.id,
          'plannedDate', o.planned_date,
          'sourceKind', o.source_kind,
          'sourceId', o.source_id,
          'title', o.title,
          'planState', o.plan_state,
          'environment', o.environment,
          'expectedActiveMinutes', o.expected_active_minutes,
          'reason', o.reason,
          'planOrder', o.plan_order
        )
        order by o.planned_date, o.plan_order, o.id
      )
      from atlas.worker_week_projection o
      where o.farm_id = p_farm_id
        and o.membership_id = p_membership_id
        and o.planned_date between p_start_date and p_end_date
    ), '[]'::jsonb),
    'weedQueue', '[]'::jsonb
  );
end;
$function$
;

DO $atlas_consumer_source_postcheck$
DECLARE previous record; actual record;
BEGIN
 FOR previous IN SELECT * FROM atlas_retire_queue_consumer_before LOOP
  SELECT oid,proowner,proacl,prosecdef,proconfig
  INTO actual
  FROM pg_proc WHERE oid=previous.oid;
  IF actual.oid IS NULL
    OR actual.proowner IS DISTINCT FROM previous.proowner
    OR actual.proacl IS DISTINCT FROM previous.proacl
    OR actual.prosecdef IS DISTINCT FROM previous.prosecdef
    OR actual.proconfig IS DISTINCT FROM previous.proconfig
    OR strpos(lower(pg_get_functiondef(previous.oid)),'task_release_queue_items')>0 THEN
     RAISE EXCEPTION 'Live function identity, ACL, SECURITY or queue decoupling changed for %',previous.proname;
  END IF;
 END LOOP;
 IF (SELECT count(*)::text FROM atlas.task_release_queue_items) IS DISTINCT FROM current_setting('atlas.pre_queue_count',true)
    OR (SELECT count(*)::text FROM atlas.work_items) IS DISTINCT FROM current_setting('atlas.pre_work_count',true)
    OR (SELECT count(*)::text FROM atlas.work_requirements) IS DISTINCT FROM current_setting('atlas.pre_requirement_count',true)
    OR (SELECT count(*)::text FROM atlas.tasks) IS DISTINCT FROM current_setting('atlas.pre_task_count',true) THEN
   RAISE EXCEPTION 'Canonical source/history count changed during source-only consumer retirement';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='atlas.flower_harvest_bucket_observations'::regclass AND tgname='flower_harvest_bucket_observations_queue_preparation_v1' AND NOT tgisinternal) THEN
   RAISE EXCEPTION 'Real harvest preparation consequence missing';
 END IF;
END $atlas_consumer_source_postcheck$;
COMMIT;
