insert into atlas.crop_observation_types(observation_key,label,mapped_event_type,mapped_cycle_state,lifecycle_effect,decision_required,sort_order,active,metadata)
values('stand_count','Stand count','observed',null,'none',false,85,true,jsonb_build_object(
  'quantity_required',true,'allowed_units',jsonb_build_array('plants'),'truth_role','current_living_plant_count',
  'yield_rebase',true,'portable',true
))
on conflict(observation_key) do update set label=excluded.label,mapped_event_type=excluded.mapped_event_type,mapped_cycle_state=excluded.mapped_cycle_state,lifecycle_effect=excluded.lifecycle_effect,decision_required=excluded.decision_required,sort_order=excluded.sort_order,active=true,metadata=atlas.crop_observation_types.metadata||excluded.metadata,updated_at=now();

create or replace function atlas.apply_crop_stand_count_observation_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_key text;
  v_stems_per_plant numeric;
  v_estimated_remaining integer;
begin
  v_key:=new.metadata->'state'->>'crop_observation_key';
  if v_key is distinct from 'stand_count' or new.crop_cycle_id is null then return new; end if;
  if new.quantity is null or lower(coalesce(new.unit,'')) not in ('plant','plants') then
    raise exception 'Stand-count observations require a nonnegative plant quantity with unit plants.' using errcode='22023';
  end if;

  select coalesce(cp.expected_stems_per_plant,1::numeric) into v_stems_per_plant
  from atlas.crop_cycles cc left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
  where cc.id=new.crop_cycle_id;
  v_stems_per_plant:=coalesce(v_stems_per_plant,1::numeric);
  v_estimated_remaining:=greatest(0,floor(new.quantity*v_stems_per_plant)::integer);

  update atlas.crop_cycles
  set coverage_kind='plant_count',coverage_amount=new.quantity,coverage_unit='plants',
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'current_living_plant_count',new.quantity,'stand_count_observed_date',new.event_date,
        'stand_count_event_id',new.id,'stand_count_expected_stems_per_plant',v_stems_per_plant,
        'stand_count_estimated_remaining_stems',v_estimated_remaining,'stand_count_source','canonical_crop_observation'
      ),updated_at=now()
  where id=new.crop_cycle_id;

  insert into atlas.crop_cycle_impacts(
    farm_id,crop_cycle_id,object_id,observed_date,impact_type,severity,viability_state,
    estimated_remaining_stems,confidence,note,source,metadata
  ) values(
    new.farm_id,new.crop_cycle_id,new.object_id,new.event_date,'other','trace','unknown',
    v_estimated_remaining,'confirmed','Current living plant count rebased the remaining-stem forecast.','truth_acquisition_stand_count',
    jsonb_build_object('standCount',new.quantity,'unit','plants','expectedStemsPerPlant',v_stems_per_plant,'sourceEventId',new.id,'forecastRebase',true)
  );
  return new;
end;
$function$;

drop trigger if exists trg_apply_crop_stand_count_observation_v1 on atlas.object_activity_events;
create trigger trg_apply_crop_stand_count_observation_v1
after insert on atlas.object_activity_events
for each row execute function atlas.apply_crop_stand_count_observation_v1();

do $block$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='ensure_truth_acquisition_worker_observation_v1' and p.prokind='f' limit 1;
  if v_def is null then raise exception 'Truth-acquisition worker observation carrier not found'; end if;
  v_def:=replace(
    v_def,
    'v_due:=coalesce(v_requirement.requirement_known_active_by,v_requirement.requirement_onset_date,(now() at time zone ''America/Chicago'')::date);',
    'v_due:=coalesce(v_requirement.requirement_known_active_by,v_requirement.requirement_onset_date,v_instance.requirement_known_active_by,v_instance.requirement_onset_date,(now() at time zone ''America/Chicago'')::date);'
  );
  execute v_def;
end;
$block$;

insert into atlas.state_consequence_policies(
  farm_id,stable_key,subject_kind,subject_selector,state_match,consequence_kind,action_key,audience,priority,action_spec,active,metadata
) values(
  null,'crop-stand-count-truth-required-v1','crop_cycle',
  jsonb_build_object('scope','active crop cycles whose remaining yield cannot be quantified from recorded geometry or stand truth'),
  jsonb_build_object('remaining_expected_stems','unknown'),
  'knowledge_acquisition','measure_stand_count','farm_operations',65,
  jsonb_build_object(
    'state','truth_acquisition_required','action','measure_stand_count','factNeeded','current living plant count for this crop stand',
    'actionLabel','Count living plants','jurisdiction','farm_hand','blocksExecution',false,'doesNotInventCoverage',true
  ),true,
  jsonb_build_object(
    'gapKind','crop_stand_quantity_required','contract','crop_stand_count_truth_acquisition_v1','consequenceRole','truth_acquisition',
    'knowerClass','worker_observable','workerObservationAdapter','crop_observation_v1','searchAdapter','crop_latest_observation_v1',
    'workerObservationKey','stand_count','workerObservationPrompt','Count the living plants of this crop in this bed',
    'canonicalWriter','record_crop_observation_for_member_v1','portable',true
  )
)
on conflict(stable_key) do update set subject_kind=excluded.subject_kind,subject_selector=excluded.subject_selector,state_match=excluded.state_match,
consequence_kind=excluded.consequence_kind,action_key=excluded.action_key,audience=excluded.audience,priority=excluded.priority,action_spec=excluded.action_spec,active=true,
metadata=atlas.state_consequence_policies.metadata||excluded.metadata,updated_at=now();

