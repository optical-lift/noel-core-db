create or replace function atlas.sync_snapdragon_bed_preparation_tasks_v1(p_program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'atlas','public'
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
  select * into v_program from atlas.production_programs where id=p_program_id and stable_key='spring_2027_snapdragon_program';
  if v_program.id is null then raise exception 'Spring 2027 Snapdragon program not found'; end if;
  select organization_id into v_org from atlas.farms where id=v_program.farm_id;
  select fm.id,fm.worker_key into v_anna,v_worker_key from atlas.farm_memberships fm where fm.farm_id=v_program.farm_id and fm.active and fm.worker_key='anna' order by fm.created_at limit 1;

  for v_assignment in
    select a.id assignment_id,a.production_lot_id,a.object_id,a.quantity_assigned,a.planned_transplant_date,req.preparation_due_date,
           pl.stable_key production_lot_key,pl.lot_label,go.label object_label,go.zone_id
    from atlas.production_bed_assignments a
    join atlas.production_lots pl on pl.id=a.production_lot_id
    join atlas.production_capacity_requirements req on req.id=a.requirement_id
    join atlas.growing_objects go on go.id=a.object_id
    where pl.program_id=p_program_id and a.assignment_status='assigned' and req.preparation_due_date is not null
    order by req.preparation_due_date,pl.succession_number,go.sort_order
  loop
    v_title:='Prepare '||v_assignment.object_label||' for '||v_assignment.lot_label;
    v_metadata:=jsonb_build_object(
      'task_key','capacity_bed_prep_'||v_assignment.assignment_id::text,
      'anna_task',v_anna is not null,'owner_task',v_anna is null,'assigned_to',coalesce(v_worker_key,'Owner'),
      'work_route','prepare','work_rhythm','Bed Preparation','display_action','Prepare bed','display_subject',v_assignment.object_label,
      'display_detail',v_assignment.quantity_assigned::text||' bed-ft for transplant '||v_assignment.planned_transplant_date::text,
      'collection_zone',v_assignment.object_label,'production_program_id',p_program_id,'production_lot_id',v_assignment.production_lot_id,
      'production_lot_key',v_assignment.production_lot_key,'production_bed_assignment_id',v_assignment.assignment_id,
      'destination_object_id',v_assignment.object_id,'required_bed_feet',v_assignment.quantity_assigned,
      'target_transplant_date',v_assignment.planned_transplant_date,'relationship_kind','production_capacity_preparation'
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
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('bed_preparation_occurrence_id',v_occurrence_id,'bed_preparation_task_id',v_task_id,'bed_preparation_synced_at',now()),updated_at=now()
    where id=v_assignment.assignment_id;
  end loop;

  return jsonb_build_object('programId',p_program_id,'occurrencesAuthored',v_authored,'tasksMaterialized',v_materialized,'tasksCreated',v_materialized,'tasksUpdated',0);
end;
$function$;