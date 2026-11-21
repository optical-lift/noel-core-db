-- HELD P3 / Nov 4 decision 6A: legacy tasks Done cannot release new
-- task/occurrence/Work. Preserve signed Done, existing terminal status,
-- requirement-boundary evidence and legitimate historical records.
-- Exact live PG17 function snapshots from 2026-11-06; NOT a migration,
-- tests, or production authorization.
BEGIN;
DO $source_hold$
DECLARE v_name text;v_digest text;v_expected text;
BEGIN
 FOR v_name,v_expected IN SELECT * FROM (VALUES
  ('advance_anna_weeding_serial_queue_v1','3e19f0db48bb781ee09c28b120e39bf9'),
  ('advance_gentle_pressure_wash_serial_queue_v1','a1e91245470dc25a831f4cdd36f37ae6'),
  ('advance_owner_completion_gated_queue_v1','2d4c93888e82f00f3a1af150827d1bcc'),
  ('advance_pot_up_serial_queue_v1','b9e2f2f8c3fb494d5cea9325b182eefc'),
  ('release_after_task_terminal_v1','4223cee690c2fde4f033c45dbca74815')
 ) AS expected(name,digest)
 LOOP
  SELECT pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
    INTO v_digest
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='atlas' AND p.proname=v_name
    AND pg_catalog.pg_get_function_identity_arguments(p.oid)='';
  IF v_digest IS DISTINCT FROM v_expected
  THEN
   RAISE EXCEPTION 'P3 legacy Done-trace source mismatch: %',v_name
     USING ERRCODE='42501';
  END IF;
 END LOOP;
END;
$source_hold$;

-- Exact previously-live advance_anna_weeding_serial_queue_v1 function source MD5 3e19f0db48bb781ee09c28b120e39bf9.
-- Only the subsequent release side effect is removed; boundary/Done remains.
CREATE OR REPLACE FUNCTION atlas.advance_anna_weeding_serial_queue_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_queue_key constant text := 'anna_weeding_rotation';
  v_worker_key text;
  v_item atlas.task_release_queue_items%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_boundary_id uuid;
  v_evaluated_at timestamptz;
  v_completed_date date;
begin
  if new.status <> 'done' or old.status='done' then return new; end if;
  if lower(coalesce(new.metadata->>'weed_serial_gate','false')) not in ('true','yes','1') then return new; end if;

  select fm.worker_key into v_worker_key
  from atlas.farm_memberships fm
  where fm.id=new.assigned_membership_id;
  if v_worker_key is distinct from 'anna' then return new; end if;

  select qi.* into v_item
  from atlas.task_release_queue_items qi
  where qi.farm_id=new.farm_id
    and qi.queue_key=v_queue_key
    and qi.task_id=new.id
    and qi.state='active'
  for update;

  if not found then return new; end if;

  v_evaluated_at:=coalesce(new.completed_at,new.updated_at,now());

  v_before:=atlas.requirement_set_evaluate_v1(jsonb_build_array(jsonb_build_object(
    'requirementKey','predecessor_task_completed',
    'satisfied',old.status='done',
    'provider','atlas.tasks.status',
    'providerState',old.status,
    'evidence',jsonb_build_object('taskId',old.id,'status',old.status,'completedAt',old.completed_at)
  )));

  v_after:=atlas.requirement_set_evaluate_v1(jsonb_build_array(jsonb_build_object(
    'requirementKey','predecessor_task_completed',
    'satisfied',new.status='done',
    'provider','atlas.tasks.status',
    'providerState',new.status,
    'evidence',jsonb_build_object('taskId',new.id,'status',new.status,'completedAt',new.completed_at)
  )));

  v_boundary_id:=atlas.record_requirement_boundary_v1(
    'task_release_queue_item',
    v_item.id,
    'anna_weeding_predecessor_completion_v1',
    'anna-weeding:'||v_item.id::text||':predecessor-completed',
    v_before,
    v_after,
    v_evaluated_at,
    'task',
    new.id,
    jsonb_build_object(
      'queueKey',v_queue_key,
      'effectConsumer','independent_governed_issuance_required_v1',
      'legacyEffectSuppressed','apply_anna_weeding_serial_release_effect_v1',
      'newWorkReleased',false
    )
  );

  if v_boundary_id is null then
    raise exception 'Anna weeding predecessor completion did not cross an open-to-satisfied boundary.' using errcode='23514';
  end if;

  v_completed_date:=(v_evaluated_at at time zone 'America/Chicago')::date;
  NULL; /* 6A: preserve completion/boundary; later Work requires independent source. */
  return new;