with farm as (select id from atlas.farms where stable_key='elm_farm' limit 1), policy as (
  select id,stable_key,action_spec,metadata from atlas.state_consequence_policies where stable_key='crop-stand-count-truth-required-v1'
), next_harvest as (
  select min(o.planned_due_date) d from atlas.planned_work_occurrences o,farm f
  where o.farm_id=f.id and o.source_kind='recurring_task' and o.occurrence_key like 'recurring:anna_harvest_thursday_weekly:%'
    and o.state='planned' and o.planned_due_date>=(now() at time zone 'America/Chicago')::date
), candidates as (
  select cc.id crop_cycle_id,cc.farm_id,cc.object_id,go.label object_label,cc.crop_label,cc.variety,p.id policy_id,p.stable_key policy_key,p.action_spec,p.metadata policy_metadata,nh.d due_date
  from atlas.crop_cycles cc
  join farm f on f.id=cc.farm_id
  join atlas.crop_profiles cp on cp.id=cc.crop_profile_id
  join atlas.growing_objects go on go.id=cc.object_id
  left join atlas.crop_cycle_yield_forecast yf on yf.crop_cycle_id=cc.id
  cross join policy p cross join next_harvest nh
  where cc.lifecycle_status='active' and coalesce(cp.metadata->'use_tags','[]'::jsonb)?'cut_flower'
    and yf.remaining_expected_stems is null
)
insert into atlas.state_consequence_instances(
  farm_id,policy_id,subject_kind,subject_id,consequence_key,consequence_kind,action_key,audience,priority,status,release_generation,
  state_fingerprint,state_snapshot,consequence_payload,requirement_onset_date,requirement_known_active_by,requirement_time_class,epistemic_basis,consequence_role
)
select c.farm_id,c.policy_id,'crop_cycle',c.crop_cycle_id,'crop-stand-count-truth-required:'||c.crop_cycle_id::text,'knowledge_acquisition','measure_stand_count','farm_operations',65,'open',1,
  md5('crop-stand-count:'||c.crop_cycle_id::text),
  jsonb_build_object('objectId',c.object_id,'objectLabel',c.object_label,'cropLabel',c.crop_label,'variety',c.variety,'remainingExpectedStems',null),
  jsonb_build_object('audience','farm_operations','priority',65,'actionKey','measure_stand_count','policyKey',c.policy_key,'actionSpec',c.action_spec,'policyMetadata',c.policy_metadata,'consequenceKind','knowledge_acquisition'),
  c.due_date,c.due_date,'exact',jsonb_build_object('knowerClass','actually_unknown','acquisitionSurface','worker_observation','reason','mixed-bed crop quantity is not derivable from current geometry'),
  'truth_acquisition'
from candidates c
on conflict(policy_id,subject_kind,subject_id) do update set
  status=case when atlas.state_consequence_instances.status='resolved' then 'resolved' else 'open' end,
  requirement_onset_date=excluded.requirement_onset_date,requirement_known_active_by=excluded.requirement_known_active_by,
  state_snapshot=excluded.state_snapshot,consequence_payload=excluded.consequence_payload,epistemic_basis=atlas.state_consequence_instances.epistemic_basis||excluded.epistemic_basis,
  updated_at=now();

do $block$
declare r record;
begin
  for r in
    select i.id from atlas.state_consequence_instances i
    join atlas.state_consequence_policies p on p.id=i.policy_id
    where i.farm_id=(select id from atlas.farms where stable_key='elm_farm')
      and p.stable_key='crop-stand-count-truth-required-v1' and i.status='open'
  loop
    perform atlas.ensure_truth_acquisition_worker_observation_v1(r.id);
  end loop;
end;
$block$;

with farm as (select id from atlas.farms where stable_key='elm_farm' limit 1), inv as (
  select cc.object_id,string_agg(distinct cc.crop_label||coalesce(' · '||nullif(cc.variety,''),'') ,'; ' order by cc.crop_label||coalesce(' · '||nullif(cc.variety,''),'')) inventory
  from atlas.crop_cycles cc join farm f on f.id=cc.farm_id
  where cc.lifecycle_status='active' and cc.cleared_date is null
  group by cc.object_id
)
update atlas.object_state os
set decision_required=false,
    operational_truth='Occupied: '||coalesce(inv.inventory,'active crop stand')||'. Aug. 8 deer-damage evidence is preserved historically; current productive condition is routed through scheduled Harvest observations rather than an owner decision.',
    operational_truth_source='harvest_observation_route_20260829',operational_truth_changed_at=now(),
    metadata=coalesce(os.metadata,'{}'::jsonb)||jsonb_build_object(
      'decision_reconciled_on','2026-08-29','decision_reconciled_reason','physical crop condition is worker-observable through recurring Harvest, not an owner decision',
      'historical_deer_damage_preserved',true,'physical_recheck_route','anna_harvest_thursday_weekly'
    ),updated_at=now()
from atlas.growing_objects go left join inv on inv.object_id=go.id
where os.object_id=go.id and go.farm_id=(select id from farm)
  and go.stable_key in ('bw_1','bw_4','bw_7','bw_8','bw_10');