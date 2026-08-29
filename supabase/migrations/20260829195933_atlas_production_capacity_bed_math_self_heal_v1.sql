create or replace function atlas.reconcile_production_capacity_work_v1(p_production_lot_id uuid,p_as_of_date date default null)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_today date:=coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_prior text:=current_setting('atlas.production_reconciler_active',true);
  v_lot atlas.production_lots%rowtype;
  v_req atlas.production_capacity_requirements%rowtype;
  v_assignment record;
  v_anna atlas.farm_memberships%rowtype;
  v_org uuid;
  v_next jsonb;
  v_due date;
  v_not_before date;
  v_work jsonb:='[]'::jsonb;
  v_readiness_observation_id uuid;
  v_surviving numeric;
  v_rows numeric;
  v_spacing numeric;
  v_bed_feet numeric;
begin
  perform set_config('atlas.production_reconciler_active','on',true);
  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;
  if v_lot.current_stage<>'transplant_ready' or v_lot.lifecycle_status<>'active' then
    perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
    return jsonb_build_object('productionLotId',v_lot.id,'work',v_work,'state','not_waiting_for_field_capacity');
  end if;

  select * into v_req
  from atlas.production_capacity_requirements
  where production_lot_id=v_lot.id and capacity_kind='bed_feet'
  order by created_at desc
  limit 1;

  if v_req.id is not null and (v_req.calculation_status not in ('calculated','confirmed') or v_req.quantity_needed is null) then
    select ro.id,ro.surviving_seedlings
    into v_readiness_observation_id,v_surviving
    from atlas.production_readiness_observations ro
    where ro.production_lot_id=v_lot.id
      and ro.observation_outcome='ready'
      and ro.surviving_seedlings is not null
      and ro.surviving_seedlings>0
    order by ro.observed_date desc,ro.created_at desc
    limit 1;

    select cm.value into v_rows
    from atlas.capacity_measurements cm
    where cm.farm_id=v_lot.farm_id and cm.stable_key='snapdragon_rows_per_three_foot_bed'
    order by cm.updated_at desc
    limit 1;

    select cm.value into v_spacing
    from atlas.capacity_measurements cm
    where cm.farm_id=v_lot.farm_id and cm.stable_key='snapdragon_in_row_spacing_inches'
    order by cm.updated_at desc
    limit 1;

    if v_surviving is not null and v_rows is not null and v_rows>0 and v_spacing is not null and v_spacing>0 then
      v_bed_feet:=ceil((v_surviving*v_spacing/12.0)/v_rows);
      update atlas.production_capacity_requirements
      set quantity_needed=v_bed_feet,
          calculation_status='confirmed',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
            'bed_math_authority','production_reconciler',
            'bed_math_reason','capacity_measurements_recovered',
            'readiness_observation_id',v_readiness_observation_id,
            'surviving_seedlings',v_surviving,
            'rows_per_three_foot_bed',v_rows,
            'in_row_spacing_inches',v_spacing,
            'calculated_bed_feet',v_bed_feet,
            'bed_math_reconciled_at',now()
          ),
          updated_at=now()
      where id=v_req.id;

      select * into v_req from atlas.production_capacity_requirements where id=v_req.id;
      perform atlas.refresh_production_transplant_gate_v1(v_lot.id);
      v_work:=v_work||jsonb_build_array(jsonb_build_object(
        'workKey','bed-math-reconciled',
        'requirementId',v_req.id,
        'quantityNeeded',v_req.quantity_needed,
        'unit',v_req.unit,
        'readinessObservationId',v_readiness_observation_id
      ));
    end if;
  end if;

  if v_req.id is null or v_req.calculation_status not in ('calculated','confirmed') or v_req.quantity_needed is null then
    perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
    return jsonb_build_object('productionLotId',v_lot.id,'work',v_work,'state','waiting_bed_math');
  end if;

  select * into v_anna from atlas.farm_memberships where farm_id=v_lot.farm_id and worker_key='anna' and active order by updated_at desc limit 1;
  select organization_id into v_org from atlas.farms where id=v_lot.farm_id;

  for v_assignment in
    select a.*,go.label as object_label,go.zone_id
    from atlas.production_bed_assignments a
    join atlas.growing_objects go on go.id=a.object_id
    where a.production_lot_id=v_lot.id and a.assignment_status='assigned'
    order by a.planned_transplant_date,go.sort_order,a.created_at
  loop
    v_due:=coalesce(v_req.preparation_due_date,v_assignment.planned_transplant_date,v_req.required_by_date,v_today);
    v_not_before:=least(v_due,v_today);
    v_next:=atlas.author_production_work_occurrence_v1(
      v_lot.farm_id,'bed-preparation','production:bed-preparation:'||v_assignment.id::text,
      'Prepare '||v_assignment.object_label||' for '||v_lot.lot_label,
      v_due,v_not_before,
      'production_bed_assignment',v_assignment.id,'bed_preparation','prepare','standard','high',
      case when v_anna.id is null then 'owner' else 'assigned_worker' end,v_anna.id,v_anna.user_id,v_org,
      'Weed, clear, prepare, and confirm water access for '||v_assignment.quantity_assigned::text||' bed-feet before transplant.',
      jsonb_build_object(
        'task_key','capacity_bed_prep_'||v_assignment.id::text,
        'anna_task',v_anna.id is not null,'owner_task',v_anna.id is null,
        'assigned_to',case when v_anna.id is null then 'Owner' else 'Anna' end,
        'assignee_key',case when v_anna.id is null then null else 'anna' end,
        'executor_worker_key',case when v_anna.id is null then null else 'anna' end,
        'executor_membership_id',v_anna.id,
        'work_route','prepare','work_rhythm','Bed Preparation',
        'display_action','Prepare bed','display_subject',v_assignment.object_label,
        'display_detail',v_assignment.quantity_assigned::text||' bed-ft for transplant '||coalesce(v_assignment.planned_transplant_date::text,v_req.required_by_date::text,'date unresolved'),
        'collection_zone',v_assignment.object_label,
        'production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,
        'production_bed_assignment_id',v_assignment.id,'destination_object_id',v_assignment.object_id,
        'required_bed_feet',v_assignment.quantity_assigned,'target_transplant_date',v_assignment.planned_transplant_date,
        'relationship_kind','production_capacity_preparation','next_action_authority','production_reconciler'
      ),
      jsonb_build_object(
        'task_objects',jsonb_build_array(jsonb_build_object('object_id',v_assignment.object_id,'role','target')),
        'task_crop_cycles',jsonb_build_array(),
        'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role','bed_preparation','source','production_reconciler','metadata',jsonb_build_object('production_bed_assignment_id',v_assignment.id))),
        'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()
      ),
      'process_continuation','dependency',coalesce(v_assignment.planned_transplant_date,v_req.window_end,v_req.required_by_date),
      jsonb_build_object('kind','destination_preparation','effect','The assigned bed must be prepared before this production lot can pass its transplant gate.'),false
    );
    update atlas.production_bed_assignments
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('bed_preparation_occurrence_id',v_next->>'occurrenceId','bed_preparation_task_id',v_next->>'taskId','bed_preparation_synced_at',now(),'bed_preparation_authority','production_reconciler'),updated_at=now()
    where id=v_assignment.id;
    v_work:=v_work||jsonb_build_array(jsonb_build_object('workKey','bed-preparation','assignmentId',v_assignment.id,'occurrenceId',v_next->>'occurrenceId'));
  end loop;

  perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
  return jsonb_build_object('productionLotId',v_lot.id,'authority','production_reconciler','work',v_work);
end;
$function$;