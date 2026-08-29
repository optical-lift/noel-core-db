create or replace function atlas.author_production_work_occurrence_v1(
  p_farm_id uuid,
  p_work_key text,
  p_occurrence_key text,
  p_title text,
  p_due_date date,
  p_not_before_date date,
  p_source_kind text,
  p_source_id uuid,
  p_task_type text,
  p_action_key text,
  p_work_class text,
  p_priority text,
  p_visibility_scope text,
  p_assigned_membership_id uuid,
  p_assigned_user_id uuid,
  p_organization_id uuid,
  p_note text,
  p_metadata jsonb default '{}'::jsonb,
  p_relation_payload jsonb default '{}'::jsonb,
  p_work_lane text default 'process_continuation',
  p_commitment_kind text default 'dependency',
  p_latest_lawful_date date default null,
  p_miss_consequence jsonb default '{}'::jsonb,
  p_release_if_due boolean default false
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_reconciler_active boolean := coalesce(current_setting('atlas.production_reconciler_active', true),'')='on';
  v_governed boolean;
  v_existing atlas.planned_work_occurrences%rowtype;
  v_existing_visibility text;
  v_existing_membership uuid;
  v_existing_user uuid;
  v_existing_org uuid;
  v_effective_latest date:=p_latest_lawful_date;
  v_effective_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
  v_effective_miss jsonb:=coalesce(p_miss_consequence,'{}'::jsonb);
begin
  v_governed := p_work_key in (
    'germination','seedling-care','owner-reseed-decision','owner-lifecycle-gap','owner-pot-up-method','pot-up',
    'hardening','transplant-readiness','owner-seedling-recovery','owner-bed-math','bed-preparation',
    'transplant','establishment','field-water','field-weed','owner-field-failure',
    'owner-harvest-rules','harvest-readiness'
  ) or p_work_key like 'field-care-%';

  select * into v_existing
  from atlas.planned_work_occurrences
  where farm_id=p_farm_id and occurrence_key=p_occurrence_key
  order by created_at desc limit 1;

  if v_governed and not v_reconciler_active then
    if v_existing.id is not null then
      return jsonb_build_object('occurrenceId',v_existing.id,'taskId',v_existing.released_task_id,'state',v_existing.state,'authority','production_reconciler','deduplicated',true);
    end if;
    return jsonb_build_object('occurrenceId',null,'taskId',null,'state','deferred_to_reconciler','authority','production_reconciler','deduplicated',false);
  end if;

  if v_existing.id is not null then
    v_existing_visibility:=nullif(v_existing.task_payload->>'visibility_scope','');
    begin v_existing_membership:=nullif(v_existing.task_payload->>'assigned_membership_id','')::uuid; exception when others then v_existing_membership:=null; end;
    begin v_existing_user:=nullif(v_existing.task_payload->>'assigned_user_id','')::uuid; exception when others then v_existing_user:=null; end;
    begin v_existing_org:=nullif(v_existing.task_payload->>'organization_id','')::uuid; exception when others then v_existing_org:=null; end;
    if v_existing_membership is not null or v_existing_user is not null then
      p_visibility_scope:=coalesce(v_existing_visibility,p_visibility_scope,'assigned_worker');
      p_assigned_membership_id:=coalesce(v_existing_membership,p_assigned_membership_id);
      p_assigned_user_id:=coalesce(v_existing_user,p_assigned_user_id);
      p_organization_id:=coalesce(v_existing_org,p_organization_id);
      v_effective_metadata:=v_effective_metadata||jsonb_build_object('execution_custody_preserved',true,'execution_custody_source_occurrence_id',v_existing.id);
    end if;
  end if;

  if v_effective_latest is not null and p_due_date is not null and v_effective_latest<p_due_date then
    v_effective_metadata:=v_effective_metadata||jsonb_build_object('recovered_missed_window',true,'original_latest_lawful_date',v_effective_latest,'recovery_due_date',p_due_date,'recovery_authority','production_work_authoring_boundary');
    v_effective_miss:=v_effective_miss||jsonb_build_object('windowMissed',true,'originalLatestLawfulDate',v_effective_latest,'recoveredOperationalDeadline',p_due_date);
    v_effective_latest:=p_due_date;
  end if;

  return atlas.author_production_work_occurrence_internal_v1(
    p_farm_id,p_work_key,p_occurrence_key,p_title,p_due_date,p_not_before_date,p_source_kind,p_source_id,
    p_task_type,p_action_key,p_work_class,p_priority,p_visibility_scope,p_assigned_membership_id,p_assigned_user_id,
    p_organization_id,p_note,v_effective_metadata,p_relation_payload,p_work_lane,p_commitment_kind,v_effective_latest,
    v_effective_miss,p_release_if_due
  );
end;
$function$;
revoke all on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) from public,anon,authenticated;
grant execute on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) to postgres,service_role;

