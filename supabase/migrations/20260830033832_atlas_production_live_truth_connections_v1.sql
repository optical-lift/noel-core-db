create or replace function atlas.sync_production_bed_preparation_tasks_v1(p_program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_program atlas.production_programs%rowtype;
  v_assignment record;
  v_anna uuid;
  v_worker_key text;
  v_next jsonb;
  v_occurrence_id uuid;
  v_task_id uuid;
  v_authored integer:=0;
  v_materialized integer:=0;
  v_title text;
  v_metadata jsonb;
  v_org uuid;
begin
  select * into v_program from atlas.production_programs where id=p_program_id;
  if v_program.id is null then raise exception 'Production program not found' using errcode='P0002'; end if;
  select organization_id into v_org from atlas.farms where id=v_program.farm_id;
  select fm.id,fm.worker_key into v_anna,v_worker_key
  from atlas.farm_memberships fm
  where fm.farm_id=v_program.farm_id and fm.active and fm.worker_key='anna'
  order by fm.created_at limit 1;

  for v_assignment in
    select a.id assignment_id,a.production_lot_id,a.object_id,a.quantity_assigned,a.planned_transplant_date,
           req.preparation_due_date,pl.stable_key production_lot_key,pl.lot_label,go.label object_label,go.zone_id
    from atlas.production_bed_assignments a
    join atlas.production_lots pl on pl.id=a.production_lot_id
    join atlas.production_capacity_requirements req on req.id=a.requirement_id
    join atlas.growing_objects go on go.id=a.object_id
    where pl.program_id=p_program_id
      and a.assignment_status='assigned'
      and req.preparation_due_date is not null
    order by req.preparation_due_date,pl.succession_number nulls last,go.sort_order nulls last,go.label
  loop
    v_title:='Prepare '||v_assignment.object_label||' for '||v_assignment.lot_label;
    v_metadata:=jsonb_build_object(
      'task_key','capacity_bed_prep_'||v_assignment.assignment_id::text,
      'anna_task',v_anna is not null,'owner_task',v_anna is null,
      'assigned_to',coalesce(v_worker_key,'Owner'),
      'work_route','prepare','work_rhythm','Bed Preparation','display_action','Prepare bed',
      'display_subject',v_assignment.object_label,
      'display_detail',v_assignment.quantity_assigned::text||' bed-ft for transplant '||v_assignment.planned_transplant_date::text,
      'collection_zone',v_assignment.object_label,'production_program_id',p_program_id,
      'production_lot_id',v_assignment.production_lot_id,'production_lot_key',v_assignment.production_lot_key,
      'production_bed_assignment_id',v_assignment.assignment_id,'destination_object_id',v_assignment.object_id,
      'required_bed_feet',v_assignment.quantity_assigned,'target_transplant_date',v_assignment.planned_transplant_date,
      'relationship_kind','production_capacity_preparation'
    );

    v_next:=atlas.author_production_work_occurrence_v1(
      v_program.farm_id,'bed-preparation','production:bed-preparation:'||v_assignment.assignment_id::text,
      v_title,v_assignment.preparation_due_date,v_assignment.preparation_due_date,
      'production_bed_assignment',v_assignment.assignment_id,'bed_preparation','prepare','standard','high',
      case when v_anna is null then 'owner' else 'assigned_worker' end,v_anna,null,v_org,
      'Weed, clear, prepare, and confirm water access for '||v_assignment.quantity_assigned::text||' bed-feet.',
      v_metadata,
      jsonb_build_object(
        'task_objects',jsonb_build_array(jsonb_build_object('object_id',v_assignment.object_id,'role','target')),
        'task_crop_cycles',jsonb_build_array(),
        'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_assignment.production_lot_id,'link_role','bed_preparation','source','capacity_planner','metadata',jsonb_build_object('production_bed_assignment_id',v_assignment.assignment_id))),
        'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()
      ),
      'process_continuation','dependency',v_assignment.planned_transplant_date,
      jsonb_build_object('kind','destination_preparation','effect','The assigned bed must be prepared before this production lot can pass its transplant gate.'),false
    );
    v_occurrence_id:=nullif(v_next->>'occurrenceId','')::uuid;
    v_task_id:=nullif(v_next->>'taskId','')::uuid;
    v_authored:=v_authored+1;
    if v_task_id is not null then v_materialized:=v_materialized+1; end if;
    update atlas.production_bed_assignments
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'bed_preparation_occurrence_id',v_occurrence_id,
      'bed_preparation_task_id',v_task_id,
      'bed_preparation_synced_at',now()
    ),updated_at=now()
    where id=v_assignment.assignment_id;
  end loop;

  return jsonb_build_object('programId',p_program_id,'occurrencesAuthored',v_authored,'tasksMaterialized',v_materialized,'tasksCreated',v_materialized,'tasksUpdated',0);