end;
$function$

-- Exact previously-live advance_gentle_pressure_wash_serial_queue_v1 function source MD5 a1e91245470dc25a831f4cdd36f37ae6.
-- Only the subsequent release side effect is removed; boundary/Done remains.
CREATE OR REPLACE FUNCTION atlas.advance_gentle_pressure_wash_serial_queue_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_item atlas.task_release_queue_items%rowtype;
  v_completed_date date;
begin
  if new.status<>'done' or old.status='done' then
    return new;
  end if;

  select item.* into v_item
  from atlas.task_release_queue_items item
  where item.task_id=new.id
    and item.state='active'
    and item.queue_key='anna_gentle_pressure_wash_aug_2026'
  for update;

  if v_item.id is null then
    return new;
  end if;

  update atlas.task_release_queue_items
  set state='completed',
      completed_at=coalesce(new.completed_at,now()),
      updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'completed_task_id',new.id,
        'completed_at',coalesce(new.completed_at,now()),
        'completion_gate_advanced',false,
        'independent_issuance_required',true
      )
  where id=v_item.id;

  v_completed_date := (coalesce(new.completed_at,now()) at time zone 'America/Chicago')::date;
  NULL; /* 6A: preserve completion/boundary; later Work requires independent source. */
  return new;
end;
$function$

-- Exact previously-live advance_owner_completion_gated_queue_v1 function source MD5 2d4c93888e82f00f3a1af150827d1bcc.
-- Only the subsequent release side effect is removed; boundary/Done remains.
CREATE OR REPLACE FUNCTION atlas.advance_owner_completion_gated_queue_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_item atlas.task_release_queue_items%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_boundary_id uuid;
  v_evaluated_at timestamptz;
  v_completed_date date;
begin
  if new.status <> 'done' or old.status = 'done' then
    return new;
  end if;

  select qi.* into v_item
  from atlas.task_release_queue_items qi
  where qi.task_id=new.id
    and qi.state='active'
    and qi.queue_key in ('owner_social_content_queue','owner_venue_marketing_queue')
  for update;

  if not found then
    return new;
  end if;

  v_evaluated_at:=coalesce(new.completed_at,new.updated_at,now());

  v_before:=atlas.requirement_set_evaluate_v1(jsonb_build_array(jsonb_build_object(
    'requirementKey','predecessor_task_completed',
    'satisfied',old.status='done',
    'provider','atlas.tasks.status',
    'providerState',old.status,
    'evidence',jsonb_build_object('taskId',old.id,'status',old.status,'completedAt',old.completed_at)
  )));

  v_after:=atlas.requirement_set_evaluate_v1(jsonb_build_array(jsonb_build_object(
    'requirementKey','predecessor_task_completed',
    'satisfied',new.status='done',
    'provider','atlas.tasks.status',
    'providerState',new.status,
    'evidence',jsonb_build_object('taskId',new.id,'status',new.status,'completedAt',new.completed_at)
  )));

  v_boundary_id:=atlas.record_requirement_boundary_v1(
    'task_release_queue_item',
    v_item.id,
    'owner_completion_gated_predecessor_completion_v1',
    'owner-completion-gated:'||v_item.id::text||':predecessor-completed',
    v_before,
    v_after,
    v_evaluated_at,
    'task',
    new.id,
    jsonb_build_object(
      'queueKey',v_item.queue_key,
      'effectConsumer','independent_governed_issuance_required_v1',
      'legacyEffectSuppressed','apply_owner_completion_gated_release_effect_v1',
      'newWorkReleased',false
    )
  );

  if v_boundary_id is null then
    raise exception 'Owner completion-gated predecessor completion did not cross an open-to-satisfied boundary.' using errcode='23514';
  end if;

  v_completed_date:=(v_evaluated_at at time zone 'America/Chicago')::date;
  NULL; /* 6A: preserve completion/boundary; later Work requires independent source. */

  return new;
end;
$function$

-- Exact previously-live advance_pot_up_serial_queue_v1 function source MD5 b9e2f2f8c3fb494d5cea9325b182eefc.
-- Only the subsequent release side effect is removed; boundary/Done remains.
CREATE OR REPLACE FUNCTION atlas.advance_pot_up_serial_queue_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_item atlas.task_release_queue_items%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_boundary_id uuid;
  v_evaluated_at timestamptz;
  v_completed_date date;