create or replace function atlas.reconcile_production_capacity_work_v1(p_production_lot_id uuid,p_as_of_date date default null) returns jsonb
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
begin
  perform set_config('atlas.production_reconciler_active','on',true);
  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  if v_lot.id is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;
  if v_lot.current_stage<>'transplant_ready' or v_lot.lifecycle_status<>'active' then
    perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
    return jsonb_build_object('productionLotId',v_lot.id,'work',v_work,'state','not_waiting_for_field_capacity');
  end if;
  select * into v_req from atlas.production_capacity_requirements where production_lot_id=v_lot.id and capacity_kind='bed_feet' limit 1;
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
revoke all on function atlas.reconcile_production_capacity_work_v1(uuid,date) from public,anon,authenticated,service_role;
grant execute on function atlas.reconcile_production_capacity_work_v1(uuid,date) to postgres;

create or replace function atlas.reconcile_production_work_v1(p_production_lot_id uuid,p_as_of_date date default null) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_prop jsonb;
  v_down jsonb;
  v_capacity jsonb;
  v_cleanup jsonb;
  v_stage text;
begin
  if p_production_lot_id is null then raise exception 'Production lot is required' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended('atlas.production.reconcile:entry:'||p_production_lot_id::text,0));
  select current_stage into v_stage from atlas.production_lots where id=p_production_lot_id;
  if v_stage is null then raise exception 'Production lot was not found' using errcode='P0002'; end if;

  v_prop:=atlas.reconcile_production_propagation_work_v1(p_production_lot_id,p_as_of_date);
  if v_stage in ('germination_pending','reseed_decision','seedling_care') then
    v_down:=jsonb_build_object('currentStage',v_stage,'work','[]'::jsonb,'transplantGate',null,'harvestGate',null);
  else
    v_down:=atlas.reconcile_production_work_downstream_v1(p_production_lot_id,p_as_of_date);
  end if;
  v_capacity:=atlas.reconcile_production_capacity_work_v1(p_production_lot_id,p_as_of_date);
  v_cleanup:=atlas.cancel_obsolete_production_propagation_work_v1(p_production_lot_id);

  return jsonb_build_object(
    'productionLotId',p_production_lot_id,
    'authority','production_reconciler',
    'currentStage',coalesce(v_down->>'currentStage',v_prop->>'currentStage',v_stage),
    'work',coalesce(v_prop->'work','[]'::jsonb)||coalesce(v_down->'work','[]'::jsonb)||coalesce(v_capacity->'work','[]'::jsonb),
    'transplantGate',v_down->'transplantGate','harvestGate',v_down->'harvestGate','cleanup',v_cleanup
  );
end;
$function$;
revoke all on function atlas.reconcile_production_work_v1(uuid,date) from public,anon,authenticated;
grant execute on function atlas.reconcile_production_work_v1(uuid,date) to postgres,service_role;

comment on function atlas.reconcile_production_capacity_work_v1(uuid,date) is 'Derives destination preparation work from confirmed production bed assignments. Assignment truth creates preparation obligations; preparation completion controls the transplant gate.';