end;
$function$;

create or replace function atlas.sync_snapdragon_bed_preparation_tasks_v1(p_program_id uuid)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select atlas.sync_production_bed_preparation_tasks_v1(p_program_id);
$function$;

create or replace function atlas.weekly_harvest_task_state_core_v1(p_task_id uuid,p_effective_membership_id uuid,p_effective_role text,p_operator_mode boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_member atlas.farm_memberships%rowtype;
  v_rows jsonb:='[]'::jsonb;
  v_total integer:=0;
  v_resolved integer:=0;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Weekly Harvest task not found.' using errcode='P0002'; end if;
  if v_task.task_type<>'harvest' or v_task.task_series_key<>'anna_harvest_thursday_weekly' then raise exception 'Task is not the canonical weekly Harvest card.' using errcode='22023'; end if;
  select * into v_member from atlas.farm_memberships where id=p_effective_membership_id;
  if v_member.id is null or not v_member.active or v_member.farm_id is distinct from v_task.farm_id then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  if p_effective_role not in ('owner','manager','farm_hand') then raise exception 'Harvest access denied.' using errcode='42501'; end if;
  if p_effective_role='farm_hand' and v_task.assigned_membership_id is distinct from p_effective_membership_id then raise exception 'Weekly Harvest is not assigned to this worker.' using errcode='42501'; end if;

  with current_candidates as (
    select c.*,coalesce(nullif(z.label,''),'Elm Farm') zone_label
    from atlas.weekly_harvest_candidate_cycles_v1(v_task.id)c
    join atlas.growing_objects go on go.id=c.object_id
    left join atlas.zones z on z.id=go.zone_id
  ), historical_results as (
    select cc.id crop_cycle_id,coalesce(nullif(cc.crop_label,''),'Crop') crop_label,nullif(cc.variety,'') variety,
           go.id object_id,coalesce(nullif(go.label,''),'Growing area') object_label,
           cc.expected_harvest_watch_start window_start,coalesce(cc.expected_harvest_watch_end,cc.expected_harvest_watch_start+21) window_end,
           coalesce(nullif(cc.cycle_state,''),'growing') cycle_state,cha.status availability_status,
           coalesce(nullif(z.label,''),'Elm Farm') zone_label
    from atlas.weekly_harvest_task_results wr
    join atlas.crop_cycles cc on cc.id=wr.crop_cycle_id
    join atlas.growing_objects go on go.id=cc.object_id
    left join atlas.zones z on z.id=go.zone_id
    left join atlas.crop_harvest_availability cha on cha.crop_cycle_id=cc.id
    where wr.task_id=v_task.id and wr.result_kind<>'crop_exhausted'
  ), rows_union as (
    select * from current_candidates union select * from historical_results
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'cropCycleId',u.crop_cycle_id,'cropLabel',u.crop_label,'variety',u.variety,
      'zoneLabel',u.zone_label,'objectId',u.object_id,'objectLabel',u.object_label,
      'windowStart',u.window_start,'windowEnd',u.window_end,'cycleState',u.cycle_state,
      'availabilityStatus',u.availability_status,
      'originalPotentialStems',yf.original_potential_stems,
      'knownRemovedStems',yf.known_removed_stems,
      'remainingExpectedStems',yf.remaining_expected_stems,
      'harvestDepletionState',yf.harvest_depletion_state,
      'unresolvedHarvestDepletionEvents',yf.unresolved_harvest_depletion_events,
      'forecastState',yf.forecast_state,
      'forecastQuantityKind',coalesce(cp.metadata->>'forecast_quantity_kind','expected_seasonal_stems'),
      'forecastConfidence',coalesce(cp.metadata->>'forecast_confidence',case when yf.original_potential_stems is null then 'unresolved' else 'profile_based' end),
      'resolved',wr.id is not null,'resultKind',wr.result_kind,'bucketHalves',wr.bucket_halves,'resolvedAt',wr.resolved_at
    )) order by u.zone_label,u.object_label,u.crop_label,u.variety,u.crop_cycle_id),'[]'::jsonb),
    count(*)::integer,count(wr.id)::integer
  into v_rows,v_total,v_resolved
  from rows_union u
  left join atlas.weekly_harvest_task_results wr on wr.task_id=v_task.id and wr.crop_cycle_id=u.crop_cycle_id
  left join atlas.crop_cycle_yield_forecast yf on yf.crop_cycle_id=u.crop_cycle_id
  left join atlas.crop_cycles cc on cc.id=u.crop_cycle_id
  left join atlas.crop_profiles cp on cp.id=cc.crop_profile_id;

  return jsonb_build_object(
    'contractVersion','weekly_harvest_round_v2','taskId',v_task.id,'status',v_task.status,'dueDate',v_task.due_date,
    'rows',v_rows,'totalRows',v_total,'resolvedRows',v_resolved,'complete',v_total>0 and v_total=v_resolved,'operatorMode',p_operator_mode,
    'truthBoundary',jsonb_build_object(
      'oneWorkerFacingHarvestCard',true,'cropRowsAreNotTasks',true,'cropCycleTruthRemainsCanonical',true,
      'cutFlowerUseTagRequired',true,'cropExhaustedLeavesCard',true,'positiveBucketCountIsHarvestResult',true,
      'remainingSupplyComesFromYieldForecast',true,'unresolvedBucketQuantityNeverInventsStems',true,
      'onlySelectableExceptions',jsonb_build_array('not_ready','deadheaded','crop_exhausted'),'bucketIncrement',0.5
    )
  );
