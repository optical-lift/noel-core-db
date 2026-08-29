create or replace function atlas.ensure_production_succession_sow_occurrence_v1(
  p_succession_id uuid,
  p_assigned_membership_id uuid default null,
  p_worker_key text default null
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_s atlas.production_successions%rowtype;
  v_plan atlas.production_plans%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_org uuid;
  v_title text;
  v_metadata jsonb;
  v_authored jsonb;
  v_task_id uuid;
  v_today date:=(now() at time zone 'America/Chicago')::date;
begin
  select * into v_s from atlas.production_successions where id=p_succession_id for update;
  if v_s.id is null then raise exception 'Production succession was not found.' using errcode='P0002'; end if;
  select * into v_plan from atlas.production_plans where id=v_s.production_plan_id;
  select * into v_profile from atlas.crop_profiles where id=v_plan.crop_profile_id;
  if v_plan.id is null or v_profile.id is null then raise exception 'Production succession is missing plan/profile custody.' using errcode='23514'; end if;

  if v_s.state not in ('upcoming','in_window','late') then
    return v_s.sow_task_id;
  end if;

  if v_plan.missed_strategy='skip' and v_today>v_s.skip_after_date then
    if v_s.sow_occurrence_id is not null then
      update atlas.planned_work_occurrences
      set state=case when state='completed' then state else 'cancelled' end,
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'cancelledBy','production_succession_missed_strategy',
            'cancelledAt',now(),
            'productionSuccessionId',v_s.id,
            'reason','skip_after_date_passed'
          ),updated_at=now()
      where id=v_s.sow_occurrence_id and state not in ('completed','cancelled');
    end if;
    update atlas.production_successions
    set state='skipped',skip_reason='Skipped automatically because the plan uses skip and the succession passed its skip-after date.',updated_at=now()
    where id=v_s.id;
    return null;
  end if;

  select organization_id into v_org from atlas.farms where id=v_plan.farm_id;
  v_title:='Sow '||v_profile.crop_label||' · Succession '||v_s.sequence_number::text||' of '||v_plan.succession_count::text;
  v_metadata:=jsonb_build_object(
    'production_plan_id',v_plan.id,
    'production_succession_id',v_s.id,
    'succession_number',v_s.sequence_number,
    'succession_count',v_plan.succession_count,
    'crop_profile_id',v_profile.id,
    'crop_profile_stable_key',v_profile.stable_key,
    'crop_label',v_profile.crop_label,
    'variety',v_profile.variety,
    'sowing_window_start',v_s.planned_window_start,
    'sowing_window_end',v_s.planned_window_end,
    'late_window_end',v_s.late_window_end,
    'skip_after_date',v_s.skip_after_date,
    'missed_strategy',v_plan.missed_strategy,
    'intended_uses',v_plan.intended_uses,
    'work_route','sow',
    'work_rhythm','Seed Sowing',
    'display_action','Sow',
    'display_subject',v_profile.crop_label||' · Succession '||v_s.sequence_number::text||' of '||v_plan.succession_count::text,
    'detail_heading','Sowing window',
    'detail_lines',jsonb_build_array(coalesce(v_plan.notes,'Production sowing succession.'),v_s.planned_window_start::text||' through '||v_s.planned_window_end::text),
    'location_required',true,
    'assigned_to',p_worker_key
  );

  v_authored:=atlas.author_production_work_occurrence_v1(
    v_plan.farm_id,
    'succession-sowing',
    'production:succession-sowing:'||v_s.id::text,
    v_title,
    v_s.planned_window_start,
    v_s.planned_window_start,
    'production_succession',
    v_s.id,
    'succession_sowing',
    'sow',
    'Seed Starting / Succession',
    'high',
    case when p_assigned_membership_id is null then 'management' else 'assigned_worker' end,
    p_assigned_membership_id,
    null,
    v_org,
    'Operating sowing window: '||v_s.planned_window_start::text||' through '||v_s.planned_window_end::text||'.',
    v_metadata,
    jsonb_build_object(
      'task_objects',jsonb_build_array(),
      'task_crop_cycles',jsonb_build_array(),
      'production_lot_tasks',jsonb_build_array(),
      'task_resource_requirements',jsonb_build_array(),
      'production_harvest_lot_tasks',jsonb_build_array()
    ),
    'process_continuation',
    'dependency',
    case when v_plan.missed_strategy='skip' then v_s.skip_after_date else v_s.late_window_end end,
    jsonb_build_object('kind','sowing_window','effect','A planned production succession remains unsown as its sowing window closes.','missedStrategy',v_plan.missed_strategy),
    true
  );

  v_task_id:=nullif(v_authored->>'taskId','')::uuid;
  update atlas.production_successions
  set sow_occurrence_id=nullif(v_authored->>'occurrenceId','')::uuid,
      sow_task_id=v_task_id,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'sow_occurrence_id',v_authored->>'occurrenceId',
        'sowing_reservoir_contract','production_succession_reservoir_v1'
      ),updated_at=now()
  where id=v_s.id;

  return v_task_id;
end;
$function$;