begin
  if new.status<>'done' or old.status='done' then
    return new;
  end if;

  select qi.* into v_item
  from atlas.task_release_queue_items qi
  where qi.task_id=new.id
    and qi.state='active'
    and coalesce(qi.metadata->>'queue_kind','')='pot_up_serial'
  for update;

  if not found then
    return new;
  end if;

  v_evaluated_at:=coalesce(new.completed_at,new.updated_at,now());

  v_before:=atlas.requirement_set_evaluate_v1(jsonb_build_array(jsonb_build_object(
    'requirementKey','predecessor_task_completed',
    'satisfied',old.status='done',
    'provider','atlas.tasks.status',
    'providerState',old.status,
    'evidence',jsonb_build_object('taskId',old.id,'status',old.status,'completedAt',old.completed_at)
  )));

  v_after:=atlas.requirement_set_evaluate_v1(jsonb_build_array(jsonb_build_object(
    'requirementKey','predecessor_task_completed',
    'satisfied',new.status='done',
    'provider','atlas.tasks.status',
    'providerState',new.status,
    'evidence',jsonb_build_object('taskId',new.id,'status',new.status,'completedAt',new.completed_at)
  )));

  v_boundary_id:=atlas.record_requirement_boundary_v1(
    'task_release_queue_item',
    v_item.id,
    'pot_up_serial_predecessor_completion_v1',
    'pot-up-serial:'||v_item.id::text||':predecessor-completed',
    v_before,
    v_after,
    v_evaluated_at,
    'task',
    new.id,
    jsonb_build_object(
      'queueKey',v_item.queue_key,
      'queueKind','pot_up_serial',
      'effectConsumer','independent_governed_issuance_required_v1',
      'legacyEffectSuppressed','apply_pot_up_serial_release_effect_v1',
      'newWorkReleased',false
    )
  );

  if v_boundary_id is null then
    raise exception 'Pot-up predecessor completion did not cross an open-to-satisfied boundary.' using errcode='23514';
  end if;

  v_completed_date:=(v_evaluated_at at time zone 'America/Chicago')::date;
  NULL; /* 6A: preserve completion/boundary; later Work requires independent source. */

  return new;
end;
$function$

-- Exact previously-live release_after_task_terminal_v1 function source MD5 4223cee690c2fde4f033c45dbca74815.
-- Only the subsequent release side effect is removed; boundary/Done remains.
CREATE OR REPLACE FUNCTION atlas.release_after_task_terminal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_company_work_managed boolean:=false;
begin
  if current_setting('atlas.reservoir_migration',true)='on' then return new; end if;
  if current_setting('atlas.release_engine_active',true)='on' then return new; end if;

  if old.status in ('open','blocked') and new.status in ('done','archived','skipped') then
    select exists(
      select 1
      from atlas.work_execution_adapters a
      join atlas.work_items wi
        on wi.organization_id=a.organization_id
       and wi.id=a.work_item_id
      where a.task_id=new.id
        and a.state in ('active','completed','retired')
        and coalesce(wi.metadata->>'managerSchedulingAuthority','')='work_execution_plans'
    ) into v_company_work_managed;

    if new.planned_occurrence_id is not null then
      update atlas.planned_work_occurrences child
      set state=case when new.status='done' then 'completed' else 'cancelled' end,
          updated_at=now(),metadata=child.metadata || jsonb_build_object(
            'closed_with_parent_task_id',new.id,'closed_with_parent_status',new.status,'closed_at',now())
      where child.parent_occurrence_id=new.planned_occurrence_id and child.state in ('planned','eligible','failed');

      update atlas.planned_work_occurrences
      set state=case when new.status='done' then 'completed' else 'cancelled' end,
          updated_at=now(),metadata=metadata || jsonb_build_object(
            'terminal_task_status',new.status,'terminal_task_id',new.id,'terminal_at',now())
      where id=new.planned_occurrence_id;
    end if;

    -- Manager-scheduled Company Work has its own planning/release authority.
    -- Finishing one of these carriers must not invoke the unrelated legacy
    -- farm-wide release sweep; that sweep may still serve legacy farm work.
    if not v_company_work_managed then
      NULL; /* 6A: preserve completion/boundary; later Work requires independent source. */
    end if;
  end if;
  return new;
end;
$function$
COMMIT;