end;
$function$;

update atlas.crop_profiles
set rows_per_3ft_bed=3,
    in_row_spacing_in=9,
    expected_stems_per_plant=4,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'spacing_source','Johnny''s Selected Seeds — Zinnia Cut-Flower Production / Key Growing Information',
      'spacing_source_checked_on','2026-08-29',
      'yield_source','Atlas California Giant profile + conservative cross-variety planning proxy',
      'forecast_quantity_kind','expected_seasonal_stems',
      'forecast_confidence','planning_proxy',
      'yield_reforecast_from_actuals',true
    ),updated_at=now()
where stable_key='zinnia_cut_flower_generic';

update atlas.crop_profiles
set rows_per_3ft_bed=3,
    in_row_spacing_in=12,
    expected_stems_per_plant=3,
    metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'spacing_source','Mississippi State Extension — plumosa celosia continuous-harvest spacing',
      'spacing_source_checked_on','2026-08-29',
      'yield_source','conservative mixed branching-celosia planning floor; revise from Elm actuals',
      'forecast_quantity_kind','conservative_seasonal_stem_floor',
      'forecast_confidence','low_planning_proxy',
      'yield_reforecast_from_actuals',true
    ),updated_at=now()
where stable_key='celosia_cut_flower';

insert into atlas.production_tray_batch_locations(farm_id,tray_batch_id,location_object_id,position_label,placed_at,metadata)
select tb.farm_id,tb.id,tb.source_object_id,tb.batch_label,now(),
       jsonb_build_object('source','tray_location_reconciliation_v1','location_basis','source_object_no_move_record','confidence','provisional','recorded_on','2026-08-29')
from atlas.production_tray_batches tb
join atlas.production_lots pl on pl.id=tb.production_lot_id
where pl.stable_key in ('snapdragon_chantilly_overwinter_2026_live','snapdragon_first_lady_overwinter_2026_live','snapdragon_potomac_overwinter_2026_live','snapdragon_rocket_overwinter_2026_live')
  and tb.source_object_id is not null
  and not exists(select 1 from atlas.production_tray_batch_locations l where l.tray_batch_id=tb.id and l.removed_at is null);

do $block$
declare v_program_id uuid;
begin
  select id into v_program_id from atlas.production_programs
  where farm_id=(select id from atlas.farms where stable_key='elm_farm') and stable_key='overwinter_2026_snapdragon_program' limit 1;
  if v_program_id is not null then perform atlas.sync_production_bed_preparation_tasks_v1(v_program_id); end if;
end;
$block$;

update atlas.object_state os
set decision_required=false,
    metadata=coalesce(os.metadata,'{}'::jsonb)||jsonb_build_object('decision_reconciled_on','2026-08-29','decision_reconciled_reason','active crop occupancy is explicit and no owner decision remains'),
    updated_at=now()
from atlas.growing_objects go
where os.object_id=go.id
  and go.farm_id=(select id from atlas.farms where stable_key='elm_farm')
  and go.stable_key in ('bb_5','bb_6','bb_7');

update atlas.object_state os
set decision_required=false,
    operational_truth='Occupied and harvest-proven: the active Berry Walk Bed 5 sunflower stand produced a recorded cut on Aug. 28. Preserve remaining deer-damage history, but the bed is no longer an unresolved occupancy decision.',
    operational_truth_source='harvest_evidence_20260828',operational_truth_changed_at=now(),
    metadata=coalesce(os.metadata,'{}'::jsonb)||jsonb_build_object('decision_reconciled_on','2026-08-29','later_harvest_evidence',true,'later_harvest_date','2026-08-28'),updated_at=now()
from atlas.growing_objects go
where os.object_id=go.id and go.farm_id=(select id from atlas.farms where stable_key='elm_farm') and go.stable_key='bw_5';

update atlas.object_state os
set decision_required=false,
    metadata=coalesce(os.metadata,'{}'::jsonb)||jsonb_build_object('decision_reconciled_on','2026-08-29','decision_reconciled_reason','known operational work or capability hold; no owner choice required'),updated_at=now()
