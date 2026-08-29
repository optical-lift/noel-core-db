create or replace function atlas.ensure_production_care_task_v1(p_production_lot_id uuid,p_care_kind text)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_policy atlas.production_care_policies%rowtype;
  v_task_id uuid;
  v_source atlas.tasks%rowtype;
  v_role text;
  v_action text;
  v_action_key text;
  v_title text;
  v_due date;
  v_today date:=(now() at time zone 'America/Chicago')::date;
  v_next jsonb;
  v_objects jsonb;
  v_cycles jsonb;
begin
  if p_care_kind not in ('watering','weeding','pinching','support','fertility') then raise exception 'Unsupported production care kind' using errcode='22023'; end if;
  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  select * into v_policy from atlas.production_care_policies where production_lot_id=p_production_lot_id and care_kind=p_care_kind;
  if v_lot.id is null or v_policy.id is null or v_policy.current_status not in ('due','needs_attention') then return null; end if;

  v_role:=case p_care_kind when 'watering' then 'water_care' when 'weeding' then 'weed_care' when 'pinching' then 'pinch_care' when 'support' then 'support_care' else 'fertility_care' end;
  select t.id into v_task_id from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id where plt.production_lot_id=v_lot.id and plt.link_role=v_role and t.status in ('open','blocked') order by t.created_at desc limit 1;
  if v_task_id is not null then return v_task_id; end if;

  select t.* into v_source from atlas.production_lot_tasks plt join atlas.tasks t on t.id=plt.task_id where plt.production_lot_id=v_lot.id and plt.link_role in ('establishment_check','harvest_readiness','transplant') order by t.created_at desc limit 1;
  v_action:=case p_care_kind when 'watering' then 'Water' when 'weeding' then 'Weed' when 'pinching' then 'Pinch' when 'support' then 'Support' else 'Feed' end;
  v_action_key:=case p_care_kind when 'watering' then 'water' when 'weeding' then 'weed' when 'pinching' then 'pinch' else 'maintain' end;
  v_title:=v_action||' field cohort — '||v_lot.lot_label;
  v_due:=coalesce(v_policy.next_due_date,v_policy.due_date,v_today);

  select coalesce(jsonb_agg(jsonb_build_object('object_id',s.object_id,'role','target') order by s.object_id),'[]'::jsonb),
         coalesce(jsonb_agg(jsonb_build_object('crop_cycle_id',s.crop_cycle_id,'role','affects','confidence','confirmed','source','production_stage_engine','metadata',jsonb_build_object('care_policy_id',v_policy.id)) order by s.crop_cycle_id),'[]'::jsonb)
  into v_objects,v_cycles
  from atlas.production_field_stands s
  where s.production_lot_id=v_lot.id and s.current_plants>0 and s.stand_status not in ('failed','cleared');

  v_next:=atlas.author_production_work_occurrence_v1(
    v_lot.farm_id,'field-care-'||p_care_kind,'production:field-care:'||v_policy.id::text,
    v_title,v_due,v_due,
    'production_care_policy',v_policy.id,'production_field_care',v_action_key,'standard',case when v_policy.required_before_harvest then 'high' else 'medium' end,
    coalesce(v_source.visibility_scope,'assigned_worker'),v_source.assigned_membership_id,v_source.assigned_user_id,coalesce(v_source.organization_id,(select organization_id from atlas.farms where id=v_lot.farm_id)),
    v_action||' every linked living bed and record any revised plant counts.',
    jsonb_build_object('task_key','production_care_'||v_policy.id::text,'task_style','production_field_care','production_lot_id',v_lot.id,'production_lot_key',v_lot.stable_key,'production_care_policy_id',v_policy.id,'care_action',p_care_kind,'required_before_harvest',v_policy.required_before_harvest,'display_action',v_action,'display_subject',v_lot.lot_label,'display_detail',case when v_policy.required_before_harvest then 'Required before harvest readiness' else 'Field monitoring response' end,'collection_zone','Production beds'),
    jsonb_build_object('task_objects',coalesce(v_objects,'[]'::jsonb),'task_crop_cycles',coalesce(v_cycles,'[]'::jsonb),'production_lot_tasks',jsonb_build_array(jsonb_build_object('production_lot_id',v_lot.id,'link_role',v_role,'source','production_stage_engine','metadata',jsonb_build_object('care_policy_id',v_policy.id))),'task_resource_requirements',jsonb_build_array(),'production_harvest_lot_tasks',jsonb_build_array()),
    case when v_policy.required_before_harvest then 'required' else 'process_continuation' end,'dependency',
    case when v_policy.freshness_days is not null then v_due+v_policy.freshness_days else null end,
    jsonb_build_object('kind','production_care','careKind',p_care_kind,'effect',case when v_policy.required_before_harvest then 'Harvest readiness remains blocked until this required care is current.' else 'The field cohort has a recorded care need.' end),true
  );
  v_task_id:=nullif(v_next->>'taskId','')::uuid;
  update atlas.production_care_policies
  set source_task_id=coalesce(v_task_id,source_task_id),metadata=metadata||jsonb_build_object('source_occurrence_id',v_next->>'occurrenceId','reservoir_authored_at',now()),updated_at=now()
  where id=v_policy.id;
  return v_task_id;
end;
$function$;