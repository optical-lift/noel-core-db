do $block$
declare v_def text;
begin
  select pg_get_viewdef('atlas.crop_cycle_yield_forecast'::regclass,true) into v_def;
  v_def:=replace(v_def,
    'cc.sown_date IS NOT NULL OR cc.planted_date IS NOT NULL AS is_in_ground',
    'cc.sown_date IS NOT NULL OR cc.planted_date IS NOT NULL OR cc.coverage_kind = ''plant_count''::text AS is_in_ground'
  );
  execute 'create or replace view atlas.crop_cycle_yield_forecast as '||v_def;
end;
$block$;

with next_harvest as (
  select min(o.planned_due_date) d
  from atlas.planned_work_occurrences o
  where o.farm_id=(select id from atlas.farms where stable_key='elm_farm')
    and o.source_kind='recurring_task'
    and o.occurrence_key like 'recurring:anna_harvest_thursday_weekly:%'
    and o.state in ('planned','eligible','released')
    and o.planned_due_date>=(now() at time zone 'America/Chicago')::date
), instances as (
  select i.id,i.carrier_task_id,coalesce(nh.d,(now() at time zone 'America/Chicago')::date+5) d
  from atlas.state_consequence_instances i
  join atlas.state_consequence_policies p on p.id=i.policy_id
  cross join next_harvest nh
  where i.farm_id=(select id from atlas.farms where stable_key='elm_farm')
    and p.stable_key='crop-stand-count-truth-required-v1' and i.status='open'
)
update atlas.state_consequence_instances i
set requirement_onset_date=x.d,requirement_known_active_by=x.d,requirement_time_class='exact',
    epistemic_basis=coalesce(i.epistemic_basis,'{}'::jsonb)||jsonb_build_object('scheduledWith','next_weekly_harvest','scheduledFor',x.d,'scheduleCorrectedAt',now()),updated_at=now()
from instances x where i.id=x.id;

with next_harvest as (
  select min(o.planned_due_date) d
  from atlas.planned_work_occurrences o
  where o.farm_id=(select id from atlas.farms where stable_key='elm_farm')
    and o.source_kind='recurring_task' and o.occurrence_key like 'recurring:anna_harvest_thursday_weekly:%'
    and o.state in ('planned','eligible','released') and o.planned_due_date>=(now() at time zone 'America/Chicago')::date
), carriers as (
  select i.carrier_task_id,coalesce(nh.d,(now() at time zone 'America/Chicago')::date+5) d
  from atlas.state_consequence_instances i join atlas.state_consequence_policies p on p.id=i.policy_id cross join next_harvest nh
  where i.farm_id=(select id from atlas.farms where stable_key='elm_farm') and p.stable_key='crop-stand-count-truth-required-v1' and i.status='open' and i.carrier_task_id is not null
)
update atlas.tasks t
set due_date=c.d,metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object('truth_observation_schedule','next_weekly_harvest','schedule_corrected_at',now(),'schedule_correction_reason','do not dump newly discovered stand-count gaps into current worker day'),updated_at=now()
from carriers c where t.id=c.carrier_task_id and t.status in ('open','blocked');

with next_harvest as (
  select min(o.planned_due_date) d
  from atlas.planned_work_occurrences o
  where o.farm_id=(select id from atlas.farms where stable_key='elm_farm')
    and o.source_kind='recurring_task' and o.occurrence_key like 'recurring:anna_harvest_thursday_weekly:%'
    and o.state in ('planned','eligible','released') and o.planned_due_date>=(now() at time zone 'America/Chicago')::date
), occurrence_ids as (
  select distinct t.planned_occurrence_id,coalesce(nh.d,(now() at time zone 'America/Chicago')::date+5) d
  from atlas.state_consequence_instances i join atlas.state_consequence_policies p on p.id=i.policy_id
  join atlas.tasks t on t.id=i.carrier_task_id cross join next_harvest nh
  where i.farm_id=(select id from atlas.farms where stable_key='elm_farm') and p.stable_key='crop-stand-count-truth-required-v1' and i.status='open' and t.planned_occurrence_id is not null
)
update atlas.planned_work_occurrences o
set planned_due_date=x.d,not_before_date=x.d,metadata=coalesce(o.metadata,'{}'::jsonb)||jsonb_build_object('scheduleCorrectedAt',now(),'scheduleSource','next_weekly_harvest'),updated_at=now()
from occurrence_ids x where o.id=x.planned_occurrence_id and o.state in ('planned','eligible','released');