from atlas.growing_objects go
where os.object_id=go.id and go.farm_id=(select id from atlas.farms where stable_key='elm_farm')
  and go.stable_key in ('berry_walk_spiral_perennial_pockets','curve_arch_03_left_bed','curve_arch_03_right_bed','eb_sunflower_1','eb_sunflower_2','eb_sunflower_3','eb_sunflower_4','eb_sunflower_5','eb_sunflower_6');

with farm as (select id from atlas.farms where stable_key='elm_farm' limit 1), anna as (
  select fm.id from atlas.farm_memberships fm join farm f on f.id=fm.farm_id where fm.worker_key='anna' and fm.active order by fm.created_at limit 1
)
update atlas.tasks t
set title='Reset Entry Billboard Bed '||(t.metadata->>'serial_position'),
    assigned_membership_id=case when t.metadata->>'serial_position'='1' then (select id from anna) else t.assigned_membership_id end,
    visibility_scope=case when t.metadata->>'serial_position'='1' then 'assigned_worker' else t.visibility_scope end,
    status=case when t.metadata->>'serial_position'='1' and t.status='archived' then 'open' else t.status end,
    blocker_text=case when t.metadata->>'serial_position'='1' then null else t.blocker_text end,
    metadata=(coalesce(t.metadata,'{}'::jsonb)
      - 'archived_reason' - 'serial_weeding_retracted' - 'serial_weeding_retracted_at' - 'serial_weeding_queue_key' - 'material_destination_task_id')
      ||jsonb_build_object(
        'serial_queue_bypass',true,
        'serial_chain_governance','entry_billboard_reset_daily_v1',
        'work_route','weed','work_rhythm','Bed Reset','display_action','Reset','display_title','Entry Billboard Bed '||(t.metadata->>'serial_position'),
        'execution_do','Inspect Entry Billboard Bed '||(t.metadata->>'serial_position')||' and finish the reset.',
        'execution_how',jsonb_build_array(
          'Inspect for live green weed regrowth after prior spraying.',
          'If regrowth is green, re-spray and leave the bed in reset until the weeds are dead.',
          'If growth is dead, clear sprayed biomass and excess loose/decomposed material while preserving usable soil.',
          'If the intended material destination is unavailable, stage usable excess material without blocking this bed reset.',
          'Reshape and level the bed and adjacent walkway; finish only when planting-ready.'
        ),
        'execution_done_when','The bed is clear of live weed pressure, dead biomass is removed, the bed/walkway are shaped, and the bed is planting-ready.',
        'material_destination_policy','stage_if_destination_unavailable',
        'reset_truth_source','owner_truth_20260829'
      ),updated_at=now()
where t.farm_id=(select id from farm) and t.metadata->>'serial_chain_key'='entry_billboard_reset_daily_v1';

update atlas.planned_work_occurrences o
set state='released',released_task_id=t.id,released_at=coalesce(o.released_at,now()),
    planned_due_date=coalesce(o.planned_due_date,t.due_date),not_before_date=coalesce(o.not_before_date,t.due_date),
    metadata=(coalesce(o.metadata,'{}'::jsonb)-'serialWeedingQueued'-'serialWeedingQueuedAt'-'serialWeedingQueueKey')||jsonb_build_object('serialQueueBypass',true,'releaseReason','entry_billboard_chain_owns_sequence'),updated_at=now()
from atlas.tasks t
where t.planned_occurrence_id=o.id
  and t.farm_id=(select id from atlas.farms where stable_key='elm_farm')
  and t.metadata->>'serial_chain_key'='entry_billboard_reset_daily_v1'
  and t.metadata->>'serial_position'='1';

update atlas.task_release_queue_items qi
set state='skipped',task_id=null,completed_at=coalesce(qi.completed_at,now()),
    metadata=coalesce(qi.metadata,'{}'::jsonb)||jsonb_build_object('skipped_by','entry_billboard_chain_owns_sequence','skipped_at',now()),updated_at=now()
from atlas.planned_work_occurrences o
join atlas.tasks t on t.planned_occurrence_id=o.id
where qi.planned_occurrence_id=o.id
  and qi.queue_key='anna_weeding_rotation'
  and t.farm_id=(select id from atlas.farms where stable_key='elm_farm')
  and t.metadata->>'serial_chain_key'='entry_billboard_reset_daily_v1';

do $block$
declare r record;
begin
  for r in select id from atlas.tasks where farm_id=(select id from atlas.farms where stable_key='elm_farm') and metadata->>'serial_chain_key'='entry_billboard_reset_daily_v1' and metadata->>'serial_position'<>'1' loop
    perform atlas.reconcile_task_prerequisite_gate_v1(r.id,now());
  end loop;
end;
$block$;